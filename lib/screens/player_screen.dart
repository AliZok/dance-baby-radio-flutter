import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/audio_service.dart';
import '../widgets/stars_background.dart';
import '../widgets/video_background.dart';
import '../widgets/genre_selector.dart';

/// Draws a solid right-pointing triangle (▶), matching the Nuxt frontend's
/// `.button-icon` CSS-border triangle trick, but as real vector geometry so
/// it always renders crisp, correctly centered and pointing right on every
/// device (the CSS border-hack can render inconsistently in Flutter).
class _RightTriangle extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _RightTriangle({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _RightTrianglePainter(color),
    );
  }
}

class _RightTrianglePainter extends CustomPainter {
  final Color color;
  _RightTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RightTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

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
      <svg xmlns="http://www.w3.org/2000/svg" width="25" height="25" fill="${isActive ? '#52DCFF' : '#66FFFFFF'}" class="bi bi-arrow-repeat" viewBox="0 0 16 16">
          <path d="M11.534 7h3.932a.25.25 0 0 1 .192.41l-1.966 2.36a.25.25 0 0 1-.384 0l-1.966-2.36a.25.25 0 0 1 .192-.41zm-11 2h3.932a.25.25 0 0 0 .192-.41L2.692 6.23a.25.25 0 0 0-.384 0L.342 8.59A.25.25 0 0 0 .534 9z" />
          <path fill-rule="evenodd" d="M8 3c-1.552 0-2.94.707-3.857 1.818a.5.5 0 1 1-.771-.636A6.002 6.002 0 0 1 13.917 7H12.9A5.002 5.002 0 0 0 8 3zM3.1 9a5.002 5.002 0 0 0 8.757 2.182.5.5 0 1 1 .771.636A6.002 6.002 0 0 1 2.083 9H3.1z" />
      </svg>
      ''',
      width: 25,
      height: 25,
    );
  }

  Widget _buildDefaultCoverBrand() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/background-dance-1.jpg',
          fit: BoxFit.cover,
        ),
        Align(
          // Frontend: `.back-logo { top: 71%; transform: translateY(-50%) }`.
          alignment: const Alignment(0, 0.42),
          child: IgnorePointer(
            child: SizedBox(
              width: 220,
              child: Text(
                'DANCE BABY RADIO',
                textAlign: TextAlign.center,
                style: GoogleFonts.daysOne(
                  fontSize: 20,
                  color: const Color(0xFFD8F6FF),
                  shadows: const [
                    Shadow(
                      color: Color(0xFF2B3D3C),
                      offset: Offset(5, 10),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
          listenable: widget.audioService,
          builder: (context, child) {
            final activeTrack = widget.audioService.activeTrack;
            final isPlaying = widget.audioService.isPlaying;
            final isLoading = widget.audioService.isLoading;
            final isRepeat = widget.audioService.isRepeat;
            final volume = widget.audioService.volume;
            final currentTime = widget.audioService.currentTime;
            final duration = widget.audioService.duration;
            final isAudioReady = widget.audioService.isAudioReady;

            // Check if video should be shown
            final shouldShowVideo = activeTrack != null &&
                (activeTrack.genre.contains('electronic') || activeTrack.genre.contains('relax'));

            // Show loading splash screen if tracks are not loaded yet
            if (!isAudioReady && activeTrack == null) {
              return Container(
                color: Colors.black,
                width: double.infinity,
                height: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Stars Background
                    const StarsBackground(),
                    
                    // Centered Logo and Loading Spinner
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "DANCE BABY RADIO",
                          style: GoogleFonts.daysOne(
                            fontSize: 28,
                            color: const Color(0xFF94D4E3),
                            shadows: [
                              Shadow(
                                color: const Color(0xFFCCFBF7).withOpacity(0.8),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        const SpinKitRing(
                          color: Color(0xFF64EEFF),
                          size: 50,
                          lineWidth: 2,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return Stack(
              children: [
                // Video sits behind and blends through the dimmed cover for
                // electronic/relax, matching the mobile frontend layering.
                Positioned.fill(
                  child: VideoBackground(shouldShow: shouldShowVideo),
                ),

                // Full-screen, center-cropped cover. The dark translucent layer
                // keeps it atmospheric while allowing the video to show through.
                Positioned.fill(
                  child: Opacity(
                    opacity: shouldShowVideo ? 0.46 : 0.58,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Color(0x66000000),
                        BlendMode.srcATop,
                      ),
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
                  ),
                ),

                const Positioned.fill(
                  child: Opacity(
                    opacity: 0.5,
                    child: StarsBackground(),
                  ),
                ),

                // Captures only empty-page taps; interactive controls are
                // painted later in this Stack and therefore win hit testing.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _closeGenreMenu();
                      setState(() => _showControls = false);
                    },
                  ),
                ),

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
                          fontSize: 18,
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
                  child: Transform.translate(
                    offset: const Offset(0, -27.5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // Animated Controls (Repeat on Right, Volume on Left)
                        // They slide out from behind the Player Card
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          // Both positions are inside the Stack's hit-test
                          // bounds. Previously these controls were painted at
                          // top:-45, visible but impossible to tap.
                          top: _showControls ? 5 : 60,
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
                                    height: 40,
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
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      width: 40,
                                      height: 40,
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
                        Padding(
                          // Reserve real layout space for the controls so they
                          // remain tappable while visually sliding from behind
                          // the card.
                          padding: const EdgeInsets.only(top: 55),
                          child: GestureDetector(
                            onTap: () {
                              _closeGenreMenu();
                              setState(() {
                                _showControls = !_showControls;
                              });
                            },
                            child: Container(
                            width: 300,
                            padding: const EdgeInsets.fromLTRB(18, 40, 18, 18),
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
                                // Cover Image / Play Button. Only the centered
                                // play area owns the playback tap; tapping the
                                // poster around it reaches the card and toggles
                                // the sliding details, as on mobile web.
                                Stack(
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
                                                  imageUrl: activeTrack!.cover,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) =>
                                                      _buildDefaultCoverBrand(),
                                                  errorWidget:
                                                      (context, url, error) =>
                                                          _buildDefaultCoverBrand(),
                                                )
                                              : _buildDefaultCoverBrand(),
                                        ),
                                      ),

                                      // Ripple Loading Spinner
                                      if (isLoading)
                                        const SpinKitRipple(
                                          color: Color(0xFF64EEFF),
                                          size: 150,
                                        ),

                                      // Play Button Overlay (when paused and not loading)
                                      // Group-opacity 0.4 matches the frontend's
                                      // `.play-button-box { opacity: 0.4 }` rule, which
                                      // dims the whole circle + triangle together.
                                      if (!isLoading)
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: widget.audioService.playMusic,
                                          child: Opacity(
                                            opacity: isPlaying ? 0 : 0.4,
                                            child: Container(
                                              width: 150,
                                              height: 150,
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF10191A,
                                                ).withOpacity(0.593),
                                                shape: BoxShape.circle,
                                              ),
                                              alignment: Alignment.center,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 6,
                                                ),
                                                child: _RightTriangle(
                                                  width: 28,
                                                  height: 38,
                                                  color: const Color(
                                                    0xFF52DCFF,
                                                  ).withOpacity(0.7),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
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

                                // Mobile frontend keeps metadata collapsed on
                                // first render (`max-h-0`) and slides it open
                                // when the player body is tapped.
                                ClipRect(
                                  child: AnimatedSize(
                                    duration: const Duration(seconds: 1),
                                    curve: Curves.easeInOut,
                                    alignment: Alignment.topCenter,
                                    child: _showControls
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8,
                                              right: 8,
                                              top: 8,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        activeTrack?.title ??
                                                            'Dance Baby Radio',
                                                        style: const TextStyle(
                                                          color:
                                                              Color(0xFF23C1D2),
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      Text(
                                                        activeTrack?.artist ??
                                                            '',
                                                        style: TextStyle(
                                                          color: const Color(
                                                            0xFF23C1D2,
                                                          ).withOpacity(0.7),
                                                          fontSize: 10,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${_formatDuration(currentTime)} / '
                                                  '${_formatDuration(duration)}',
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.6),
                                                    fontSize: 9,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : const SizedBox(
                                            width: double.infinity,
                                            height: 0,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
                // Group-opacity 0.6 matches the frontend's
                // `.next-button-box { opacity: .6 }` rule.
                Positioned(
                  bottom: 27 + MediaQuery.of(context).padding.bottom,
                  right: 20,
                  child: GestureDetector(
                    onTap: () {
                      _closeGenreMenu();
                      widget.audioService.playNextMusic();
                    },
                    child: Opacity(
                      opacity: 0.6,
                      child: Container(
                        width: 83,
                        height: 81,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10191A).withOpacity(0.592),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF003E47),
                            width: 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Padding(
                          // Nudge right to visually center the pair of
                          // right-pointing "skip" triangles in the circle.
                          padding: const EdgeInsets.only(left: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _RightTriangle(
                                width: 12,
                                height: 16,
                                color: const Color(0xFF52DCFF).withOpacity(0.7),
                              ),
                              const SizedBox(width: 3),
                              _RightTriangle(
                                width: 12,
                                height: 16,
                                color: const Color(0xFF52DCFF).withOpacity(0.7),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
    );
  }
}
