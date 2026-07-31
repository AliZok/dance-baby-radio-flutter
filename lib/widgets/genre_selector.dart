import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/audio_service.dart';

class GenreSelector extends StatefulWidget {
  final AudioService audioService;

  const GenreSelector({
    Key? key,
    required this.audioService,
  }) : super(key: key);

  @override
  _GenreSelectorState createState() => _GenreSelectorState();
}

class _GenreSelectorState extends State<GenreSelector> {
  bool _isOpen = false;

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
              onTap: () {
                setState(() {
                  _isOpen = !_isOpen;
                });
              },
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF10191A).withOpacity(0.6),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF003E47),
                    width: 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  "GENRE",
                  style: GoogleFonts.daysOne(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
            ),

            // Floating Genre List
            if (_isOpen)
              Positioned(
                bottom: 90,
                left: 0,
                child: Container(
                  width: 200,
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10191A).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF003E47),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
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
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  genreEl.text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(
                                      genreEl.active ? 1.0 : 0.5,
                                    ),
                                    fontWeight: genreEl.active
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (genreEl.active)
                                const Icon(
                                  Icons.check,
                                  color: Color(0xFF00FFFF),
                                  size: 16,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
