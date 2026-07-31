import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/audio_service.dart';
import '../widgets/stars_background.dart';
import '../widgets/video_background.dart';
import '../widgets/genre_selector.dart';

class PlayerScreen extends StatefulWidget {
  final AudioService audioService;

  const PlayerScreen({
    Key? key,
    required this.audioService,
  }) : super(key: key);

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showControls = false; // In mobile front-end, controls are hidden by default
  bool _isGenreOpen = false; // Manages the open/close state of the genre selector

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _closeGenreMenu() {
    if (_isGenreOpen) {
      setState(() {
        _isGenreOpen = false;
      });
    }
  }

  // Custom SVG path for the exact Repeat icon from the Nuxt project
  Widget _buildRepeatIcon(bool isActive) {
    return SvgPicture.string(
      '''
      <svg xmlns="http://www.w3.org/2000/svg" width="25" height="25" fill="${isActive ? '#52DCFF' : '#ffffff'}" class="bi bi-arrow-repeat" viewBox="0 0 16 16">
          <path d="M11.534 7h3.932a.25.25 0 0 1 .192.41l-1.966 2.36a.25.25 0 0 1-.384 0l-1.966-2.36a.25.25 0 0 1 .192-.41zm-11 2h3.932a.25.25 0 0 0 .192-.41L2.692 6.23a.25.25 0 0 0-.384 0L.342 8.59A.25.25 0 0 0 .534 9z" />
          <path fill-rule="evenodd" d="M8 3c-1.552 0-2.94.707-3.857 1.818a.5.5 0 1 1-.771-.636A6.002 6.002 0 0 1 13.917 7H12.9A5.002 5.002 0 0 0 8 3zM3.1 9a5.002 5.002 0 0 0 8.757 2.182.5.5 0 1 1 .771.636A6.002 6.002 0 0 1 2.083 9H3.1z" />
      </svg>
      ''',
      width: 25,
      height: 25,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          _closeGenreMenu();
          setState(() {
            _showControls = false; // Tap anywhere else to hide controls
          });
        },
        behavior: HitTestBehavior.translucent,
        child: ListenableBuilder(
          listenable: widget.audioService,
          builder: (context, child) {
            final activeTrack = widget.audioService.activeTrack;
            final isPlaying = widget.audioService.isPlaying;
            final isLoading = widget.audioService.isLoading;
            final isRepeat = widget.audioService.isRepeat;
            final volume = widget.audioService.volume;
            final currentTime = widget.audioService.currentTime;
            final duration = widget.audioService.duration;

            // Check if video should be shown
            final shouldShowVideo = activeTrack != null &&
                (activeTrack.genre.contains('electronic') || activeTrack.genre.contains('relax'));

            return Stack(
              children: [
                // 1. Blurred Background Image
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(seconds: 1),
                    child: activeTrack?.cover.isNotEmpty == true
                        ? CachedNetworkImage(
                            key: ValueKey(activeTrack!.cover),
                            imageUrl: activeTrack.cover,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Image.asset(
                              'assets/images/background-dance-1.jpg',
                              fit: BoxFit.cover,
                            ),
                            errorWidget: (context, url, error) => Image.asset(
                              'assets/images/background-dance-1.jpg',
                              fit: BoxFit.cover,
                            ),
                          )
                        : Image.asset(
                            'assets/images/background-dance-1.jpg',
                            key: const ValueKey('default_bg'),
                            fit: BoxFit.cover,
                          ),
                  ),
                ),

                // 2. Stars Background
                const StarsBackground(),

                // 3. Video Background
                VideoBackground(shouldShow: shouldShowVideo),

                // 4. Header (Top Left)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "DANCE BABY RADIO",
                        style: GoogleFonts.daysOne(
                          fontSize: 22,
                          color: const Color(0xFF94D4E3),
                          shadows: [
                            Shadow(
                              color: const Color(0xFFCCFBF7).withOpacity(0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (isPlaying)
                        Container(
                          width: 44,
                          height: 25,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.asset(
                              'assets/images/radio-playing-2.webp',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // 5. Main Player Box (Center)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Animated Controls (Repeat on Right, Volume on Left)
                        // They slide out from behind the Player Card
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          top: _showControls ? -45 : 10, // Slides up/down
                          left: 0,
                          right: 0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: _showControls ? 1.0 : 0.0,
                            child: SizedBox(
                              width: 300,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Volume Slider (Left side, NO speaker icon)
                                  Container(
                                    width: 110,
                                    height: 30,
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10191A).withOpacity(0.593),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    alignment: Alignment.center,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        activeTrackColor: const Color(0xFF58D1EF),
                                        inactiveTrackColor: Colors.white24,
                                        thumbColor: const Color(0xFF4E4E4E),
                                        trackHeight: 5.0,
                                        thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 7.0,
                                        ),
                                        overlayShape: SliderComponentShape.noOverlay,
                                      ),
                                      child: Slider(
                                        value: volume,
                                        min: 0.0,
                                        max: 1.0,
                                        onChanged: widget.audioService.setVolume,
                                      ),
                                    ),
                                  ),

                                  // Repeat Button (Right side, custom SVG icon)
                                  GestureDetector(
                                    onTap: widget.audioService.toggleRepeat,
                                    child: Container(
                                      width: 40,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10191A).withOpacity(0.593),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      alignment: Alignment.center,
                                      child: _buildRepeatIcon(isRepeat),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Player Card
                        GestureDetector(
                          onTap: () {
                            _closeGenreMenu();
                            setState(() {
                              _showControls = !_showControls; // Toggles sliding animation
                            });
                          },
                          child: Container(
                            width: 300,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C0C0C).withOpacity(0.64),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF003E47),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF111A1E).withOpacity(0.8),
                                  blurRadius: 30,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Cover Image / Play Button
                                GestureDetector(
                                  onTap: widget.audioService.playMusic,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Cover Image
                                      Container(
                                        width: 240,
                                        height: 240,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: isPlaying
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFF84F3FF).withOpacity(0.16),
                                                    blurRadius: 12,
                                                    spreadRadius: 4,
                                                  ),
                                                ]
                                              : [],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(20),
                                          child: activeTrack?.cover.isNotEmpty == true
                                              ? CachedNetworkImage(
                                                  imageUrl: activeTrack.cover,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) => Image.asset(
                                                    'assets/images/background-dance-1.jpg',
                                                    fit: BoxFit.cover,
                                                  ),
                                                  errorWidget: (context, url, error) => Image.asset(
                                                    'assets/images/background-dance-1.jpg',
                                                    fit: BoxFit.cover,
                                                  ),
                                                )
                                              : Image.asset(
                                                  'assets/images/background-dance-1.jpg',
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                      ),

                                      // Ripple Loading Spinner
                                      if (isLoading)
                                        const SpinKitRipple(
                                          color: Color(0xFF64EEFF),
                                          size: 150,
                                        ),

                                      // Play Button Overlay (when paused and not loading)
                                      if (!isPlaying && !isLoading)
                                        Container(
                                          width: 200,
                                          height: 200,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10191A).withOpacity(0.59),
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Container(
                                            width: 0,
                                            height: 0,
                                            margin: const EdgeInsets.only(left: 10),
                                            decoration: const BoxDecoration(
                                              border: Border(
                                                top: BorderSide(color: Colors.transparent, width: 19),
                                                bottom: BorderSide(color: Colors.transparent, width: 19),
                                                left: BorderSide(color: Color(0xFF52DCFF), width: 28),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Seek Slider
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: const Color(0xFF58D1EF),
                                    inactiveTrackColor: Colors.white24,
                                    thumbColor: const Color(0xFF4E4E4E),
                                    trackHeight: 4.0,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8.0,
                                    ),
                                  ),
                                  child: Slider(
                                    value: currentTime.inSeconds.toDouble().clamp(
                                          0.0,
                                          duration.inSeconds.toDouble(),
                                        ),
                                    min: 0.0,
                                    max: duration.inSeconds > 0
                                        ? duration.inSeconds.toDouble()
                                        : 1.0,
                                    onChanged: (val) {
                                      widget.audioService.seek(Duration(seconds: val.toInt()));
                                    },
                                  ),
                                ),

                                // Track Metadata & Time
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Title & Artist
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              activeTrack?.title ?? "Dance Baby Radio",
                                              style: const TextStyle(
                                                color: Color(0xFF23C1D2),
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              activeTrack?.artist ?? "",
                                              style: TextStyle(
                                                color: const Color(0xFF23C1D2).withOpacity(0.7),
                                                fontSize: 10,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Playback Time
                                      Text(
                                        "${_formatDuration(currentTime)} / ${_formatDuration(duration)}",
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 6. Genre Button (Bottom Left)
                Positioned(
                  bottom: 27 + MediaQuery.of(context).padding.bottom,
                  left: 20,
                  child: GenreSelector(
                    audioService: widget.audioService,
                    isOpen: _isGenreOpen,
                    onToggle: () {
                      setState(() {
                        _isGenreOpen = !_isGenreOpen;
                      });
                    },
                  ),
                ),

                // 7. Next Button (Bottom Right)
                Positioned(
                  bottom: 27 + MediaQuery.of(context).padding.bottom,
                  right: 20,
                  child: GestureDetector(
                    onTap: () {
                      _closeGenreMenu();
                      widget.audioService.playNextMusic();
                    },
                    child: Container(
                      width: 83,
                      height: 81,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10191A).withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 0,
                            height: 0,
                            margin: const EdgeInsets.only(left: 3),
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Colors.transparent, width: 8),
                                bottom: BorderSide(color: Colors.transparent, width: 8),
                                left: BorderSide(color: Color(0xFF52DCFF), width: 12),
                              ),
                            ),
                          ),
                          Container(
                            width: 0,
                            height: 0,
                            margin: const EdgeInsets.only(left: 3),
                            decoration: const BoxDecoration(
                              border: Border(
                                top: BorderSide(color: Colors.transparent, width: 8),
                                bottom: BorderSide(color: Colors.transparent, width: 8),
                                left: BorderSide(color: Color(0xFF52DCFF), width: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
