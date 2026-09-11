package com.dancebabyradio.app

import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Bridges Android's [Visualizer] FFT capture to Flutter so the LED light-dance
 * background can react to the active just_audio / ExoPlayer session — the same
 * role Web Audio's AnalyserNode plays in the Nuxt LedLights component.
 */
class MainActivity : AudioServiceActivity() {
    private val methodChannelName = "com.dancebabyradio.app/audio_fft"
    private val eventChannelName = "com.dancebabyradio.app/audio_fft_stream"

    private var visualizer: Visualizer? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val sessionId = call.argument<Int>("sessionId") ?: 0
                        try {
                            startVisualizer(sessionId)
                            result.success(true)
                        } catch (error: Exception) {
                            stopVisualizer()
                            result.error("viz_start", error.message, null)
                        }
                    }
                    "stop" -> {
                        stopVisualizer()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startVisualizer(sessionId: Int) {
        stopVisualizer()
        if (sessionId <= 0) return

        val viz = Visualizer(sessionId)
        val range = Visualizer.getCaptureSizeRange()
        viz.captureSize = range[1]

        val rate = Visualizer.getMaxCaptureRate().coerceAtMost(20_000)
        viz.setDataCaptureListener(
            object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(
                    visualizer: Visualizer?,
                    waveform: ByteArray?,
                    samplingRate: Int,
                ) {
                    // unused — frequency bins drive the LED dance
                }

                override fun onFftDataCapture(
                    visualizer: Visualizer?,
                    fft: ByteArray?,
                    samplingRate: Int,
                ) {
                    if (fft == null || eventSink == null) return

                    // Android FFT layout: [DC, Nyquist, re1, im1, re2, im2, ...]
                    val binCount = fft.size / 2
                    val magnitudes = ByteArray(binCount)
                    magnitudes[0] = abs(fft[0].toInt()).coerceIn(0, 255).toByte()
                    if (binCount > 1) {
                        magnitudes[binCount - 1] =
                            abs(fft[1].toInt()).coerceIn(0, 255).toByte()
                    }
                    var i = 1
                    while (i < binCount - 1) {
                        val re = fft[i * 2].toInt()
                        val im = fft[i * 2 + 1].toInt()
                        val mag = min(255, (sqrt((re * re + im * im).toDouble()) * 2.2).toInt())
                        magnitudes[i] = mag.toByte()
                        i++
                    }

                    val sampleRateHz = (samplingRate / 1000).coerceAtLeast(1)
                    val payload = hashMapOf<String, Any>(
                        "fft" to magnitudes,
                        "sampleRate" to sampleRateHz,
                    )
                    mainHandler.post { eventSink?.success(payload) }
                }
            },
            rate,
            false,
            true,
        )
        viz.enabled = true
        visualizer = viz
    }

    private fun stopVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {
            // OEM quirks while releasing — ignore
        }
        visualizer = null
    }

    override fun onDestroy() {
        stopVisualizer()
        super.onDestroy()
    }
}
