import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Native twin of the Nuxt `WelcomeModal` in its *not-ready* state:
/// a pure-black full-screen cover with the perspective grid, the pulsing
/// glow field, the two scanning laser lines and the glitching neon
/// "DANCE BABY RADIO is LOADING..." title.
///
/// It is mounted above everything (header, player, chrome) so the user can
/// never catch a glimpse of a half-buffered player — the first thing they see
/// is the radio already on air. Browsers need the "Let's GO" tap to unlock
/// audio; Android does not, so this gate releases by itself the moment the
/// first track is actually audible.
class WelcomeGate extends StatefulWidget {
  const WelcomeGate({Key? key}) : super(key: key);

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate>
    with TickerProviderStateMixin {
  static const _neon = Color(0xFF00FFCC);
  static const _neonAlt = Color(0xFF00FFFF);

  late final AnimationController _grid;
  late final AnimationController _glow;
  late final AnimationController _scanFast;
  late final AnimationController _scanSlow;
  late final AnimationController _pulse;
  late final AnimationController _glitch;

  @override
  void initState() {
    super.initState();
    // CSS: gridDrift 12s linear infinite
    _grid = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
    // CSS: glowPulse 3.5s ease-in-out infinite
    _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 3500))
      ..repeat();
    // CSS: scan 1.6s / 2.4s linear infinite (second one offset by -0.8s)
    _scanFast = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _scanSlow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();
    // CSS: textPulse 1.5s infinite ease-in-out
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat();
    // CSS: glitch 2s infinite (+ reversed twin)
    _glitch = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _grid.dispose();
    _glow.dispose();
    _scanFast.dispose();
    _scanSlow.dispose();
    _pulse.dispose();
    _glitch.dispose();
    super.dispose();
  }

  /// `top: -5% → 105%` of the viewport, as a translateY offset.
  Widget _scanLine({
    required Animation<double> animation,
    required double height,
    required double opacity,
    required double blur,
    required double screenHeight,
    double phase = 0,
  }) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          // -0.05 → 1.05 of the screen height, looping (CSS `animation-delay`)
          final loop = (animation.value + phase) % 1.0;
          final progress = -0.05 + loop * 1.10;
          return Transform.translate(
            offset: Offset(0, progress * screenHeight),
            child: child,
          );
        },
        child: Opacity(
          opacity: opacity,
          child: ImageFiltered(
            // CSS `filter: blur(...)` on the scan line
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0x0000FFCC),
                    Color(0x2600FFCC),
                    Color(0xE600FFCC),
                    Color(0x2600FFCC),
                    Color(0x0000FFCC),
                  ],
                  stops: [0.0, 0.3, 0.5, 0.7, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _neon.withOpacity(0.3),
                    blurRadius: 22,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glitchTitle() {
    final baseStyle = GoogleFonts.daysOne();
    return AnimatedBuilder(
      animation: Listenable.merge([_glitch, _pulse]),
      builder: (context, child) {
        final t = _glitch.value;
        // CSS: textPulse 0%,100% opacity .6 → 50% opacity 1
        final loadingPulse =
            0.6 + 0.4 * (0.5 - 0.5 * math.cos(_pulse.value * math.pi * 2));
        final upper = _glitchShift(t);
        final lower = _glitchShift((t + 0.5) % 1.0);

        Widget ghost(Color color, double dx, double dy) {
          return Transform.translate(
            offset: Offset(dx, dy),
            child: _TitleText(
              baseStyle: baseStyle,
              color: color,
              opacity:
                  (0.3 + 0.2 * math.sin(t * math.pi * 2)).clamp(0.0, 1.0).toDouble(),
              blur: 6,
              loadingOpacity: loadingPulse,
            ),
          );
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            ghost(_neon, upper, -2),
            ghost(_neonAlt, -lower, 2),
            _TitleText(
              baseStyle: baseStyle,
              color: _neon,
              opacity: 1,
              blur: 0,
              loadingOpacity: loadingPulse,
            ),
          ],
        );
      },
    );
  }

  /// CSS `@keyframes glitch` translateX sample: 0 → -5 → 5 → -3 → 3 → 0.
  double _glitchShift(double t) {
    const stops = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
    const values = [0.0, -5.0, 5.0, -3.0, 3.0, 0.0];
    for (var i = 0; i < stops.length - 1; i++) {
      if (t <= stops[i + 1]) {
        final local = (t - stops[i]) / (stops[i + 1] - stops[i]);
        return values[i] + (values[i + 1] - values[i]) * local;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenH = size.height;

    return Material(
      color: Colors.black,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // .field-grid — perspective grid drifting toward the viewer
            Opacity(
              opacity: 0.55,
              child: CustomPaint(
                painter: _IntroGridPainter(_grid),
                size: Size.infinite,
              ),
            ),

            // .field-glow — pulsing neon field behind the title
            AnimatedBuilder(
              animation: _glow,
              builder: (context, child) {
                final pulse = 0.7 + 0.3 * math.sin(_glow.value * math.pi * 2);
                return Opacity(
                  opacity: pulse.clamp(0.0, 1.0).toDouble(),
                  child: child,
                );
              },
              child: const _IntroGlowField(),
            ),

            // .scan-line (fast) + delayed thinner twin
            _scanLine(
              animation: _scanFast,
              height: 2,
              opacity: 1,
              blur: 0.6,
              screenHeight: screenH,
            ),
            _scanLine(
              animation: _scanSlow,
              height: 1,
              opacity: 0.35,
              blur: 1.2,
              screenHeight: screenH,
              // CSS `animation-delay: -0.8s` on a 2.4s loop
              phase: 1 / 3,
            ),

            // hologram title
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _glitchTitle(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brand / "is" / "LOADING..." stack, matching the web loading text.
class _TitleText extends StatelessWidget {
  final TextStyle baseStyle;
  final Color color;
  final double opacity;
  final double blur;
  final double loadingOpacity;

  const _TitleText({
    required this.baseStyle,
    required this.color,
    required this.opacity,
    required this.blur,
    required this.loadingOpacity,
  });

  @override
  Widget build(BuildContext context) {
    TextStyle style(
      double size,
      FontWeight weight,
      Color c, {
      bool italic = false,
      double letterSpacing = 2,
      double glow = 12,
      double alpha = 1,
    }) {
      return baseStyle.copyWith(
        fontSize: size,
        fontWeight: weight,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        letterSpacing: letterSpacing,
        color: c.withOpacity(opacity * alpha),
        shadows: [
          Shadow(
            color: color.withOpacity(0.85 * opacity * alpha),
            offset: const Offset(0, 0),
            blurRadius: blur > 0 ? blur : glow,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'DANCE BABY RADIO',
          textAlign: TextAlign.center,
          style: style(26, FontWeight.w700, const Color(0xFF00FFCC),
              letterSpacing: 3, glow: 14),
        ),
        const SizedBox(height: 14),
        Text(
          'is',
          textAlign: TextAlign.center,
          style: style(
            16,
            FontWeight.w400,
            const Color(0xB3FFFFFF),
            italic: true,
            glow: 6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'LOADING...',
          textAlign: TextAlign.center,
          style: style(18, FontWeight.w600, const Color(0xFF00FFCC),
              alpha: loadingOpacity),
        ),
      ],
    );
  }
}

/// The two radial gradients from `.field-glow`.
class _IntroGlowField extends StatelessWidget {
  const _IntroGlowField();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        // radial ellipse at 50% / 42% — cyan field around the title
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.16),
              radius: 0.85,
              colors: [Color(0x1F00FFCC), Color(0x0000FFCC)],
            ),
          ),
        ),
        // radial ellipse rising from the bottom edge — cool blue haze
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 1),
              radius: 0.9,
              colors: [Color(0x1400B4DC), Color(0x0000B4DC)],
            ),
          ),
        ),
      ],
    );
  }
}

