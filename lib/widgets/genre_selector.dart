import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/audio_service.dart';

class GenreSelector extends StatefulWidget {
  final AudioService audioService;
  final bool isOpen;
  final VoidCallback onToggle;

  const GenreSelector({
    Key? key,
    required this.audioService,
    required this.isOpen,
    required this.onToggle,
  }) : super(key: key);

  @override
  _GenreSelectorState createState() => _GenreSelectorState();
}

class _GenreSelectorState extends State<GenreSelector> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    if (widget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
    }
  }

  @override
  void didUpdateWidget(covariant GenreSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen == oldWidget.isOpen) return;
    if (widget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
    } else {
      _hideOverlay();
    }
  }

  void _showOverlay() {
    if (!mounted || _overlayEntry != null || !widget.isOpen) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: Stack(
          children: [
            // Mobile frontend closes the menu when the rest of the page is
            // tapped. The popup itself sits above this barrier and keeps taps.
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onToggle,
              child: const SizedBox.expand(),
            ),
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              // Mirrors the frontend's zero-height anchor and
              // `.genre-list { left: 5px; bottom: 25px; }`.
              offset: const Offset(62, 15),
              child: Material(
                type: MaterialType.transparency,
                child: _GenreMenu(audioService: widget.audioService),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF10191A).withOpacity(0.78),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            'GENRE',
            style: GoogleFonts.daysOne(
              fontSize: 10,
              color: const Color(0xFF84F3FF).withOpacity(
                widget.isOpen ? 1 : 0.6,
              ),
              shadows: widget.isOpen
                  ? [
                      Shadow(
                        color: const Color(0xFF84F3FF).withOpacity(0.75),
                        blurRadius: 9,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _GenreMenu extends StatelessWidget {
  final AudioService audioService;

  const _GenreMenu({required this.audioService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: audioService,
      builder: (context, child) {
        return Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF10191A).withOpacity(0.593),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: audioService.genres.map((genre) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => audioService.toggleGenre(genre),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      genre.text,
                      style: TextStyle(
                        fontSize: 13,
                        color: genre.active
                            ? const Color(0xFF84F3FF)
                            : const Color(0xFF84F3FF).withOpacity(0.5),
                        shadows: genre.active
                            ? [
                                Shadow(
                                  color:
                                      const Color(0xFF84F3FF).withOpacity(0.55),
                                  blurRadius: 7,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
