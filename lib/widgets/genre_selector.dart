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
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.audioService,
      builder: (context, child) {
        final genres = widget.audioService.genres;

        return Stack(
          alignment: Alignment.bottomLeft,
          clipBehavior: Clip.none,
          children: [
            // Genre Button
            GestureDetector(
              onTap: widget.onToggle,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF10191A).withOpacity(0.593),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  "GENRE",
                  style: GoogleFonts.daysOne(
                    fontSize: 10,
                    color: Colors.white.withOpacity(widget.isOpen ? 1.0 : 0.6),
                  ),
                ),
              ),
            ),

            // Floating Genre List (Select Box)
            if (widget.isOpen)
              Positioned(
                bottom: 90,
                left: 0,
                child: GestureDetector(
                  onTap: () {}, // Prevents closing when tapping inside the list
                  child: Container(
                    width: 200,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10191A).withOpacity(0.593),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: genres.map((genreEl) {
                        return GestureDetector(
                          onTap: () {
                            widget.audioService.toggleGenre(genreEl);
                          },
                          child: Container(
                            color: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 10.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    genreEl.text,
                                    style: TextStyle(
                                      fontFamily: 'farsiFont', // Fallback to system if not loaded
                                      fontSize: 13,
                                      color: Colors.white.withOpacity(
                                        genreEl.active ? 1.0 : 0.5,
                                      ),
                                      fontWeight: genreEl.active
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      // Glowing/bright light effect for active items
                                      shadows: genreEl.active
                                          ? [
                                              Shadow(
                                                color: Colors.white.withOpacity(0.8),
                                                blurRadius: 8,
                                              ),
                                            ]
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
