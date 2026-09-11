import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One FFT capture frame from Android's Visualizer (0..255 per bin).
class AudioFftFrame {
  const AudioFftFrame({
    required this.magnitudes,
    required this.sampleRate,
  });

  final Uint8List magnitudes;
  final int sampleRate;
}

/// Bridges Android Visualizer FFT data into Flutter.
class AudioFftBridge {
  AudioFftBridge._();

  static const _method =
      MethodChannel('com.dancebabyradio.app/audio_fft');
  static const _events =
      EventChannel('com.dancebabyradio.app/audio_fft_stream');

  static StreamSubscription<dynamic>? _eventSub;
  static final _controller = StreamController<AudioFftFrame>.broadcast();
  static int? _activeSessionId;
  static bool _started = false;

  static Stream<AudioFftFrame> get frames => _controller.stream;

  static Future<void> bindSession(int? sessionId) async {
    if (sessionId == null || sessionId <= 0) {
      await stop();
      return;
    }
    if (_started && _activeSessionId == sessionId) return;

    await stop();
    _activeSessionId = sessionId;

    try {
      _eventSub = _events.receiveBroadcastStream().listen(
        (dynamic raw) {
          if (raw is! Map) return;
          final fft = raw['fft'];
          final sampleRate = raw['sampleRate'];
          if (fft == null) return;

          final magnitudes = fft is Uint8List
              ? fft
              : Uint8List.fromList(List<int>.from(fft as List));
          final rate = sampleRate is int
              ? sampleRate
              : int.tryParse('$sampleRate') ?? 44100;

          if (!_controller.isClosed) {
            _controller.add(AudioFftFrame(
              magnitudes: magnitudes,
              sampleRate: rate,
            ));
          }
        },
        onError: (Object error) {
          debugPrint('AudioFftBridge stream error: $error');
        },
      );

      await _method.invokeMethod<void>('start', {'sessionId': sessionId});
      _started = true;
    } catch (error) {
      debugPrint('AudioFftBridge.start failed: $error');
      await stop();
    }
  }

  static Future<void> stop() async {
    _started = false;
    _activeSessionId = null;
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _method.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
