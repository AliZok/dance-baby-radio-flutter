import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/playlist.dart';
import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../screens/login_screen.dart';
import '../screens/playlists_screen.dart';

/// Playlist icon + overlay menu (Nuxt PlayerMain mobile playlist dropdown).
class PlaylistSelector extends StatefulWidget {
  final AuthService authService;
  final AudioService audioService;
  final PlaylistService playlistService;
  final bool isOpen;
  final ValueChanged<bool> onOpenChanged;

  const PlaylistSelector({
    super.key,
    required this.authService,
    required this.audioService,
    required this.playlistService,
    required this.isOpen,
    required this.onOpenChanged,
  });

  @override
  State<PlaylistSelector> createState() => PlaylistSelectorState();
}

class PlaylistSelectorState extends State<PlaylistSelector> {
  OverlayEntry? _overlayEntry;

  List<Playlist> _playlists = [];
  List<String> _trackPlaylistIds = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_onAuthChanged);
    widget.audioService.addListener(_onTrackChanged);
    if (widget.authService.isLoggedIn) {
      _refresh();
    }
    if (widget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());
    }
  }

  @override
  void didUpdateWidget(covariant PlaylistSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());
    } else if (widget.isOpen) {
      _overlayEntry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    widget.authService.removeListener(_onAuthChanged);
    widget.audioService.removeListener(_onTrackChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onAuthChanged() {
    if (widget.authService.isLoggedIn) {
      _refresh();
    } else {
      setState(() {
        _playlists = [];
        _trackPlaylistIds = [];
      });
    }
    _overlayEntry?.markNeedsBuild();
  }

  void _onTrackChanged() {
    _refreshTrackIds();
    _overlayEntry?.markNeedsBuild();
  }

  Future<void> _refresh() async {
    await Future.wait([_loadPlaylists(), _refreshTrackIds()]);
    _overlayEntry?.markNeedsBuild();
  }

  Future<void> _loadPlaylists() async {
    if (!widget.authService.isLoggedIn) return;
    final result = await widget.playlistService.getUserPlaylists();
    if (!mounted) return;
    setState(() => _playlists = result.data);
  }

  Future<void> _refreshTrackIds() async {
    final track = widget.audioService.activeTrack;
    if (track == null || !widget.authService.isLoggedIn) {
      if (mounted) setState(() => _trackPlaylistIds = []);
      return;
    }
    final result = await widget.playlistService.getTrackPlaylistIds(track.id);
    if (!mounted) return;
    setState(() => _trackPlaylistIds = result.data);
  }

  bool get _isInAnyPlaylist => _trackPlaylistIds.isNotEmpty;

  void _syncOverlay() {
    if (!mounted) return;
    if (widget.isOpen) {
      _showOverlay();
      _refresh();
    } else {
      _removeOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Positions the menu inside the screen (never overflows the phone frame).
  ({double left, double top, double width, double maxHeight}) _menuRect() {
    final box = context.findRenderObject() as RenderBox?;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final pad = media.padding;

    const menuWidth = 240.0;
    const gap = 8.0;
    const edge = 12.0;
    final maxHeight = (screen.height * 0.42).clamp(140.0, 280.0);

    if (box == null || !box.hasSize) {
      return (
        left: edge,
        top: pad.top + 80,
        width: menuWidth,
        maxHeight: maxHeight,
      );
    }

    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;

    // Prefer opening to the LEFT of the icon (mobile Nuxt).
    double left = origin.dx - menuWidth - gap;
    if (left < edge) {
      // Not enough room — open to the right, still clamped.
      left = origin.dx + size.width + gap;
    }
    left = left.clamp(edge, screen.width - menuWidth - edge);

    double top = origin.dy;
    final minTop = pad.top + edge;
    final maxTop = screen.height - pad.bottom - maxHeight - edge;
    top = top.clamp(minTop, maxTop < minTop ? minTop : maxTop);

    return (left: left, top: top, width: menuWidth, maxHeight: maxHeight);
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final rect = _menuRect();
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onOpenChanged(false),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              child: Material(
                color: Colors.transparent,
                elevation: 28,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: rect.maxHeight),
                  child: _buildMenu(overlayContext),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_overlayEntry!);
  }

  Widget _playlistIcon({required bool active}) {
    return Opacity(
      opacity: active ? 1 : 0.4,
      child: SvgPicture.string(
        '''
        <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" fill="#52DCFF" viewBox="0 0 16 16">
          <path d="M12 13c0 1.105-1.12 2-2.5 2S7 14.105 7 13s1.12-2 2.5-2 2.5.895 2.5 2"/>
          <path fill-rule="evenodd" d="M12 3v10h-1V3z"/>
          <path d="M11 2.82a1 1 0 0 1 .804-.98l3-.6A1 1 0 0 1 16 2.22V4l-5 1z"/>
          <path fill-rule="evenodd" d="M0 11.5a.5.5 0 0 1 .5-.5H4a.5.5 0 0 1 0 1H.5a.5.5 0 0 1-.5-.5m0-4A.5.5 0 0 1 .5 7H8a.5.5 0 0 1 0 1H.5a.5.5 0 0 1-.5-.5m0-4A.5.5 0 0 1 .5 3H8a.5.5 0 0 1 0 1H.5a.5.5 0 0 1-.5-.5"/>
        </svg>
        ''',
        width: 22,
        height: 22,
      ),
    );
  }

  Widget _playIcon({required bool paused}) {
    if (paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 3, height: 10, color: AppColors.primary),
          const SizedBox(width: 2),
          Container(width: 3, height: 10, color: AppColors.primary),
        ],
      );
    }
    return CustomPaint(
      size: const Size(8, 10),
      painter: _MiniPlayTrianglePainter(AppColors.primary),
    );
  }

  Future<void> _onPlaylistTap(Playlist playlist) async {
    final track = widget.audioService.activeTrack;
    if (track == null || _busy) return;

    final name = playlist.name;
    final already = _trackPlaylistIds.contains(playlist.id);
    setState(() => _busy = true);
    _overlayEntry?.markNeedsBuild();

    if (already) {
      final result = await widget.playlistService.removeTrackFromPlaylist(
        playlist.id,
        track.id,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (result.error != null) {
        AppToast.error(context, result.error!, title: 'Playlist');
        _overlayEntry?.markNeedsBuild();
        return;
      }
      setState(() {
        _trackPlaylistIds =
            _trackPlaylistIds.where((id) => id != playlist.id).toList();
      });
      AppToast.success(
        context,
        '“${track.title}” removed from “$name”.',
        title: 'Removed from playlist',
      );
      _overlayEntry?.markNeedsBuild();
      return;
    }

    final result =
        await widget.playlistService.addTrackToPlaylist(playlist.id, track.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      AppToast.error(context, result.error!, title: 'Playlist');
      _overlayEntry?.markNeedsBuild();
      return;
    }
    setState(() => _trackPlaylistIds = [..._trackPlaylistIds, playlist.id]);
    AppToast.success(
      context,
      '“${track.title}” added to “$name”.',
      title: 'Added to playlist',
    );
    _overlayEntry?.markNeedsBuild();
  }

  Future<void> _playFromPlaylist(Playlist playlist) async {
    if (_busy) return;

    if (widget.audioService.activePlaybackPlaylist?.id == playlist.id) {
      setState(() => _busy = true);
      widget.onOpenChanged(false);
      try {
        await widget.audioService.returnToMainRandom();
        if (mounted) {
          AppToast.success(context, 'Back to main radio shuffle.', title: 'Radio');
        }
      } catch (e) {
        if (mounted) {
          AppToast.error(context, e.toString(), title: 'Radio');
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    setState(() => _busy = true);
    _overlayEntry?.markNeedsBuild();
    try {
      final result = await widget.playlistService.getPlaylistTracks(playlist.id);
      if (result.error != null) {
        throw Exception(result.error);
      }
      final playable = result.data.where((t) => t.audio.isNotEmpty).toList();
      if (playable.isEmpty) {
        if (mounted) {
          AppToast.error(
            context,
            '“${playlist.name}” has no playable tracks yet.',
            title: 'Empty playlist',
          );
        }
        return;
      }
      widget.onOpenChanged(false);
      await widget.audioService.playFromPlaylist(playlist, playable);
      if (mounted) {
        AppToast.success(
          context,
          'Now playing from “${playlist.name}”.',
          title: 'Playlist',
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, e.toString(), title: 'Playlist');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goLogin() async {
    widget.onOpenChanged(false);
    final nav = Navigator.of(context);
    await nav.push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(authService: widget.authService),
      ),
    );
    if (mounted && widget.authService.isLoggedIn) {
      await _refresh();
    }
  }

  Future<void> _goPlaylists() async {
    widget.onOpenChanged(false);
    final nav = Navigator.of(context);
    await nav.push(
      MaterialPageRoute(
        builder: (_) => PlaylistsScreen(
          authService: widget.authService,
          playlistService: widget.playlistService,
        ),
      ),
    );
    if (mounted && widget.authService.isLoggedIn) {
      await _refresh();
    }
  }

  Widget _buildMenu(BuildContext menuContext) {
    final activeSourceId = widget.audioService.activePlaybackPlaylist?.id;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
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
      child: !widget.authService.isLoggedIn
          ? _emptyBlock(
              title: 'Login required',
              text: 'Sign in to create playlists and save tracks.',
              actionLabel: 'Login',
              onAction: _goLogin,
            )
          : _playlists.isEmpty
              ? _emptyBlock(
                  title: 'No playlists',
                  text: 'Create a playlist first, then you can add this track.',
                  actionLabel: 'Create playlist',
                  onAction: _goPlaylists,
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    final inList = _trackPlaylistIds.contains(playlist.id);
                    final isSource = activeSourceId == playlist.id;
                    return _PlaylistRow(
                      name: playlist.name.isEmpty ? 'Untitled' : playlist.name,
                      containsTrack: inList,
                      isPlayingSource: isSource,
                      busy: _busy,
                      onNameTap: () => _onPlaylistTap(playlist),
                      onPlayTap: () => _playFromPlaylist(playlist),
                      playIcon: _playIcon(paused: isSource),
                    );
                  },
                ),
    );
  }

  Widget _emptyBlock({
    required String title,
    required String text,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          style: TextStyle(
            color: AppColors.primary.withOpacity(0.8),
            fontSize: 12,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onAction,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xEB0A161A),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel,
                  style: const TextStyle(color: AppColors.primary, fontSize: 12),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.open_in_new,
                  size: 13,
                  color: AppColors.primary.withOpacity(0.9),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeSourceId = widget.audioService.activePlaybackPlaylist?.id;
    final iconActive = _isInAnyPlaylist || activeSourceId != null;

    // Frontend `.control-item`: 44×44, border-radius 7px
    return SizedBox(
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => widget.onOpenChanged(!widget.isOpen),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: const Color(0xEB0A161A),
            borderRadius: BorderRadius.circular(7),
            boxShadow: iconActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF52DCFF).withOpacity(0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: _playlistIcon(active: iconActive),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final String name;
  final bool containsTrack;
  final bool isPlayingSource;
  final bool busy;
  final VoidCallback onNameTap;
  final VoidCallback onPlayTap;
  final Widget playIcon;

  const _PlaylistRow({
    required this.name,
    required this.containsTrack,
    required this.isPlayingSource,
    required this.busy,
    required this.onNameTap,
    required this.onPlayTap,
    required this.playIcon,
  });

  @override
  Widget build(BuildContext context) {
    final highlighted = containsTrack || isPlayingSource;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPlayingSource
              ? AppColors.primary.withOpacity(0.55)
              : containsTrack
                  ? AppColors.primary.withOpacity(0.4)
                  : AppColors.primary.withOpacity(0.08),
        ),
        gradient: highlighted
            ? LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: isPlayingSource
                    ? [
                        AppColors.primary.withOpacity(0.28),
                        const Color(0xB80A3038),
                        AppColors.primary.withOpacity(0.12),
                      ]
                    : [
                        AppColors.primary.withOpacity(0.16),
                        const Color(0x990A282E),
                        AppColors.primary.withOpacity(0.06),
                      ],
              )
            : null,
        color: highlighted ? null : const Color(0x8C061014),
        boxShadow: isPlayingSource
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.14),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onNameTap,
              behavior: HitTestBehavior.opaque,
              child: Opacity(
                opacity: highlighted ? 1 : 0.45,
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: highlighted
                        ? const Color(0xFFE8FBFF)
                        : Colors.white,
                    fontSize: 13,
                    fontWeight:
                        highlighted ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: busy ? null : onPlayTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPlayingSource
                    ? AppColors.primary.withOpacity(0.45)
                    : AppColors.primary.withOpacity(0.12),
                border: Border.all(
                  color: isPlayingSource
                      ? AppColors.primary.withOpacity(0.9)
                      : AppColors.primary.withOpacity(0.35),
                ),
              ),
              alignment: Alignment.center,
              child: playIcon,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPlayTrianglePainter extends CustomPainter {
  final Color color;
  _MiniPlayTrianglePainter(this.color);

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
  bool shouldRepaint(covariant _MiniPlayTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
