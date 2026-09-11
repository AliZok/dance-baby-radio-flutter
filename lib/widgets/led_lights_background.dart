import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';

import '../services/audio_fft_bridge.dart';
import '../services/audio_service.dart';

/// Background LED equalizer / light-dance, ported from the Nuxt `LedLights`
/// canvas. Palette: green → cyan-blue → purple.
class LedLightsBackground extends StatefulWidget {
  const LedLightsBackground({
    Key? key,
    required this.audioService,
  }) : super(key: key);

  final AudioService audioService;

  @override
  State<LedLightsBackground> createState() => _LedLightsBackgroundState();
}

class _LedLightsBackgroundState extends State<LedLightsBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  StreamSubscription<int?>? _sessionSub;
  StreamSubscription<AudioFftFrame>? _fftSub;
  Duration _lastElapsed = Duration.zero;

  Uint8List? _freq;
  int _sampleRate = 44100;
  bool _hasLiveFft = false;
  double _fftStaleFor = 0;

  final List<double> _displayed = [];
  final List<double> _peaks = [];
  final List<_Sparkle> _sparkles = [];

  double _glow = 0;
  double _flash = 0;
  double _kickEnv = 0;
  double _bassEma = 0;
  double _bassPeakPrev = 0;
  double _lastKickAt = 0;
  double _breath = 0;
  double _nowSec = 0;
  double _highs = 0;

  List<List<int>>? _logRanges;
  String _logRangesKey = '';
  Size _lastSize = Size.zero;
  AudioPlayer? _boundPlayer;

  @override
  void initState() {
    super.initState();
    widget.audioService.addListener(_onAudioChanged);
    _ticker = createTicker(_onTick)..start();
    _bindSession(widget.audioService.activePlayer);
    _fftSub = AudioFftBridge.frames.listen(_onFftFrame);
  }

  @override
  void didUpdateWidget(covariant LedLightsBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioService != widget.audioService) {
      oldWidget.audioService.removeListener(_onAudioChanged);
      widget.audioService.addListener(_onAudioChanged);
      _bindSession(widget.audioService.activePlayer);
    }
  }

  @override
  void dispose() {
    widget.audioService.removeListener(_onAudioChanged);
    _ticker.dispose();
    _sessionSub?.cancel();
    _fftSub?.cancel();
    unawaited(AudioFftBridge.stop());
    super.dispose();
  }

  void _onAudioChanged() {
    _bindSession(widget.audioService.activePlayer);
  }

  void _bindSession(AudioPlayer player) {
    if (identical(_boundPlayer, player) && _sessionSub != null) {
      unawaited(AudioFftBridge.bindSession(player.androidAudioSessionId));
      return;
    }
    _boundPlayer = player;
    _sessionSub?.cancel();
    _sessionSub = player.androidAudioSessionIdStream.listen((id) {
      unawaited(AudioFftBridge.bindSession(id));
    });
    unawaited(AudioFftBridge.bindSession(player.androidAudioSessionId));
  }

  void _onFftFrame(AudioFftFrame frame) {
    _freq = frame.magnitudes;
    _sampleRate = frame.sampleRate;
    _hasLiveFft = true;
    _fftStaleFor = 0;
  }

  void _onTick(Duration elapsed) {
    final dt = _lastElapsed == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastElapsed = elapsed;
    _nowSec = elapsed.inMicroseconds / 1e6;
    _fftStaleFor += dt;
    if (_fftStaleFor > 0.45) _hasLiveFft = false;
    if (!mounted) return;
    setState(() => _advance(dt));
  }

  void _seedSparkles(Size size) {
    if ((_lastSize.width - size.width).abs() < 1 &&
        (_lastSize.height - size.height).abs() < 1 &&
        _sparkles.isNotEmpty) {
      return;
    }
    _lastSize = size;
    final count = size.width < 768 ? 28 : 48;
    _sparkles
      ..clear()
      ..addAll(List.generate(count, (i) {
        final n = math.sin(i * 127.1 + 311.7) * 43758.5453;
        final n2 = math.sin(i * 269.5 + 19.2) * 23421.631;
        final u = n - n.floorToDouble();
        final v = n2 - n2.floorToDouble();
        return _Sparkle(
          x: u * size.width,
          y: 0.08 * size.height + v * size.height * 0.52,
          s: 1.1 + u * 1.8,
          band: 0.55 + v * 0.4,
        );
      }));
  }

  List<List<int>> _getLogRanges(int binCount, int sampleRate, int barCount) {
    final key = '$binCount:$sampleRate:$barCount';
    if (_logRanges != null && _logRangesKey == key) return _logRanges!;

    final ranges = <List<int>>[];
    final bassBars = math.min(8, math.max(5, (barCount * 0.2).floor()));
    for (var i = 0; i < bassBars; i++) {
      ranges.add([1 + i, 2 + i]);
    }

    final startBin = 1 + bassBars;
    final minF = math.max(80.0, (startBin / binCount) * (sampleRate / 2));
    final maxF = math.min(16000.0, sampleRate * 0.48);
    final rest = barCount - bassBars;
    for (var i = 0; i < rest; i++) {
      final t0 = i / rest;
      final t1 = (i + 1) / rest;
      final f0 = minF * math.pow(maxF / minF, t0);
      final f1 = minF * math.pow(maxF / minF, t1);
      final b0 = math.max(
        startBin,
        ((f0 / (sampleRate / 2)) * binCount).floor(),
      );
      final b1 = math.max(
        b0 + 1,
        ((f1 / (sampleRate / 2)) * binCount).floor(),
      );
      ranges.add([b0, math.min(binCount, b1)]);
    }
    _logRanges = ranges;
    _logRangesKey = key;
    return ranges;
  }

  double _maxRange(Uint8List freq, int start, int end) {
    final a = start.clamp(0, freq.length);
    final b = end.clamp(0, freq.length);
    if (b <= a) return 0;
    var m = 0;
    for (var i = a; i < b; i++) {
      if (freq[i] > m) m = freq[i];
    }
    return m / 255.0;
  }

  double _avgRange(Uint8List freq, int start, int end) {
    final a = start.clamp(0, freq.length);
    final b = end.clamp(0, freq.length);
    if (b <= a) return 0;
    var sum = 0;
    for (var i = a; i < b; i++) {
      sum += freq[i];
    }
    return sum / (b - a) / 255.0;
  }

  void _ensureBars(int barCount) {
    while (_displayed.length < barCount) {
      _displayed.add(0);
    }
    while (_peaks.length < barCount) {
      _peaks.add(0);
    }
    if (_displayed.length > barCount) {
      _displayed.removeRange(barCount, _displayed.length);
    }
    if (_peaks.length > barCount) {
      _peaks.removeRange(barCount, _peaks.length);
    }
  }

  void _advance(double dt) {
    final playing = widget.audioService.isPlaying;
    final freq = _freq;
    final liveFft = _hasLiveFft && freq != null && freq.isNotEmpty;

    final isMobile = _lastSize.width == 0 || _lastSize.width < 768;
    final barCount = isMobile ? 26 : 42;
    final levels = List<double>.filled(barCount, 0);
    _ensureBars(barCount);

    var bass = 0.0;
    var hasSignal = false;
    _highs = 0;

    if (liveFft) {
      var freqSum = 0;
      for (var i = 1; i < freq.length; i++) {
        freqSum += freq[i];
      }
      hasSignal = freqSum > 8;
      if (hasSignal) {
        final bassPeak = _maxRange(freq, 1, 6);
        _bassEma = _bassEma * 0.9 + bassPeak * 0.1;
        final flux = math.max(0.0, bassPeak - _bassPeakPrev);
        _bassPeakPrev = bassPeak;
        final punch = math.max(0.0, bassPeak - _bassEma * 0.82);
        if ((punch > 0.08 || flux > 0.06) && _nowSec - _lastKickAt > 0.12) {
          _lastKickAt = _nowSec;
          _kickEnv = 1;
          _flash = 1;
        }

        final ranges = _getLogRanges(freq.length, _sampleRate, barCount);
        final bassBars = math.min(8, math.max(5, (barCount * 0.2).floor()));
        for (var i = 0; i < barCount; i++) {
          final raw = _maxRange(freq, ranges[i][0], ranges[i][1]);
          if (i < bassBars) {
            final t = 1 - i / bassBars;
            final bounced = math.max(0.0, raw - _bassEma * 0.92) * 4.2;
            levels[i] = math.min(
              1.0,
              bounced * 0.85 + _kickEnv * (0.5 + t * 0.5) + raw * 0.08,
            );
          } else {
            final pump = _kickEnv *
                (0.28 *
                    (1 -
                        (i - bassBars) /
                            math.max(1, barCount - bassBars)));
            levels[i] =
                math.min(1.0, math.pow(raw, 0.78).toDouble() * 1.2 + pump);
          }
        }
        bass = math.min(1.0, punch * 2.2 + _kickEnv * 0.85 + bassPeak * 0.15);
        _highs = _avgRange(
          freq,
          (freq.length * 0.45).floor(),
          (freq.length * 0.85).floor(),
        );
      }
    }

    _kickEnv = math.max(0.0, _kickEnv - dt * 7.5);
    _flash = math.max(0.0, _flash - dt * 4.2);

    if (!hasSignal) {
      _breath += dt * (playing ? 1.6 : 0.4);
      final pulse = playing ? (math.sin(_breath) * 0.5 + 0.5) * 0.16 : 0.0;
      bass = _glow * 0.92 + pulse * 0.08;
      _highs = pulse * 0.5;

      if (playing) {
        for (var i = 0; i < barCount; i++) {
          final phase = _breath * (1.1 + i * 0.07) + i * 0.4;
          final wobble = math.sin(phase) * 0.5 + 0.5;
          final bassBoost = i < barCount * 0.2
              ? (math.sin(_breath * 2.4) * 0.5 + 0.5) * 0.55
              : 0.0;
          levels[i] = math.min(
            1.0,
            pulse * 0.35 + wobble * 0.22 + bassBoost,
          );
        }
        if (math.sin(_breath * 2.2) > 0.92 && _nowSec - _lastKickAt > 0.35) {
          _lastKickAt = _nowSec;
          _kickEnv = 0.85;
          _flash = 0.7;
        }
      }
    }

    for (var i = 0; i < barCount; i++) {
      final target = levels[i];
      final follow = target > _displayed[i]
          ? math.min(1.0, dt * 28)
          : math.min(1.0, dt * 9);
      _displayed[i] += (target - _displayed[i]) * follow;
      if (_displayed[i] < 0.004) _displayed[i] = 0;
      _peaks[i] = math.max(_displayed[i], _peaks[i] - dt * 1.15);
    }

    _glow += (bass - _glow) * math.min(1.0, dt * 12);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.48,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            _seedSparkles(size);
            return CustomPaint(
              size: size,
              painter: _LedLightsPainter(
                displayed: List<double>.from(_displayed),
                peaks: List<double>.from(_peaks),
                sparkles: List<_Sparkle>.from(_sparkles),
                glow: _glow,
                flash: _flash,
                kickEnv: _kickEnv,
                highs: _highs,
                nowSec: _nowSec,
                playing: widget.audioService.isPlaying,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Sparkle {
  const _Sparkle({
    required this.x,
    required this.y,
    required this.s,
    required this.band,
  });

  final double x;
  final double y;
  final double s;
  final double band;
}

class _LedLightsPainter extends CustomPainter {
  _LedLightsPainter({
    required this.displayed,
    required this.peaks,
    required this.sparkles,
    required this.glow,
    required this.flash,
    required this.kickEnv,
    required this.highs,
    required this.nowSec,
    required this.playing,
  });

  final List<double> displayed;
  final List<double> peaks;
  final List<_Sparkle> sparkles;
  final double glow;
  final double flash;
  final double kickEnv;
  final double highs;
  final double nowSec;
  final bool playing;

  /// Green → cyan-blue → purple LED palette.
  static Color _ledColor(double t, double flashAmt) {
    late final double r;
    late final double g;
    late final double b;
    if (t < 0.34) {
      final k = t / 0.34;
      r = 24 + k * 40;
      g = 220 + k * 20;
      b = 96 + k * 90;
    } else if (t < 0.66) {
      final k = (t - 0.34) / 0.32;
      r = 64 + k * 20;
      g = 240 + k * -90;
      b = 255;
    } else {
      final k = (t - 0.66) / 0.34;
      r = 110 + k * 110;
      g = 120 + k * -40;
      b = 255;
    }
    return Color.fromARGB(
      255,
      math.min(255, (r + flashAmt * 40).round()),
      math.min(255, (g + flashAmt * 12).round()),
      math.min(255, (b + flashAmt * 30).round()),
    );
  }

  void _fillRoundRect(Canvas canvas, Rect rect, double radius, Paint paint) {
    if (rect.width <= 0 || rect.height <= 0) return;
    final r = math.min(radius, math.min(rect.width, rect.height) / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      paint,
    );
  }

  void _drawColumn(
    Canvas canvas,
    double x,
    double bottom,
    double colW,
    double colH,
    int leds,
    double level,
    double peak,
    double flashAmt,
  ) {
    final gap = math.max(1.5, colW * 0.16);
    final ledH = (colH - gap * (leds - 1)) / leds;
    final litCount = (level * leds).round().clamp(0, leds);
    final peakIdx =
        ((peak * leds).round() - 1).clamp(0, math.max(0, leds - 1));
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < leds; i++) {
      final y = bottom - (i + 1) * ledH - i * gap;
      final t = leds == 1 ? 0.0 : i / (leds - 1);
      final rect = Rect.fromLTWH(x, y, colW, ledH);
      if (i < litCount) {
        final fade = 0.55 + 0.45 * (i + 1) / litCount;
        paint.color = _ledColor(t, flashAmt).withOpacity(fade.clamp(0.0, 1.0));
        _fillRoundRect(canvas, rect, math.min(2.2, ledH * 0.35), paint);
      } else {
        paint.color = const Color(0x4712183E);
        _fillRoundRect(canvas, rect, math.min(2.2, ledH * 0.35), paint);
      }
    }

    if (peak > 0.06) {
      final y = bottom - (peakIdx + 1) * ledH - peakIdx * gap;
      final base = _ledColor(peakIdx / math.max(1, leds - 1), 1);
      paint.color = Color.fromARGB(
        242,
        math.min(255, base.red + 18),
        math.min(255, base.green + 12),
        math.min(255, base.blue + 40),
      );
      _fillRoundRect(
        canvas,
        Rect.fromLTWH(x, y, colW, ledH),
        math.min(2.2, ledH * 0.35),
        paint,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w < 2 || h < 2) return;

    final barCount = displayed.length;
    if (barCount == 0) return;

    final anyMotion = playing ||
        glow > 0.012 ||
        flash > 0.012 ||
        peaks.any((p) => p > 0.02);
    if (!anyMotion) return;

    final isMobile = w < 768;
    final leds = isMobile ? 12 : 16;

    final floorTop = h * (isMobile ? 0.72 : 0.7);
    final floorPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, floorTop),
        Offset(0, h),
        [
          const Color(0x00000000),
          Color.fromRGBO(0, 6, 10, 0.16 + glow * 0.18),
        ],
      );
    canvas.drawRect(Rect.fromLTRB(0, floorTop, w, h), floorPaint);

    canvas.saveLayer(Offset.zero & size, Paint());

    final bloom = glow * 0.52 + flash * 0.22;
    if (bloom > 0.01) {
      final radius = math.max(w, h) * (0.22 + glow * 0.18 + flash * 0.08);
      final bloomPaint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset(w * 0.5, h * 0.48),
          radius,
          [
            Color.fromRGBO(80, 255, 180, bloom),
            Color.fromRGBO(90, 160, 255, bloom * 0.32),
            Color.fromRGBO(160, 80, 255, bloom * 0.12),
            const Color(0x00000000),
          ],
          const [0.0, 0.38, 0.7, 1.0],
        );
      canvas.drawRect(Offset.zero & size, bloomPaint);
    }

    if (flash > 0.05) {
      final kickPaint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset(w * 0.5, h * 0.82),
          w * 0.55,
          [
            Color.fromRGBO(180, 110, 255, flash * 0.22),
            const Color(0x00000000),
          ],
        );
      canvas.drawRect(Rect.fromLTRB(0, h * 0.5, w, h), kickPaint);
    }

    final specH = isMobile ? h * 0.22 : h * 0.24;
    final specBottom = h - (isMobile ? 18.0 : 26.0);
    final padX = isMobile ? 16.0 : 40.0;
    final innerW = w - padX * 2;
    final gapX = innerW / barCount;
    final colW = math.max(4.0, gapX * 0.58);
    final offset = padX + (gapX - colW) / 2;
    final mirrorPaint = Paint()..blendMode = BlendMode.plus;

    for (var i = 0; i < barCount; i++) {
      final x = offset + i * gapX;
      final level = displayed[i];
      final peak = i < peaks.length ? peaks[i] : 0.0;
      _drawColumn(
        canvas,
        x,
        specBottom,
        colW,
        specH,
        leds,
        level,
        peak,
        flash,
      );

      if (level > 0.04) {
        mirrorPaint.color =
            const Color(0xFF50FFB4).withOpacity(0.22 * level);
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            specBottom,
            colW,
            math.min(28.0, specH * 0.22) * level,
          ),
          mirrorPaint,
        );
      }
    }

    final sparklePaint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < sparkles.length; i++) {
      final p = sparkles[i];
      final tw =
          0.15 + 0.85 * math.sin(nowSec * (1.4 + p.band) + i).abs();
      final a = highs * tw * (0.25 + glow * 0.55 + kickEnv * 0.35);
      if (a < 0.02) continue;
      sparklePaint.color = i % 3 == 0
          ? Color.fromRGBO(196, 132, 252, math.min(0.7, a))
          : Color.fromRGBO(80, 255, 200, math.min(0.7, a));
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.s * (0.7 + flash * 0.6),
        sparklePaint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LedLightsPainter oldDelegate) => true;
}
