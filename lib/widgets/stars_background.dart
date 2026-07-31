import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StarsBackground extends StatefulWidget {
  const StarsBackground({Key? key}) : super(key: key);

  @override
  _StarsBackgroundState createState() => _StarsBackgroundState();
}

class _StarsBackgroundState extends State<StarsBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  ui.Image? _starsImage;
  ui.Image? _twinklingImage;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 200), // Matches 200s animation in CSS
    )..repeat();

    _loadAssets();
  }

  Future<void> _loadAssets() async {
    try {
      final stars = await _loadUiImage('assets/images/stars.png');
      final twinkling = await _loadUiImage('assets/images/twinkling.png');
      if (mounted) {
        setState(() {
          _starsImage = stars;
          _twinklingImage = twinkling;
          _isLoaded = true;
        });
      }
    } catch (e) {
      print('Error loading stars background assets: $e');
    }
  }

  Future<ui.Image> _loadUiImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _starsImage == null || _twinklingImage == null) {
      return Container(color: Colors.black);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // In CSS: from { background-position: 0 0; } to { background-position: -10000px 5000px; }
        // We translate the twinkling layer based on the animation value
        final double translationX = -10000.0 * _controller.value;
        final double translationY = 5000.0 * _controller.value;

        return CustomPaint(
          painter: StarfieldPainter(
            starsImage: _starsImage!,
            twinklingImage: _twinklingImage!,
            offsetX: translationX,
            offsetY: translationY,
          ),
          child: Container(),
        );
      },
    );
  }
}

class StarfieldPainter extends CustomPainter {
  final ui.Image starsImage;
  final ui.Image twinklingImage;
  final double offsetX;
  final double offsetY;

  StarfieldPainter({
    required this.starsImage,
    required this.twinklingImage,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw static stars background
    final starsPaint = Paint()
      ..shader = ImageShader(
        starsImage,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList(Matrix4.identity().storage),
      );
    canvas.drawRect(Offset.zero & size, starsPaint);

    // 2. Draw moving twinkling background
    final matrix = Matrix4.translationValues(offsetX, offsetY, 0.0);
    final twinklingPaint = Paint()
      ..shader = ImageShader(
        twinklingImage,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList(matrix.storage),
      );
    canvas.drawRect(Offset.zero & size, twinklingPaint);
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) {
    return oldDelegate.offsetX != offsetX || oldDelegate.offsetY != offsetY;
  }
}
