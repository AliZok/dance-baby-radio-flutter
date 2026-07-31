import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class WelcomeModal extends StatefulWidget {
  final bool isReady;
  final VoidCallback onLetsGo;

  const WelcomeModal({
    Key? key,
    required this.isReady,
    required this.onLetsGo,
  }) : super(key: key);

  @override
  _WelcomeModalState createState() => _WelcomeModalState();
}

class _WelcomeModalState extends State<WelcomeModal> with SingleTickerProviderStateMixin {
  late AnimationController _scanController;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  void _handlePress() {
    if (!widget.isReady || _isDismissed) return;
    setState(() {
      _isDismissed = true;
    });
    widget.onLetsGo();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withOpacity(0.92),
      child: Stack(
        children: [
          // Holographic button container
          Center(
            child: GestureDetector(
              onTap: _handlePress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 240,
                height: 230,
                decoration: BoxDecoration(
                  color: widget.isReady
                      ? const Color(0xFF00FFFF).withOpacity(0.1)
                      : const Color(0xFF00FFCC).withOpacity(0.05),
                  border: Border.all(
                    color: widget.isReady
                        ? const Color(0xFF00FFFF).withOpacity(0.5)
                        : const Color(0xFF00FFCC).withOpacity(0.3),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.zero,
                  boxShadow: [
                    BoxShadow(
                      color: widget.isReady
                          ? const Color(0xFF00FFFF).withOpacity(0.3)
                          : const Color(0xFF00FFCC).withOpacity(0.15),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRect(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Scan line animation
                      AnimatedBuilder(
                        animation: _scanController,
                        builder: (context, child) {
                          return Positioned(
                            top: _scanController.value * 230 - 2,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    widget.isReady
                                        ? const Color(0xFF00FFFF)
                                        : const Color(0xFF00FFCC),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      
                      // Content inside button
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.isReady) ...[
                              // Let's GO text
                              Text(
                                "Let's GO",
                                style: GoogleFonts.daysOne(
                                  fontSize: 24,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: const Color(0xFF00FFFF).withOpacity(0.8),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              // LOADING... text
                              Text(
                                "LOADING...",
                                style: GoogleFonts.daysOne(
                                  fontSize: 18,
                                  color: const Color(0xFF00FFCC),
                                  shadows: [
                                    Shadow(
                                      color: const Color(0xFF00FFCC).withOpacity(0.8),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Cyber spinner
                              const SpinKitRing(
                                color: Color(0xFF00FFCC),
                                size: 40,
                                lineWidth: 2,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