/// Perspective grid: horizontal lines rush toward the viewer while the
/// verticals converge on a vanishing point, like `rotateX(58deg)` in CSS.
class _IntroGridPainter extends CustomPainter {
  final Animation<double> animation;

  _IntroGridPainter(this.animation) : super(repaint: animation);

  static const Color _cyan = Color(0xFF00FFCC);
  static const Color _teal = Color(0xFF00FFFF);

  /// CSS mask: transparent 0% → black 28% → black 78% → transparent 100%.
  double _mask(double y, double h) {
    final p = y / h;
    if (p <= 0 || p >= 1) return 0;
    if (p < 0.28) return p / 0.28;
    if (p > 0.78) return (1 - p) / 0.22;
    return 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final horizon = h * 0.18;
    final depth = h - horizon;

    canvas.clipRect(Offset.zero & size);

    // Horizontal rows: eased spacing (perspective) animated by the drift phase.
    const rows = 16;
    final phase = animation.value;
    for (var i = 0; i < rows; i++) {
      final p = (i + phase) / rows;
      if (p <= 0 || p > 1) continue;
      final y = (horizon + depth * math.pow(p, 2.4)).toDouble();
      final alpha = 0.14 * p * _mask(y, h);
      if (alpha <= 0.002) continue;
      paint.color = _cyan.withOpacity(alpha.toDouble());
      canvas.drawLine(Offset(0, y.toDouble()), Offset(w, y.toDouble()), paint);
    }

    // Verticals converging to the vanishing point at the horizon.
    const cols = 9;
    for (var i = -cols; i <= cols; i++) {
      final startX = w / 2 + i * 8.0;
      final endX = w / 2 + i * (w * 0.16);
      final startY = horizon + depth * 0.02;
      final alpha = (0.10 * _mask(startY + 8, h)).toDouble();
      if (alpha <= 0.002) continue;
      paint.color = _teal.withOpacity(alpha);
      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, h * 0.98),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IntroGridPainter oldDelegate) => false;
}
