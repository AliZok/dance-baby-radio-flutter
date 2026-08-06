import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music.dart';
import '../models/genre.dart';
import '../models/playlist.dart';
import 'supabase_service.dart';

class AudioService extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();
  final _random = Random();
  
  // Dual audio players for gapless/seamless transition
  late AudioPlayer _playerPrimary;
  late AudioPlayer _playerSupport;

  // State variables
  Music? _currentOriginTrack; // Primary track
  Music? _currentSupportTrack; // Support track
  
  bool _originAudio = false; // false = Primary is active, true = Support is active
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _isAudioReady = false;
  bool _isRepeat = false;
  bool _isTransitioning = false;
  /// True when a Next arrived while a switch was already in progress — run
  /// one more transition after the current one finishes (do not drop taps).
  bool _queuedNext = false;
  /// In-flight preload of the inactive player after a Next. The next switch
  /// awaits this so we never flip onto a stale track, but we do not hold the
  /// transition lock for the whole network round-trip (that made Next feel
  /// broken and required multiple taps).
  Future<void>? _refillFuture;
  /// Bumped whenever a new inactive refill starts so an older in-flight
  /// request cannot overwrite a fresher genre-filter result.
  int _refillGeneration = 0;
  /// While true / until this timestamp, ignore ProcessingState.completed so a
  /// timeline scrub cannot race into playNextMusic (same class of bug as the
  /// Nuxt "don't sync both players on seek" fix).
  DateTime? _ignoreCompletedUntil;
  bool _hasStarted = false;
  double _volume = 1.0; // 0.0 to 1.0
  /// Last volume written to the active player (may be faded below [_volume]).
  double _lastAppliedPlayerVolume = 1.0;
  /// Fade the active track to silence over this window before it ends.
  static const Duration _fadeOutDuration = Duration(seconds: 4);
  /// Prevents stacked error→skip handlers from fighting over the dual players.
  bool _handlingPlaybackError = false;
  /// Caps auto-skip storms when several bad URLs land in a row.
  int _consecutiveLoadFailures = 0;
  static const int _maxConsecutiveLoadFailures = 8;

  Duration _currentTime = Duration.zero;
  Duration _duration = Duration.zero;

  final List<Music> _playbackHistory = [];
  List<Genre> _genres = [];

  // Playlist-as-radio-source mode (matches Nuxt activePlaybackPlaylist)
  Playlist? _activePlaybackPlaylist;
  List<Music> _activePlaylistTracks = [];

  // Subscriptions to clean up
  StreamSubscription? _primaryPositionSub;
  StreamSubscription? _primaryDurationSub;
  StreamSubscription? _primaryStateSub;
  StreamSubscription? _primaryErrorSub;
  
  StreamSubscription? _supportPositionSub;
  StreamSubscription? _supportDurationSub;
  StreamSubscription? _supportStateSub;
  StreamSubscription? _supportErrorSub;

  // Getters
  Music? get currentOriginTrack => _currentOriginTrack;
  Music? get currentSupportTrack => _currentSupportTrack;
  
  Music? get activeTrack => _originAudio ? _currentSupportTrack : _currentOriginTrack;
  AudioPlayer get activePlayer => _originAudio ? _playerSupport : _playerPrimary;
  AudioPlayer get inactivePlayer => _originAudio ? _playerPrimary : _playerSupport;

  bool get originAudio => _originAudio;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get isAudioReady => _isAudioReady;
  bool get isRepeat => _isRepeat;
  bool get hasStarted => _hasStarted;
  double get volume => _volume;

  Duration get currentTime => _currentTime;
  Duration get duration => _duration;

  List<Genre> get genres => _genres;
  List<String> get activeGenreFilters =>
      _genres.where((g) => g.active).map((g) => g.genre).toList();

  Playlist? get activePlaybackPlaylist => _activePlaybackPlaylist;
  bool get isPlaylistMode => _activePlaybackPlaylist != null;

  AudioService() {
    // Dual ExoPlayers share one Android audio session. Interruptions from the
    // inactive preload must not pause/stop the active track (that was causing
    // mid-song auto-skips when setUrl ran on the other player).
    _playerPrimary = AudioPlayer(handleInterruptions: false);
    _playerSupport = AudioPlayer(handleInterruptions: false);
    _initGenres();
    _setupListeners();
  }

  void _initGenres() {
    _genres = [
      Genre(genre: "raghsi", icon: "pop", text: "Persian Pop", active: false),
      Genre(genre: "pop", icon: "pop", text: "Pop", active: false),
      Genre(genre: "relax", icon: "pop", text: "Relax", active: false),
      Genre(genre: "rock", icon: "pop", text: "Rock", active: false),
      Genre(genre: "electronic", icon: "pop", text: "Electronic", active: true),
    ];
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    // Register as a native music session. This requests the correct Android
    // audio focus and lets playback continue naturally while the app is in the
    // background or the device is locked.
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // 1. Load genres from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final genresJson = prefs.getString('myGenres');
    if (genresJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(genresJson);
        _genres = decoded.map((item) => Genre.fromJson(item as Map<String, dynamic>)).toList();
      } catch (e) {
        print('Error decoding genres from prefs: $e');
      }
    }

    // Fetch + preload tracks, then autoplay. Native apps do not need a
    // Let's GO / Welcome gate (unlike the web autoplay policy).
    await _loadInitialTracks();
    if (_isAudioReady) {
      await startPlayback();
    }
  }

  /// Starts radio playback once tracks are ready (also used after playlist mode).
  Future<void> startPlayback() async {
    if (_hasStarted) {
      if (!_isPlaying) await resumeAudio();
      return;
    }
    _hasStarted = true;
    notifyListeners();

    if (!_isAudioReady) {
      await _loadInitialTracks();
    }
    if (_isAudioReady) {
      await resumeAudio();
    }
  }

  Music? _pickTrackFromActivePlaylist(Music? excludeTrack) {
    final playable =
        _activePlaylistTracks.where((t) => t.audio.isNotEmpty).toList();
    if (playable.isEmpty) return null;

    final candidates = excludeTrack == null
        ? playable
        : playable.where((t) => t.id != excludeTrack.id).toList();

    final pool = candidates.isNotEmpty ? candidates : playable;
    return pool[_random.nextInt(pool.length)];
  }

  Future<Music?> _fetchNextTrack({Music? excludeTrack}) async {
    if (_activePlaybackPlaylist != null && _activePlaylistTracks.isNotEmpty) {
      return _pickTrackFromActivePlaylist(excludeTrack);
    }
    return _supabaseService.getRandomActiveMusic(
      genreFilters: activeGenreFilters,
      excludeTrack: excludeTrack,
    );
  }

  Future<void> _loadInitialTracks() async {
    _isLoading = true;
    _isAudioReady = false;
    notifyListeners();

    try {
      // Fetch both in parallel
      final results = await Future.wait([
        _fetchNextTrack(),
        _fetchNextTrack(),
      ]);

      _currentOriginTrack = results[0];
      _currentSupportTrack = results[1];

      // If they are the same, fetch support again
      if (_currentOriginTrack != null &&
          _currentSupportTrack != null &&
          _currentOriginTrack!.id == _currentSupportTrack!.id) {
        _currentSupportTrack = await _fetchNextTrack(
          excludeTrack: _currentOriginTrack,
        );
      }

      // Preload players
      await _preloadPrimary();
      await _preloadSupport();

      _isLoading = false;
      _isAudioReady = true;
      notifyListeners();
    } catch (e) {
      print('Error loading initial tracks: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Enter playlist-as-source mode (or exit if same playlist is toggled).
  Future<void> playFromPlaylist(Playlist playlist, List<Music> tracks) async {
    final playable = tracks.where((t) => t.audio.isNotEmpty).toList();
    if (playable.isEmpty) {
      throw Exception('Empty playlist');
    }

    _activePlaybackPlaylist = playlist;
    _activePlaylistTracks = playable;
    _originAudio = false;
    notifyListeners();

    await _loadInitialTracks();
    _hasStarted = true;
    await resumeAudio();
  }

  /// Exit playlist mode and return to main radio shuffle.
  Future<void> returnToMainRandom() async {
    _activePlaybackPlaylist = null;
    _activePlaylistTracks = [];
    _originAudio = false;
    notifyListeners();

    await _loadInitialTracks();
    _hasStarted = true;
    await resumeAudio();
  }

  void clearPlaylistModeOnLogout() {
    _activePlaybackPlaylist = null;
    _activePlaylistTracks = [];
    notifyListeners();
  }

  Future<void> _preloadPrimary() async {
    if (_currentOriginTrack?.audio != null &&
        _currentOriginTrack!.audio.isNotEmpty) {
      try {
        await _playerPrimary.setUrl(_currentOriginTrack!.audio);
        // Preload only — never leave the buffer playing.
        await _playerPrimary.pause();
        await _playerPrimary.seek(Duration.zero);
      } catch (e) {
        print('Error preloading primary player: $e');
        await _replaceFailedSide(
          failed: _currentOriginTrack,
          isOriginSide: true,
        );
      }
    }
  }

  Future<void> _preloadSupport() async {
    if (_currentSupportTrack?.audio != null &&
        _currentSupportTrack!.audio.isNotEmpty) {
      try {
        await _playerSupport.setUrl(_currentSupportTrack!.audio);
        await _playerSupport.pause();
        await _playerSupport.seek(Duration.zero);
      } catch (e) {
        print('Error preloading support player: $e');
        await _replaceFailedSide(
          failed: _currentSupportTrack,
          isOriginSide: false,
        );
      }
    }
  }

  /// Ramp active-player volume to 0 over the last [_fadeOutDuration].
  /// Keeps user preference in [_volume] so the slider / next track stay correct.
  void _applyFadeOutVolume(Duration position) {
    var factor = 1.0;
    if (!_isTransitioning && _duration > Duration.zero) {
      final fadeMs = min(
        _fadeOutDuration.inMilliseconds,
        _duration.inMilliseconds,
      );
      final remainingMs = (_duration - position).inMilliseconds;
      if (remainingMs < fadeMs) {
        factor = (remainingMs / fadeMs).clamp(0.0, 1.0);
      }
    }

    final target = (_volume * factor).clamp(0.0, 1.0);
    if ((target - _lastAppliedPlayerVolume).abs() < 0.002) return;
    _lastAppliedPlayerVolume = target;
    unawaited(activePlayer.setVolume(target));
  }

  void _restoreFullVolume() {
    _lastAppliedPlayerVolume = _volume;
    unawaited(_playerPrimary.setVolume(_volume));
    unawaited(_playerSupport.setVolume(_volume));
  }

  void _setupListeners() {
    // Primary Player Listeners
    _primaryPositionSub = _playerPrimary.positionStream.listen((pos) {
      if (!_originAudio) {
        _currentTime = pos;
        _applyFadeOutVolume(pos);
        notifyListeners();
      }
    });

    _primaryDurationSub = _playerPrimary.durationStream.listen((dur) {
      if (!_originAudio && dur != null) {
        _duration = dur;
        _applyFadeOutVolume(_currentTime);
        notifyListeners();
      }
    });

    _primaryStateSub = _playerPrimary.playerStateStream.listen((state) {
      // Nuxt: onOriginEnded only fires next when primary is the active side.
      if (_originAudio) return;

      _isPlaying = state.playing;
      _isLoading = state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;

      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      }
      notifyListeners();
    });

    // Async load/play failures never reach the unawaited play() caller —
    // listen here so a dead URL still advances and auto-plays the next track.
    _primaryErrorSub = _playerPrimary.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (_originAudio) return; // inactive side — ignore
        if (_isTransitioning || _handlingPlaybackError) return;
        print('Primary playback error: $e');
        unawaited(_onActiveTrackFailed(_currentOriginTrack));
      },
    );

    // Support Player Listeners
    _supportPositionSub = _playerSupport.positionStream.listen((pos) {
      if (_originAudio) {
        _currentTime = pos;
        _applyFadeOutVolume(pos);
        notifyListeners();
      }
    });

    _supportDurationSub = _playerSupport.durationStream.listen((dur) {
      if (_originAudio && dur != null) {
        _duration = dur;
        _applyFadeOutVolume(_currentTime);
        notifyListeners();
      }
    });

    _supportStateSub = _playerSupport.playerStateStream.listen((state) {
      // Nuxt: onSupportEnded only when support is active.
      if (!_originAudio) return;

      _isPlaying = state.playing;
      _isLoading = state.processingState == ProcessingState.buffering ||
          state.processingState == ProcessingState.loading;

      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      }
      notifyListeners();
    });

    _supportErrorSub = _playerSupport.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (!_originAudio) return; // inactive side — ignore
        if (_isTransitioning || _handlingPlaybackError) return;
        print('Support playback error: $e');
        unawaited(_onActiveTrackFailed(_currentSupportTrack));
      },
    );
  }

  /// Advance only on a real end-of-track (Nuxt `ended` on the active element).
  void _handleTrackCompleted() {
    if (_isTransitioning) return;

    final ignoreUntil = _ignoreCompletedUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
      return;
    }

    // Unknown / zero duration → never treat as a real end (spurious completed
    // right after a switch used to auto-skip the freshly started track).
    if (_duration <= Duration.zero) return;

    // Still clearly mid-track → stale/spurious completed (e.g. after seek).
    if (_duration - _currentTime > const Duration(milliseconds: 750)) {
      return;
    }

    _consecutiveLoadFailures = 0;
    _nextOrRepeat();
  }

  /// Replace a broken buffer on a specific side (active or inactive). Does not
  /// start playback — callers that need sound must play afterwards.
  Future<void> _replaceFailedSide({
    required Music? failed,
    required bool isOriginSide,
    int attempt = 0,
  }) async {
    if (failed != null) {
      print(
        'Track failed to load/play: ${failed.title} (ID: ${failed.id}) '
        'side=${isOriginSide ? 'origin' : 'support'}',
      );
      if (!isPlaylistMode) {
        try {
          await _supabaseService.updateMusicById(
            failed.id,
            {'is_active': false},
          );
        } catch (e) {
          print('Failed to mark track inactive: $e');
        }
      }
    }

    final exclude = isOriginSide ? _currentSupportTrack : _currentOriginTrack;
    final replacement = await _fetchNextTrack(excludeTrack: exclude);
    if (replacement == null) return;

    if (isOriginSide) {
      _currentOriginTrack = replacement;
      try {
        await _playerPrimary.setUrl(replacement.audio);
        await _playerPrimary.pause();
        await _playerPrimary.seek(Duration.zero);
      } catch (e) {
        print('Replacement origin preload failed: $e');
        if (attempt < 3) {
          await _replaceFailedSide(
            failed: replacement,
            isOriginSide: true,
            attempt: attempt + 1,
          );
        }
        return;
      }
    } else {
      _currentSupportTrack = replacement;
      try {
        await _playerSupport.setUrl(replacement.audio);
        await _playerSupport.pause();
        await _playerSupport.seek(Duration.zero);
      } catch (e) {
        print('Replacement support preload failed: $e');
        if (attempt < 3) {
          await _replaceFailedSide(
            failed: replacement,
            isOriginSide: false,
            attempt: attempt + 1,
          );
        }
        return;
      }
    }
    notifyListeners();
  }

  /// Active track cannot play (Nuxt playBetter catch): mark dead, flip to the
  /// already-preloaded next buffer, and auto-play it.
  Future<void> _onActiveTrackFailed(Music? failed) async {
    if (_handlingPlaybackError || _isTransitioning) return;
    if (_consecutiveLoadFailures >= _maxConsecutiveLoadFailures) {
      print('Too many consecutive load failures — stopping auto-skip');
      _isPlaying = false;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _handlingPlaybackError = true;
    _consecutiveLoadFailures++;
    try {
      if (failed != null && !isPlaylistMode) {
        try {
          await _supabaseService.updateMusicById(
            failed.id,
            {'is_active': false},
          );
        } catch (e) {
          print('Failed to mark track inactive: $e');
        }
      }
    } finally {
      // Release before playNextMusic so another dead URL can retry (capped by
      // _consecutiveLoadFailures). Holding the flag across that call swallowed
      // the follow-up skip and left playback paused on the replacement.
      _handlingPlaybackError = false;
    }

    // Flip + play the other buffer (same idea as Nuxt flipping originAudio
    // and re-entering playBetter). playNextMusic also refills the dead side.
    await playNextMusic(fromUser: false);
  }

  /// Starts playback on the active player and waits until it is actually
  /// playing (or errors / times out). just_audio's play() future completes
  /// when playback later *stops*, so we must not await it directly.
  Future<void> _playActiveAndConfirm({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final player = activePlayer;
    final completer = Completer<void>();
    StreamSubscription<PlayerState>? stateSub;
    StreamSubscription<PlaybackEvent>? errorSub;

    void succeed() {
      if (!completer.isCompleted) completer.complete();
    }

    void fail(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
    }

    stateSub = player.playerStateStream.listen((state) {
      if (state.playing &&
          (state.processingState == ProcessingState.ready ||
              state.processingState == ProcessingState.buffering)) {
        succeed();
      }
    });
    errorSub = player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) => fail(e),
    );

    try {
      if (player.playing &&
          (player.processingState == ProcessingState.ready ||
              player.processingState == ProcessingState.buffering)) {
        succeed();
      } else {
        unawaited(player.play().catchError((Object e) {
          fail(e);
        }));
      }
      await completer.future.timeout(timeout);
      _consecutiveLoadFailures = 0;
      _isPlaying = true;
      _isLoading = false;
      notifyListeners();
    } finally {
      await stateSub.cancel();
      await errorSub.cancel();
    }
  }

  Future<void> playMusic() async {
    if (_isPlaying) {
      await pauseAudio();
    } else {
      await resumeAudio();
    }
  }

  Future<void> pauseAudio() async {
    await activePlayer.pause();
    _isPlaying = false;
    notifyListeners();
  }

  /// Hard-stop both players and clear playing state. Used when tearing down
  /// the OS media session (app swiped away / notification dismissed) so
  /// playback and system controls do not linger after the app is closed.
  Future<void> stopAudio() async {
    await Future.wait([
      _playerPrimary.stop(),
      _playerSupport.stop(),
    ]);
    _isPlaying = false;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> resumeAudio() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _playActiveAndConfirm();
    } catch (e) {
      print('resumeAudio failed: $e');
      _isLoading = false;
      notifyListeners();
      await _onActiveTrackFailed(activeTrack);
    }
  }

  void _nextOrRepeat() {
    if (_isRepeat) {
      seek(Duration.zero);
      resumeAudio();
    } else {
      // Auto-advance must never queue a second skip during a transition —
      // that was flipping mid-song right after Next.
      playNextMusic(fromUser: false);
    }
  }

  /// Flip to the already-preloaded buffer (Nuxt `playNextMusic` + `playBetter`).
  ///
  /// [fromUser] true for Next button / media controls — may queue one extra
  /// tap. Automatic `ended`/`completed` never queues, so a double-fire cannot
  /// skip two tracks in a row.
  Future<void> playNextMusic({bool fromUser = true}) async {
    if (_isTransitioning) {
      if (fromUser) _queuedNext = true;
      return;
    }
    _isTransitioning = true;
    // Suppress completed storms from pause / seek(0) / inactive setUrl.
    _ignoreCompletedUntil =
        DateTime.now().add(const Duration(milliseconds: 1500));

    _isLoading = true;
    notifyListeners();

    var playFailed = false;
    try {
      // Finish any in-flight inactive preload before flipping so we never
      // land on a half-replaced buffer.
      final pendingRefill = _refillFuture;
      if (pendingRefill != null) {
        try {
          await pendingRefill;
        } catch (e) {
          print('Pending inactive refill failed: $e');
        }
      }

      // Nuxt pauseAudio(): pause ONLY the active element — not both. Pausing /
      // reloading the inactive side while the new track plays was interrupting
      // playback and triggering another skip mid-song.
      final leaving = activePlayer;
      await leaving.pause();

      final currentTrack = activeTrack;
      if (currentTrack != null) {
        if (_playbackHistory.isEmpty ||
            _playbackHistory.last.id != currentTrack.id) {
          _playbackHistory.add(currentTrack);
          if (_playbackHistory.length > 20) {
            _playbackHistory.removeAt(0);
          }
        }
      }

      // Flip to the preloaded player (already setUrl'd in the background).
      _originAudio = !_originAudio;
      _currentTime = Duration.zero;
      // New track must start at the user's volume (outgoing side may be faded).
      _restoreFullVolume();
      await activePlayer.seek(Duration.zero);
      _duration = activePlayer.duration ?? Duration.zero;
      notifyListeners();

      await _playActiveAndConfirm();
    } catch (e) {
      print('Error playing preloaded track: $e');
      playFailed = true;
      _isLoading = false;
      _isPlaying = false;
      notifyListeners();
    } finally {
      _isTransitioning = false;
    }

    // Background-refill the side we just left (Nuxt watch(originAudio) /
    // getRandomNumber*). Keep it paused — preload only.
    _scheduleInactiveRefill();

    if (_queuedNext) {
      _queuedNext = false;
      unawaited(playNextMusic(fromUser: true));
      return;
    }

    // Bad URL after the flip: mark it dead and auto-play the *next* track
    // (Nuxt playBetter catch → flip → playBetter again).
    if (playFailed) {
      await _onActiveTrackFailed(activeTrack);
    }
  }

  /// Starts a fresh inactive-side preload. Any previous in-flight refill is
  /// ignored when it completes so genre-filter changes win the race.
  void _scheduleInactiveRefill() {
    final generation = ++_refillGeneration;
    final refill = _fetchReplacementForInactivePlayer(generation);
    _refillFuture = refill;
    unawaited(refill.whenComplete(() {
      if (identical(_refillFuture, refill)) {
        _refillFuture = null;
      }
    }));
  }

  Future<void> _fetchReplacementForInactivePlayer(int generation) async {
    final replacement = await _fetchNextTrack(excludeTrack: activeTrack);
    if (generation != _refillGeneration) return;
    if (replacement == null) return;

    // Load into the inactive player only. Never call play() here.
    if (_originAudio) {
      _currentOriginTrack = replacement;
      await _preloadPrimary();
    } else {
      _currentSupportTrack = replacement;
      await _preloadSupport();
    }
    if (generation != _refillGeneration) return;
    notifyListeners();
  }

  Future<void> playPreviousMusic() async {
    // If current song has played for more than 3 seconds, restart it (matching Nuxt logic)
    if (_currentTime.inSeconds > 3) {
      seek(Duration.zero);
      return;
    }

    if (_playbackHistory.isEmpty) {
      seek(Duration.zero);
      return;
    }

    _isLoading = true;
    notifyListeners();

    // Pause active player
    await activePlayer.pause();
    await activePlayer.seek(Duration.zero);

    // Retrieve previous track from history
    final prevTrack = _playbackHistory.removeLast();

    if (_originAudio) {
      _currentSupportTrack = prevTrack;
      await _preloadSupport();
    } else {
      _currentOriginTrack = prevTrack;
      await _preloadPrimary();
    }

    _currentTime = Duration.zero;
    _duration = Duration.zero;
    _restoreFullVolume();
    notifyListeners();

    try {
      await _playActiveAndConfirm();
    } catch (e) {
      print('playPreviousMusic failed: $e');
      _isLoading = false;
      notifyListeners();
      await _onActiveTrackFailed(activeTrack);
    }
  }

  void seek(Duration position) {
    // Only the active player — seeking the inactive (often shorter) buffer to
    // the same time can push it to `ended`/`completed` and skip the track.
    var target = position.isNegative ? Duration.zero : position;

    // Keep a small gap from the true end so dragging the slider to max does
    // not fire ProcessingState.completed and jump to the next track.
    if (_duration > const Duration(milliseconds: 500)) {
      final maxPos = _duration - const Duration(milliseconds: 300);
      if (target > maxPos) target = maxPos;
    }

    _ignoreCompletedUntil =
        DateTime.now().add(const Duration(milliseconds: 600));
    _currentTime = target;
    // Force a volume re-apply (seek may leave or enter the fade window).
    _lastAppliedPlayerVolume = -1;
    _applyFadeOutVolume(target);
    notifyListeners();
    unawaited(activePlayer.seek(target));
  }

  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    // Inactive side stays at full user volume for the next flip; active side
    // keeps any in-progress end-of-track fade relative to the new preference.
    unawaited(inactivePlayer.setVolume(_volume));
    _lastAppliedPlayerVolume = -1;
    _applyFadeOutVolume(_currentTime);
    notifyListeners();
  }

  Future<void> toggleRepeat() async {
    _isRepeat = !_isRepeat;
    notifyListeners();

    // Use the players' native repeat-one mode. This guarantees that reaching
    // the end never advances automatically while repeat is enabled. A manual
    // Next action still switches players/tracks normally.
    final loopMode = _isRepeat ? LoopMode.one : LoopMode.off;
    await Future.wait([
      _playerPrimary.setLoopMode(loopMode),
      _playerSupport.setLoopMode(loopMode),
    ]);
  }

  Future<void> toggleGenre(Genre genre) async {
    // Match the frontend exactly: every genre can independently be enabled or
    // disabled, including turning all filters off (which means "all genres").
    final turningOff = genre.active;
    genre.active = !genre.active;
    notifyListeners();

    // Persist the same `myGenres` array used by the mobile web version.
    final prefs = await SharedPreferences.getInstance();
    final genresJson = jsonEncode(_genres.map((g) => g.toJson()).toList());
    await prefs.setString('myGenres', genresJson);

    // The inactive player already holds the next track. If this genre was
    // turned off, that buffer may still be from the disabled genre — refetch
    // with the updated filters so Next respects the change.
    if (turningOff && !isPlaylistMode) {
      _scheduleInactiveRefill();
    }
  }

  @override
  void dispose() {
    _primaryPositionSub?.cancel();
    _primaryDurationSub?.cancel();
    _primaryStateSub?.cancel();
    _primaryErrorSub?.cancel();
    _supportPositionSub?.cancel();
    _supportDurationSub?.cancel();
    _supportStateSub?.cancel();
    _supportErrorSub?.cancel();
    
    _playerPrimary.dispose();
    _playerSupport.dispose();
    super.dispose();
  }
}
