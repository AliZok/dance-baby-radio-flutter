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

  const AppHeader({
    super.key,
    required this.authService,
    required this.audioService,
    required this.playlistService,
    this.showPlayingIcon = true,
    this.dismissToken = 0,
    this.visible = true,
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
                        Divider(height: 1, color: AppColors.primary.withOpacity(0.12)),
                        _menuItem('Playlists', () async {
                          _closeMenu();
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlaylistsScreen(
                                authService: widget.authService,
                                playlistService: widget.playlistService,
                              ),
                            ),
                          );
                        }),
                        _menuItem('Log out', () async {
                          _closeMenu();
                          widget.audioService.clearPlaylistModeOnLogout();
                          await widget.authService.signOut();
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    LoginScreen(authService: widget.authService),
                              ),
                            );
                          }
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
    return Row(
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
      ],
    );
  }

  static const _chromeButtonDecoration = BoxDecoration(
    color: Color(0xEB0A161A),
    borderRadius: BorderRadius.all(Radius.circular(7)),
  );

  Widget _buildAccountButton(AuthService auth) {
    if (auth.isLoggedIn) {
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

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LoginScreen(authService: widget.authService),
          ),
        );
      },
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: _chromeButtonDecoration,
        child: Icon(
          Icons.login_rounded,
          color: AppColors.brand,
          size: 22,
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
