import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/audio_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_colors.dart';
import '../screens/login_screen.dart';
import '../screens/playlists_screen.dart';

/// Brand header + account hamburger (Nuxt HeaderMain).
/// Account dropdown uses [Overlay] so it never falls under the player card.
class AppHeader extends StatefulWidget {
  final AuthService authService;
  final AudioService audioService;
  final PlaylistService playlistService;
  final bool showPlayingIcon;
  final int dismissToken;
  /// When false, header slides up off-screen (immersive chrome).
  final bool visible;
  /// Nuxt `onMobilePageClick` treats a tap anywhere in `.playing-status` (the
  /// brand / radio tape / LIVE toggle) as "inside the player chrome", so it
  /// slides the chrome back in instead of toggling it off.
  final VoidCallback? onChromeTap;

  const AppHeader({
    super.key,
    required this.authService,
    required this.audioService,
    required this.playlistService,
    this.showPlayingIcon = true,
    this.dismissToken = 0,
    this.visible = true,
    this.onChromeTap,
  });

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  final LayerLink _menuLink = LayerLink();
  OverlayEntry? _menuEntry;
  bool _menuOpen = false;

  @override
  void didUpdateWidget(covariant AppHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dismissToken != oldWidget.dismissToken && _menuOpen) {
      _closeMenu();
    }
    if (!widget.visible && oldWidget.visible && _menuOpen) {
      _closeMenu();
    }
  }

  @override
  void dispose() {
    _removeMenuOverlay();
    super.dispose();
  }

  void _closeMenu() {
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
    _removeMenuOverlay();
  }

  void _removeMenuOverlay() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  void _toggleMenu() {
    if (_menuOpen) {
      _closeMenu();
      return;
    }
    setState(() => _menuOpen = true);
    _showMenuOverlay();
  }

  void _showMenuOverlay() {
    _removeMenuOverlay();
    final overlay = Overlay.of(context);
    final loggedIn = widget.authService.isLoggedIn;
    _menuEntry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        final pad = MediaQuery.paddingOf(ctx);
        const menuWidth = 200.0;

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeMenu,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            CompositedTransformFollower(
              link: _menuLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 8),
              child: Material(
                color: Colors.transparent,
                elevation: 24,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: menuWidth,
                    maxHeight: size.height - pad.bottom - 120,
                  ),
                  child: Container(
                    width: menuWidth,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xF0081216),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.14)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Nuxt HeaderMain dropdown order: email, Playlists,
                        // Login / Log out. Email + Playlists only when signed
                        // in — the ☰ itself is always there (see below).
                        if (loggedIn) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                            child: Text(
                              widget.authService.currentUser?.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.brandSoft.withOpacity(0.85),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: AppColors.primary.withOpacity(0.12),
                          ),
                          _menuItem('Playlists', () async {
                            _closeMenu();
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PlaylistsScreen(
                                  authService: widget.authService,
                                  audioService: widget.audioService,
                                  playlistService: widget.playlistService,
                                ),
                              ),
                            );
                          }),
                        ],
                        if (!loggedIn)
                          _menuItem('Login', () {
                            _closeMenu();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LoginScreen(
                                  authService: widget.authService,
                                  audioService: widget.audioService,
                                ),
                              ),
                            );
                          }),
                        if (loggedIn)
                          _menuItem('Log out', () async {
                            _closeMenu();
                            widget.audioService.clearPlaylistModeOnLogout();
                            await widget.authService.signOut();
                            if (!mounted) return;
                            // Nuxt `handleLogout()` shows no toast — the login
                            // page appearing is the whole feedback.
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LoginScreen(
                                  authService: widget.authService,
                                  audioService: widget.audioService,
                                ),
                              ),
                            );
                          }, danger: true),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_menuEntry!);
  }

  Widget _menuItem(String label, VoidCallback onTap, {bool danger = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          label,
          style: TextStyle(
            color: danger ? AppColors.danger : Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBrand(bool isPlaying) {
    final brand = Row(
      children: [
        Flexible(
          child: Text(
            'DANCE BABY RADIO',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.daysOne(
              // Slightly smaller than before so title + playing radio
              // both fit on narrow phones without clipping the icon.
              fontSize: 15,
              color: AppColors.brand,
              shadows: [
                Shadow(
                  color: const Color(0xFFCCFBF7).withOpacity(0.5),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
        // Nuxt HeaderMain: small radio appears beside the brand while playing.
        if (widget.showPlayingIcon && isPlaying) ...[
          const SizedBox(width: 8),
          Opacity(
            opacity: 0.6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                'assets/images/radio-playing-2.webp',
                width: 44,
                height: 25,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
        // Nuxt: the LIVE toggle sits beside the playing radio icon and switches
        // the shared live station on/off. Always available on the player page.
        const SizedBox(width: 8),
        _LiveToggleButton(
          audioService: widget.audioService,
          onChromeTap: widget.onChromeTap,
        ),
      ],
    );

    // The title / radio-tape part of `.playing-status` has no control of its
    // own, so a tap there only reveals the sliding chrome.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onChromeTap,
      child: brand,
    );
  }

  static const _chromeButtonDecoration = BoxDecoration(
    color: Color(0xEB0A161A),
    borderRadius: BorderRadius.all(Radius.circular(7)),
  );

  Widget _buildAccountButton(AuthService auth) {
    // Nuxt HeaderMain always renders the ☰ trigger (signed in or not) — the
    // dropdown itself decides between Login and Playlists / Log out.
    return CompositedTransformTarget(
      link: _menuLink,
      child: GestureDetector(
        onTap: _toggleMenu,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: _chromeButtonDecoration,
          child: const Text(
            '☰',
            style: TextStyle(color: AppColors.brand, fontSize: 18),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.authService, widget.audioService]),
      builder: (context, _) {
        final auth = widget.authService;
        final isPlaying = widget.audioService.isPlaying;

        // Brand + playing radio stay visible by default (Nuxt HeaderMain).
        // Login / account menu only appear with chrome after a page tap.
        return Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildBrand(isPlaying)),
              IgnorePointer(
                ignoring: !widget.visible,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutCubic,
                  offset:
                      widget.visible ? Offset.zero : const Offset(1.2, 0),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 280),
                    opacity: widget.visible ? 1 : 0,
                    child: _buildAccountButton(auth),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Header "GO LIVE" / "LIVE" toggle (Nuxt HeaderMain `.live-toggle`).
/// Switches the shared live radio station on and back to shuffle.
class _LiveToggleButton extends StatefulWidget {
  final AudioService audioService;
  final VoidCallback? onChromeTap;

  const _LiveToggleButton({required this.audioService, this.onChromeTap});

  @override
  State<_LiveToggleButton> createState() => _LiveToggleButtonState();
}

class _LiveToggleButtonState extends State<_LiveToggleButton> {
  void _onTap() {
    // Nuxt `toggleLiveMode()`: only flips the *desired* mode and is ignored
    // while a switch is already running. The toast comes from the service when
    // the mode actually changes (a request made during the Let's GO gate is
    // deferred, so raising it here would be wrong).
    widget.onChromeTap?.call();
    if (widget.audioService.modeBusy) return;
    if (widget.audioService.wantLive) {
      widget.audioService.requestRandom();
    } else {
      widget.audioService.requestLive();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.audioService,
      builder: (context, _) {
        // Nuxt labels the button with `wantLive` (the request), not the mode
        // that is currently on air, so a pending switch is visible at once.
        final wantLive = widget.audioService.wantLive;
        final disabled = widget.audioService.modeBusy;

        // Frontend colors: idle #90999d, active #ff8da3.
        final color = wantLive
            ? const Color(0xFFFF8DA3)
            : const Color(0xFF90999D).withOpacity(disabled ? 0.5 : 1.0);

        return Opacity(
          opacity: disabled ? 0.5 : 1.0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: disabled ? null : _onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LivePulseDot(active: wantLive),
                  const SizedBox(width: 5),
                  Text(
                    wantLive ? 'LIVE' : 'GO LIVE',
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      height: 1,
                    ),
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

/// The small status dot — steady gray when idle, pulsing red when live
/// (Nuxt `.live-dot` + `live-pulse` keyframes).
class _LivePulseDot extends StatefulWidget {
  final bool active;
  const _LivePulseDot({required this.active});

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _LivePulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          color: Color(0xFF6D7579),
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFFFF4D6D),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4D6D).withOpacity(0.5 + 0.4 * t),
                blurRadius: 4 + 3 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}
