import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import '../models/music.dart';
import '../models/playlist.dart';
import '../services/auth_service.dart';
import '../services/playlist_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import 'login_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  final AuthService authService;
  final PlaylistService playlistService;

  const PlaylistsScreen({
    super.key,
    required this.authService,
    required this.playlistService,
  });

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<Playlist> _playlists = [];
  Playlist? _selected;
  List<Music> _tracks = [];
  bool _loading = false;
  bool _tracksLoading = false;
  String? _error;

  final _localPlayer = AudioPlayer();
  Music? _activeTrack;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.authService.addListener(_onAuthChanged);
    _localPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _localPlayer.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _localPlayer.playerStateStream.listen((s) {
      if (mounted) {
        setState(() {
          _isPlaying = s.playing;
          if (s.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _position = Duration.zero;
          }
        });
      }
    });

    if (widget.authService.isLoggedIn) {
      _loadPlaylists();
    }
  }

  void _onAuthChanged() {
    if (widget.authService.isLoggedIn) {
      _loadPlaylists();
    } else {
      setState(() {
        _playlists = [];
        _selected = null;
        _tracks = [];
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    widget.authService.removeListener(_onAuthChanged);
    _localPlayer.dispose();
    super.dispose();
  }

  Future<void> _stopLocal() async {
    await _localPlayer.stop();
    setState(() {
      _activeTrack = null;
      _isPlaying = false;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
  }

  Future<void> _loadPlaylists() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.playlistService.getUserPlaylists();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.error != null) {
        _error = result.error;
        _playlists = [];
      } else {
        _playlists = result.data;
      }
    });
  }

  Future<void> _openPlaylist(Playlist playlist) async {
    await _stopLocal();
    setState(() {
      _selected = playlist;
      _tracks = [];
      _tracksLoading = true;
      _error = null;
    });
    final result = await widget.playlistService.getPlaylistTracks(playlist.id);
    if (!mounted) return;
    setState(() {
      _tracksLoading = false;
      if (result.error != null) {
        _error = result.error;
        _tracks = [];
      } else {
        _tracks = result.data;
      }
    });
  }

  Future<void> _toggleTrack(Music track) async {
    if (track.audio.isEmpty) return;

    if (_activeTrack?.id == track.id && _isPlaying) {
      await _localPlayer.pause();
      return;
    }

    if (_activeTrack?.id != track.id) {
      setState(() {
        _activeTrack = track;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
      await _localPlayer.setUrl(track.audio);
    }
    await _localPlayer.play();
  }

  Future<void> _confirmRemoveTrack(Music track) async {
    final playlist = _selected;
    if (playlist == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xF008282C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.primary.withOpacity(0.2)),
        ),
        title: const Text(
          'Remove track?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove “${track.title}” from “${playlist.name}”?',
          style: TextStyle(color: AppColors.brandSoft.withOpacity(0.85), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger.withOpacity(0.85),
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _removeTrack(track);
  }

  Future<void> _removeTrack(Music track) async {
    final playlist = _selected;
    if (playlist == null) return;

    final result = await widget.playlistService.removeTrackFromPlaylist(
      playlist.id,
      track.id,
    );
    if (!mounted) return;

    if (result.error != null) {
      AppToast.error(context, result.error!, title: 'Playlist');
      return;
    }

    if (_activeTrack?.id == track.id) {
      await _stopLocal();
    }

    setState(() {
      _tracks = _tracks.where((t) => t.id != track.id).toList();
      _selected = playlist.copyWith(trackCount: _tracks.length);
      _playlists = _playlists
          .map((p) => p.id == playlist.id
              ? p.copyWith(trackCount: _tracks.length)
              : p)
          .toList();
    });

    AppToast.success(
      context,
      '“${track.title}” removed from “${playlist.name}”.',
      title: 'Removed from playlist',
    );
  }

  Future<void> _showCreateModal() async {
    final controller = TextEditingController();
    String? createError;
    var creating = false;
    var nameText = '';

    await showDialog<void>(
      context: context,
      barrierDismissible: !creating,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final canCreate = !creating && nameText.trim().isNotEmpty;
            return AlertDialog(
              backgroundColor: const Color(0xF008282C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.primary.withOpacity(0.2)),
              ),
              title: const Text(
                'New playlist',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Give your playlist a name',
                    style: TextStyle(color: AppColors.brandSoft.withOpacity(0.8), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 80,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (v) => setModalState(() => nameText = v),
                    onSubmitted: (_) async {
                      if (!canCreate) return;
                      setModalState(() {
                        creating = true;
                        createError = null;
                      });
                      final result = await widget.playlistService.createPlaylist(
                        name: controller.text,
                      );
                      if (result.error != null) {
                        setModalState(() {
                          creating = false;
                          createError = result.error;
                        });
                        return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _loadPlaylists();
                      if (mounted && result.data != null) {
                        AppToast.success(
                          context,
                          '“${result.data!.name}” created.',
                          title: 'Playlist',
                        );
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'e.g. Night Drive',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                      counterStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      filled: true,
                      fillColor: AppColors.inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.primary.withOpacity(0.55)),
                      ),
                    ),
                  ),
                  if (createError != null)
                    Text(createError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: creating ? null : () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                ),
                ElevatedButton(
                  onPressed: !canCreate
                      ? null
                      : () async {
                          setModalState(() {
                            creating = true;
                            createError = null;
                          });
                          final result = await widget.playlistService.createPlaylist(
                            name: controller.text,
                          );
                          if (result.error != null) {
                            setModalState(() {
                              creating = false;
                              createError = result.error;
                            });
                            return;
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadPlaylists();
                          if (mounted && result.data != null) {
                            AppToast.success(
                              context,
                              '“${result.data!.name}” created.',
                              title: 'Playlist',
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.withOpacity(0.35),
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.12),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white38,
                  ),
                  child: Text(creating ? 'Creating...' : 'Create'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.authService,
      builder: (context, _) {
        final auth = widget.authService;
        final title = _selected?.name ?? 'Playlists';
        final subtitle = _selected != null
            ? '${_tracks.length} track${_tracks.length == 1 ? '' : 's'} in this playlist'
            : 'Your personal collections';

        return Scaffold(
          backgroundColor: const Color(0xFF06161B),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.brand),
              onPressed: () {
                if (_selected != null) {
                  _stopLocal();
                  setState(() {
                    _selected = null;
                    _tracks = [];
                    _error = null;
                  });
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.daysOne(color: AppColors.brand, fontSize: 20),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: AppColors.brandSoft.withOpacity(0.75), fontSize: 12),
                ),
              ],
            ),
            actions: [
              if (auth.isLoggedIn && _selected == null)
                IconButton(
                  onPressed: _showCreateModal,
                  icon: const Icon(Icons.add, color: AppColors.primary, size: 28),
                  tooltip: 'Create playlist',
                ),
            ],
          ),
          body: !auth.authReady
              ? const Center(child: Text('Loading...', style: TextStyle(color: Colors.white70)))
              : !auth.isLoggedIn
                  ? _buildLoginGate()
                  : _loading
                      ? const Center(child: Text('Loading...', style: TextStyle(color: Colors.white70)))
                      : _error != null && _selected == null && _playlists.isEmpty
                          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                          : _selected != null
                              ? _buildTracksView()
                              : _buildGridView(),
        );
      },
    );
  }

  Widget _buildLoginGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('♪', style: TextStyle(fontSize: 42, color: AppColors.primary.withOpacity(0.7))),
            const SizedBox(height: 12),
            const Text(
              'Login required',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to view and manage your playlists.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.brandSoft.withOpacity(0.8), fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LoginScreen(authService: widget.authService),
                  ),
                );
                if (mounted && widget.authService.isLoggedIn) {
                  await _loadPlaylists();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.withOpacity(0.35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
              child: const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridView() {
    if (_playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('＋', style: TextStyle(fontSize: 36, color: AppColors.primary.withOpacity(0.7))),
              const SizedBox(height: 12),
              const Text(
                'No playlists yet',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                "You don't have any playlists. Tap the + button to create your first one.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.brandSoft.withOpacity(0.8), fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _showCreateModal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary.withOpacity(0.35),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Create playlist'),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.92,
      ),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        final initial = playlist.name.trim().isNotEmpty
            ? playlist.name.trim()[0].toUpperCase()
            : '?';
        return InkWell(
          onTap: () => _openPlaylist(playlist),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.18)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0A2228).withOpacity(0.95),
                  const Color(0xFF06161B).withOpacity(0.98),
                ],
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withOpacity(0.25),
                          AppColors.secondary.withOpacity(0.08),
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: GoogleFonts.daysOne(
                        fontSize: 42,
                        color: AppColors.primary.withOpacity(0.9),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${playlist.trackCount} track${playlist.trackCount == 1 ? '' : 's'}',
                  style: TextStyle(color: AppColors.brandSoft.withOpacity(0.7), fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTracksView() {
    if (_tracksLoading) {
      return const Center(child: Text('Loading tracks...', style: TextStyle(color: Colors.white70)));
    }
    if (_tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('♪', style: TextStyle(fontSize: 42, color: AppColors.primary.withOpacity(0.7))),
              const SizedBox(height: 12),
              const Text(
                'No tracks yet',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'This playlist is empty. Tracks you add will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.brandSoft.withOpacity(0.8), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final track = _tracks[index];
        final active = _activeTrack?.id == track.id;
        final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
        final posMs = active
            ? _position.inMilliseconds.toDouble().clamp(0.0, maxMs).toDouble()
            : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: active
                ? AppColors.primary.withOpacity(0.1)
                : Colors.white.withOpacity(0.03),
            border: Border.all(
              color: active
                  ? AppColors.primary.withOpacity(0.35)
                  : AppColors.primary.withOpacity(0.1),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: track.audio.isEmpty ? null : () => _toggleTrack(track),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppColors.primary.withOpacity(0.15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        active && _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (track.artist.isNotEmpty) track.artist,
                            if (track.genre.isNotEmpty) track.genre,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.brandSoft.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove from playlist',
                    onPressed: () => _confirmRemoveTrack(track),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger.withOpacity(0.9),
                      size: 22,
                    ),
                  ),
                ],
              ),
              if (active) ...[
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: AppColors.primary.withOpacity(0.85),
                    inactiveTrackColor: AppColors.primary.withOpacity(0.18),
                    thumbColor: AppColors.primary,
                  ),
                  child: Slider(
                    min: 0,
                    max: maxMs,
                    value: posMs,
                    onChanged: (v) {
                      setState(() => _position = Duration(milliseconds: v.round()));
                    },
                    onChangeEnd: (v) {
                      _localPlayer.seek(Duration(milliseconds: v.round()));
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
