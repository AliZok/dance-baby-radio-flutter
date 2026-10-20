import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Matches the Nuxt WelcomeModal: the cyber grid + scanlines sit behind a
/// "LOADING..." badge until a track can start instantly, then the hologram
/// "Let's GO" button appears and the gate is only released by a tap on it
/// (that tap is the app's first play() call, exactly like the web).
class WelcomeOverlay extends StatefulWidget {
  final bool isReady;
  final VoidCallback onLetsGo;

  const WelcomeOverlay({
    super.key,
    required this.isReady,
    required this.onLetsGo,
  });

  @override
  State<WelcomeOverlay> createState() => _WelcomeOverlayState();
}

class _WelcomeOverlayState extends State<WelcomeOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _gridController;
  late final AnimationController _scanController;
  late final AnimationController _glowController;
  late final AnimationController _spinController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _gridController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat(reverse: true);
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _gridController.dispose();
    _scanController.dispose();
    _glowController.dispose();
    _spinController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.isReady) return;
    widget.onLetsGo();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Frontend: `.WelcomeModal { background: rgba(0,0,0,.922) }` once ready,
    // pure `#000` while loading; tapping anywhere releases the gate.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: ColoredBox(
        color: widget.isReady
            ? const Color(0xEB000000)
            : const Color(0xFF000000),
        child: Stack(
          fit: StackFit.expand,
          children: [
          AnimatedBuilder(
            animation: _gridController,
            builder: (context, _) {
              return CustomPaint(
                painter: _CyberGridPainter(progress: _gridController.value),
                size: Size.infinite,
              );
            },
          ),
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, _) {
              final t = 0.7 + (_glowController.value * 0.3);
              return Opacity(
                opacity: t,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.16),
                      radius: 0.85,
                      colors: [
                        Color(0x1F00FFCC),
                        Color(0x00000000),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 1.1),
                radius: 0.9,
                colors: [
                  Color(0x1400B4DC),
                  Color(0x00000000),
                ],
              ),
            ),
          ),
          _ScanLine(controller: _scanController, delay: 0, opacity: 1),
          _ScanLine(controller: _scanController, delay: 0.33, opacity: 0.35),
          Center(
            child: widget.isReady
                ? _LetsGoBadge(pulse: _pulseController)
                : _LoadingBadge(
                    spin: _spinController,
                    pulse: _pulseController,
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 18,
            child: Text(
              'dance baby radio',
              textAlign: TextAlign.center,
              style: GoogleFonts.daysOne(
                fontSize: 13,
                letterSpacing: 3.2,
                color: const Color(0x8A00FFCC),
                shadows: const [
                  Shadow(
                    color: Color(0x6600FFCC),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

/// The hologram "Let's GO" button (Nuxt `button.hologram` — 240×230, 2px cyan
/// border, blurred cyan glow). Hover/press grows the label, matching the CSS.
class _LetsGoBadge extends StatefulWidget {
  final Animation<double> pulse;

  const _LetsGoBadge({required this.pulse});

  @override
  State<_LetsGoBadge> createState() => _LetsGoBadgeState();
}

class _LetsGoBadgeState extends State<_LetsGoBadge> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.pulse,
      builder: (context, child) {
        final t = widget.pulse.value;
        return Container(
          width: 240,
          height: 230,
          decoration: BoxDecoration(
            color: const Color(0x1A00FFFF),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x8000FFFF), width: 2),
            boxShadow: [
              BoxShadow(
                color: (_pressed
                        ? const Color(0x7AC7387E)
                        : const Color(0x4D00FFFF))
                    .withOpacity(0.6 + 0.4 * t),
                blurRadius: _pressed ? 26 : 15,
                spreadRadius: _pressed ? 6 : 0,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: child,
        );
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: Text(
          "Let's GO",
          style: GoogleFonts.orbitron(
            fontSize: _pressed ? 26 : 19,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: Colors.white,
            shadows: const [
              Shadow(color: Color(0xCC00FFCC), blurRadius: 10),
              Shadow(color: Color(0x8000FFFF), blurRadius: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingBadge extends StatelessWidget {
  final Animation<double> spin;
  final Animation<double> pulse;

  const _LoadingBadge({required this.spin, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: pulse,
          builder: (context, _) {
            final opacity = 0.6 + (pulse.value * 0.4);
            return Opacity(
              opacity: opacity,
              child: Text(
                'LOADING...',
                style: GoogleFonts.orbitron(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: const Color(0xFF00FFCC),
                  shadows: [
                    Shadow(
                      color: const Color(0xFF00FFCC).withOpacity(0.85),
                      blurRadius: 10 + (pulse.value * 8),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: spin,
          builder: (context, _) {
            return Transform.rotate(
              angle: spin.value * math.pi * 2,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.transparent, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x8000FFCC),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: CustomPaint(painter: _CyberSpinnerPainter()),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ScanLine extends StatelessWidget {
  final Animation<double> controller;
  final double delay;
  final double opacity;

  const _ScanLine({
    required this.controller,
    required this.delay,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = (controller.value + delay) % 1.0;
        return Align(
          alignment: Alignment(0, -1.1 + (t * 2.2)),
          child: Opacity(
            opacity: opacity,
            child: Container(
              height: opacity < 1 ? 1 : 2,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0x0000FFCC),
                    Color(0x2600FFCC),
                    Color(0xE600FFCC),
                    Color(0x2600FFCC),
                    Color(0x0000FFCC),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x4D00FFCC).withOpacity(opacity),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CyberSpinnerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..shader = const SweepGradient(
        colors: [
          Color(0x00000000),
          Color(0xFF00FFCC),
          Color(0x00000000),
          Color(0xFF00FFFF),
        ],
        stops: [0.0, 0.35, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawCircle(size.center(Offset.zero), size.width / 2 - 1, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CyberGridPainter extends CustomPainter {
  final double progress;

  _CyberGridPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final horizon = size.height * 0.28;
    canvas.translate(size.width / 2, horizon);
    canvas.transform((Matrix4.identity()
          ..setEntry(3, 2, 0.0016)
          ..rotateX(1.01))
        .storage);

    final offset = progress * 48;
    final paintH = Paint()
      ..color = const Color(0x1200FFCC)
      ..strokeWidth = 1;
    final paintV = Paint()
      ..color = const Color(0x0D00FFFF)
      ..strokeWidth = 1;

    const cell = 48.0;
    final halfW = size.width * 1.4;
    final depth = size.height * 1.6;

    for (double y = -offset; y < depth; y += cell) {
      canvas.drawLine(Offset(-halfW, y), Offset(halfW, y), paintH);
    }
    for (double x = -halfW; x <= halfW; x += cell) {
      canvas.drawLine(Offset(x, -20), Offset(x, depth), paintV);
    }
    canvas.restore();

    final fade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFF000000),
          Color(0x00000000),
          Color(0x00000000),
          Color(0xFF000000),
        ],
        stops: const [0.0, 0.28, 0.78, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, fade);
  }

  @override
  bool shouldRepaint(covariant _CyberGridPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
