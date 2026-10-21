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
import '../models/live_station.dart';
import 'supabase_service.dart';
import 'live_service.dart';

/// Severity the service wants the UI to show, mirroring the Nuxt
/// `toast.info / success / warning / error` variants.
enum ServiceToastKind { info, success, warning, error }

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
  // NOTE: the web's Nuxt `letsGoModal` ("Let's GO" intro gate) is deliberately
  // NOT ported. It exists only because browsers refuse to start audio without a
  // user gesture; a native app has no such restriction, so playback starts by
  // itself as soon as the first buffer is hot.
  /// Nuxt `desiredMode === 'live'` — what the user *asked* for, which is not
  /// necessarily what is playing yet ([_isLiveMode] is the actual mode).
  bool _wantLive = false;
  double _volume = 1.0; // 0.0 to 1.0
  /// Last volume written to the active player (may be faded below [_volume]).
  double _lastAppliedPlayerVolume = 1.0;
  /// Fade the active track to silence over this window before it ends.
  static const Duration _fadeOutDuration = Duration(seconds: 4);
  /// How long position may stall while we expect playback before auto-skip.
  static const Duration _stuckTimeout = Duration(seconds: 11);
  /// Max wait for inactive preload / API before Next proceeds or recovers.
  static const Duration _refillWaitTimeout = Duration(seconds: 8);
  static const Duration _setUrlTimeout = Duration(seconds: 12);
  /// Cover spinner stuck longer than this → force skip to next track.
  static const Duration _loadingStuckTimeout = Duration(seconds: 13);
  /// Prevents stacked error→skip handlers from fighting over the dual players.
  bool _handlingPlaybackError = false;
  /// Caps auto-skip storms when several bad URLs land in a row.
  int _consecutiveLoadFailures = 0;
  static const int _maxConsecutiveLoadFailures = 8;
  /// True while radio should keep producing audio (not user-paused / stopped).
  bool _expectingPlayback = false;
  /// When cover loading started (for stuck-loading recovery).
  DateTime? _loadingSince;
  /// Soft pull-to-refresh already in flight (ignore extra swipes).
  bool _softRefreshInFlight = false;
  /// Bumped on each loading-stuck recovery so a hung playNext cannot block
  /// the next 13s watchdog fire (the old bool reentrancy lock did that).
  int _loadingRecoveryGeneration = 0;
  /// Last position that counted as real progress (for stuck detection).
  Duration _lastProgressPosition = Duration.zero;
  /// When position last advanced while we expected playback.
  DateTime? _lastProgressAt;
  Timer? _stuckWatchTimer;

  Duration _currentTime = Duration.zero;
  Duration _duration = Duration.zero;

  final List<Music> _playbackHistory = [];
  List<Genre> _genres = [];

  // Playlist-as-radio-source mode (matches Nuxt activePlaybackPlaylist)
  Playlist? _activePlaybackPlaylist;
  List<Music> _activePlaylistTracks = [];

  // Live radio mode (matches Nuxt useLiveRadio + PlayerMain live branch).
  // Plays the shared `live-music` station on the primary player and keeps every
  // client (web + this app) in sync by seeking to the station's elapsed time.
  final LiveService _liveService = LiveService();
  bool _isLiveMode = false;
  bool _liveBusy = false;
  bool _liveAdvanceBusy = false;
  /// Nuxt `liveAdvanceQueued` — an advance arrived while one was already in
  /// flight. Dropping it used to leave the station stuck at the end of a track.
  bool _liveAdvanceQueued = false;
  /// Nuxt `liveFailCount` — a local load failure re-syncs the station once and
  /// only takes over (skipping for *every* listener) on the second failure.
  int _liveFailCount = 0;
  /// Nuxt `lastLoadingSkipAt` + `LOADING_SKIP_DEBOUNCE_MS` (400 ms).
  DateTime? _lastLoadingSkipAt;
  static const Duration _loadingSkipDebounce = Duration(milliseconds: 400);
  String _lastAppliedLiveIdentity = '';
  String _liveLoadedAudio = ''; // audio url currently loaded on primary
  LiveStation? _liveStation;
  VoidCallback? _liveSubscriptionCancel;
  Timer? _liveResyncTimer;
  // Last time we claimed/published a new station track — throttles back-to-back
  // advances so a burst of events can't skip through many songs at once.
  DateTime? _lastLiveAdvanceAt;
  static const Duration _liveClaimThrottle = Duration(seconds: 6);

  /// Native-only circuit breaker. The web has no local timer, so a browser tab
  /// can only advance the station on an `ended` event or a poll; this app also
  /// has a 2 s resync tick plus OEM audio-focus noise, and every one of those
  /// paths can *claim* a track for all listeners. Without a cap a single phone
  /// (bad CDN, wrong clock, dead row) rewrote the shared station endlessly — the
  /// "changes music in a bad loop" crash. Counts claims that never reached
  /// audible playback; the cap blocks further writes until the user acts.
  int _liveClaimsInRow = 0;
  bool _liveStationBlocked = false;
  static const int _maxLiveClaimsWithoutPlayback = 3;
  /// Rate-limits the "station never loaded, keep trying" recovery in the tick.
  DateTime? _lastLiveStationRetryAt;

  /// Boot autoplay retry. With the intro gate gone nothing taps "play" if the
  /// first fetch came back empty (cold DNS / no network yet on app open), so the
  /// radio keeps retrying on a gentle timer for about a minute.
  Timer? _bootAutoplayTimer;
  int _bootAutoplayAttempts = 0;
  static const int _maxBootAutoplayAttempts = 6;

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

  /// Requested mode (Nuxt `wantLive`) — drives the header LIVE / GO LIVE label.
  bool get wantLive => _wantLive;

  /// True while radio should keep producing audio (not user-paused / stopped).
  /// Used by the OS media session so lock-screen / Doze does not freeze the
  /// isolate during the gap between tracks (setUrl / RPC / dual-player flip).
  bool get expectingPlayback => _expectingPlayback;

  /// Report "playing" to Android even while buffering the next track so the
  /// foreground service wake-lock stays held with the screen locked.
  bool get mediaSessionPlaying =>
      _expectingPlayback || _isPlaying || _isTransitioning;

  Duration get currentTime => _currentTime;
  Duration get duration => _duration;

  List<Genre> get genres => _genres;
  List<String> get activeGenreFilters =>
      _genres.where((g) => g.active).map((g) => g.genre).toList();

  Playlist? get activePlaybackPlaylist => _activePlaybackPlaylist;
  bool get isPlaylistMode => _activePlaybackPlaylist != null;

  // Live radio getters
  bool get isLiveMode => _isLiveMode;
  bool get isLiveBusy => _liveBusy;

  /// Nuxt `modeBusy` — a mode switch is in flight, LIVE toggle is disabled.
  bool get modeBusy => _liveBusy;

  /// UI hook so the service can raise the exact same toasts the web raises
  /// from inside its own functions (`enterLiveMode`, `playMusic`, …) instead of
  /// guessing from a button handler. A LIVE request made during the intro is
  /// deferred, so the tap that set it off is long gone by the time the mode
  /// actually changes.
  void Function(String message, String title, ServiceToastKind kind)? onToast;

  void _emitToast(
    String message,
    String title, [
    ServiceToastKind kind = ServiceToastKind.info,
  ]) {
    final cb = onToast;
    if (cb != null) cb(message, title, kind);
  }

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

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  /// After a transient focus loss (call / OEM quirk), resume if we still want audio.
  bool _resumeAfterInterruption = false;
  /// Debounce OEM lock-screen pause→play storms.
  DateTime? _lastUnexpectedResumeAt;

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    // Register as a native music session. This requests the correct Android
    // audio focus and lets playback continue naturally while the app is in the
    // background or the device is locked.
    await _configureAudioSession();

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

    // Fetch + preload until the first track can start instantly, then play right
    // away: the app starts on air. The web has to wait for the "Let's GO" tap
    // because of the browser autoplay policy — that restriction does not exist
    // here, and Android happily attaches the media session to the first play().
    await _loadInitialTracks();
    await playMusic();
    _armBootAutoplayRetry();
  }

  /// Retries the boot playback until something is actually on air. Cancelled as
  /// soon as audio starts, the user pauses on purpose, or another source (live
  /// station / playlist) takes the players.
  void _armBootAutoplayRetry() {
    _cancelBootAutoplayRetry();
    if (_isPlaying) return;
    _bootAutoplayAttempts = 0;
    late final Timer timer;
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_bootAutoplayTick(timer));
    });
    _bootAutoplayTimer = timer;
  }

  void _cancelBootAutoplayRetry() {
    _bootAutoplayTimer?.cancel();
    _bootAutoplayTimer = null;
  }

  Future<void> _bootAutoplayTick(Timer timer) async {
    if (_isPlaying ||
        _isLiveMode ||
        _activePlaybackPlaylist != null ||
        _bootAutoplayAttempts >= _maxBootAutoplayAttempts) {
      timer.cancel();
      if (identical(_bootAutoplayTimer, timer)) _bootAutoplayTimer = null;
      return;
    }
    _bootAutoplayAttempts++;
    print('Boot autoplay retry #$_bootAutoplayAttempts');

    final track = activeTrack;
    if (track == null || track.audio.isEmpty) {
      await _loadInitialTracks();
    }
    if (!_isPlaying && !_isLiveMode && _activePlaybackPlaylist == null) {
      await playMusic();
    }
  }

  /// Nuxt login page (`skipLetsGo` + `autoPlayAfterLogin` → `playMusic()`):
  /// a successful sign-in starts the radio when nothing is playing. Native has no
  /// intro gate, so this is just "make sure something is audible".
  Future<void> startIfSilent() async {
    if (_isPlaying) return;
    await playMusic();
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    // Start from the music preset, but never auto-pause when ducked — some
    // OEMs briefly duck/steal focus when the screen turns off.
    await session.configure(
      AudioSessionConfiguration.music().copyWith(
        androidWillPauseWhenDucked: false,
      ),
    );

    await _interruptionSub?.cancel();
    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // Do NOT pause ourselves here. Some OEMs fire a fake "pause"
        // interruption when the screen locks; pausing would kill radio until
        // unlock. Real phone-call focus loss is handled by the platform and
        // we resume when the interruption ends (or via unexpected-pause recover).
        if (event.type == AudioInterruptionType.pause ||
            event.type == AudioInterruptionType.unknown) {
          _resumeAfterInterruption = _expectingPlayback || _isPlaying;
        }
      } else {
        final shouldResume =
            _resumeAfterInterruption || _expectingPlayback;
        _resumeAfterInterruption = false;
        if (shouldResume && (_expectingPlayback || _hasStarted)) {
          unawaited(resumeAudio());
        }
      }
    });

    await _becomingNoisySub?.cancel();
    _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
      // Headphones unplugged — pause like a native music app.
      unawaited(pauseAudio());
    });

    await session.setActive(true);
  }

  Future<void> _ensureAudioSessionActive() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
    } catch (e) {
      print('Audio session activate failed: $e');
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
    if (activeTrack == null || activeTrack!.audio.isEmpty) {
      // Nuxt playMusic(): toast.warning('No music available', { title: 'Player' })
      _markNotLoading();
      _emitToast('No music available', 'Player', ServiceToastKind.warning);
      return;
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

      try {
        await _waitUntilPlayableInstantly(_playerPrimary);
      } catch (e) {
        print('Intro buffer wait failed: $e');
      }

      // Origin buffer is hot enough to start without a stall.
      _isLoading = false;
      _isAudioReady = _playerPrimary.processingState == ProcessingState.ready ||
          _isHotEnoughToPlay(_playerPrimary);
      notifyListeners();
    } catch (e) {
      print('Error loading initial tracks: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Enter playlist-as-source mode (or exit if same playlist is toggled).
  Future<void> playFromPlaylist(Playlist playlist, List<Music> tracks) async {
    // Nuxt `playFromPlaylist()` drops live *inline*: no station re-load and no
    // "back to shuffle" toast, because the playlist is about to own the players
    // anyway. Going through exitLiveMode() here would fetch a random pair of
    // tracks, start them, then immediately throw them away.
    if (_isLiveMode) {
      _isLiveMode = false;
      _wantLive = false;
      _stopLiveSync();
      _liveStation = null;
      _liveLoadedAudio = '';
      _lastAppliedLiveIdentity = '';
    }

    final playable = tracks.where((t) => t.audio.isNotEmpty).toList();
    if (playable.isEmpty) {
      throw Exception('Empty playlist');
    }

    _activePlaybackPlaylist = playlist;
    _activePlaylistTracks = playable;
    _originAudio = false;
    _cancelBootAutoplayRetry();
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
        await _playerPrimary
            .setUrl(_currentOriginTrack!.audio)
            .timeout(_setUrlTimeout);
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
        await _playerSupport
            .setUrl(_currentSupportTrack!.audio)
            .timeout(_setUrlTimeout);
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

  static const Duration _introMinBuffer = Duration(seconds: 6);
  static const Duration _introWaitTimeout = Duration(seconds: 25);

  bool _isHotEnoughToPlay(AudioPlayer player) {
    final buffered = player.bufferedPosition;
    final duration = player.duration;
    if (duration != null &&
        duration > Duration.zero &&
        buffered >= duration - const Duration(milliseconds: 200)) {
      return true;
    }
    return buffered >= _introMinBuffer;
  }

  /// Hold the boot overlay until the origin player has a real startable buffer
  /// (same idea as the Nuxt intro wait — not just "metadata loaded").
  Future<void> _waitUntilPlayableInstantly(AudioPlayer player) async {
    if (_isHotEnoughToPlay(player)) return;

    final done = Completer<void>();
    var lastBuffered = player.bufferedPosition;
    var lastChange = DateTime.now();

    void consider() {
      if (done.isCompleted) return;
      final buffered = player.bufferedPosition;
      if (buffered != lastBuffered) {
        lastBuffered = buffered;
        lastChange = DateTime.now();
      }
      if (_isHotEnoughToPlay(player)) {
        done.complete();
        return;
      }
      final stalled =
          DateTime.now().difference(lastChange) >= const Duration(milliseconds: 1500);
      if (stalled &&
          player.processingState == ProcessingState.ready &&
          buffered >= const Duration(seconds: 2)) {
        done.complete();
      }
    }

    final subs = <StreamSubscription<dynamic>>[
      player.bufferedPositionStream.listen((_) => consider()),
      player.playerStateStream.listen((_) => consider()),
    ];
    final poll = Timer.periodic(const Duration(milliseconds: 250), (_) => consider());
    final timeout = Timer(_introWaitTimeout, () {
      if (done.isCompleted) return;
      if (player.processingState == ProcessingState.ready &&
          player.bufferedPosition >= const Duration(seconds: 2)) {
        done.complete();
      } else {
        done.completeError(TimeoutException('intro buffer wait'));
      }
    });

    try {
      await done.future;
    } finally {
      poll.cancel();
      timeout.cancel();
      for (final sub in subs) {
        unawaited(sub.cancel());
      }
    }
  }

  /// Ramp active-player volume to 0 over the last [_fadeOutDuration].
  /// Keeps user preference in [_volume] so the slider / next track stay correct.
  void _applyFadeOutVolume(Duration position) {
    var factor = 1.0;
    // No end-of-track fade in live mode — the station advances on its own.
    if (!_isTransitioning && !_isLiveMode && _duration > Duration.zero) {
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
        _notePlaybackProgress(pos);
        _applyFadeOutVolume(pos);
        _clearLoadingIfAudible();
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
      _syncLoadingFromPlayerState(state);

      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      } else {
        _recoverUnexpectedPause(state);
      }
      notifyListeners();
    });

    // Async load/play failures never reach the unawaited play() caller.
    // Do NOT skip immediately — wait for the 11s stuck watchdog so a transient
    // glitch mid-song cannot jump tracks.
    _primaryErrorSub = _playerPrimary.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (_originAudio) return; // inactive side — ignore
        if (_isTransitioning || _handlingPlaybackError) return;
        print('Primary playback error (waiting for stuck timeout): $e');
        _onActivePlaybackGlitch();
      },
    );

    // Support Player Listeners
    _supportPositionSub = _playerSupport.positionStream.listen((pos) {
      if (_originAudio) {
        _currentTime = pos;
        _notePlaybackProgress(pos);
        _applyFadeOutVolume(pos);
        _clearLoadingIfAudible();
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
      _syncLoadingFromPlayerState(state);

      if (state.processingState == ProcessingState.completed) {
        _handleTrackCompleted();
      } else {
        _recoverUnexpectedPause(state);
      }
      notifyListeners();
    });

    _supportErrorSub = _playerSupport.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        if (!_originAudio) return; // inactive side — ignore
        if (_isTransitioning || _handlingPlaybackError) return;
        print('Support playback error (waiting for stuck timeout): $e');
        _onActivePlaybackGlitch();
      },
    );
  }

  /// Cover spinner: stay visible until the active track is actually playing
  /// and ready (or the playhead has moved). Once audible, brief rebuffers
  /// must not flash the spinner again.
  void _syncLoadingFromPlayerState(PlayerState state) {
    final hasAudibleProgress =
        state.playing && _currentTime > const Duration(milliseconds: 80);
    final isAudiblyStarted = state.playing &&
        (state.processingState == ProcessingState.ready || hasAudibleProgress);

    if (_expectingPlayback && !isAudiblyStarted) {
      _markLoading();
      return;
    }

    // Already started (or not expecting play) — never flash on mid-song rebuffer.
    _markNotLoading();
  }

  void _markLoading() {
    // New loading episode → restart the 13s clock (do not keep an old stamp).
    if (!_isLoading || _loadingSince == null) {
      _loadingSince = DateTime.now();
    }
    _isLoading = true;
    _ensureStuckWatch();
  }

  void _markNotLoading() {
    _isLoading = false;
    _loadingSince = null;
  }

  void _clearLoadingIfAudible() {
    if (!_isLoading || !_expectingPlayback) return;
    if (activePlayer.playing &&
        _currentTime > const Duration(milliseconds: 80)) {
      _markNotLoading();
    }
  }

  /// Whether the inactive buffer looks safe to flip onto.
  bool _inactiveBufferLooksReady() {
    final track = _originAudio ? _currentOriginTrack : _currentSupportTrack;
    if (track == null || track.audio.isEmpty) return false;
    final state = inactivePlayer.processingState;
    return state == ProcessingState.ready ||
        state == ProcessingState.buffering ||
        state == ProcessingState.completed ||
        (inactivePlayer.duration != null &&
            inactivePlayer.duration! > Duration.zero);
  }

  /// Wait briefly for an in-flight refill; if it hangs, invalidate and force
  /// a fresh inactive preload so Next cannot freeze forever on loading.
  Future<void> _ensureInactiveReadyForFlip() async {
    final pending = _refillFuture;
    if (pending != null) {
      try {
        await pending.timeout(_refillWaitTimeout);
      } on TimeoutException {
        print('Inactive refill timed out — forcing a fresh preload');
        _refillGeneration++;
        _refillFuture = null;
      } catch (e) {
        print('Pending inactive refill failed: $e');
        _refillGeneration++;
        _refillFuture = null;
      }
    }

    if (_inactiveBufferLooksReady()) return;

    print('Inactive buffer not ready — loading a track before flip');
    try {
      final replacement = await _fetchNextTrack(excludeTrack: activeTrack)
          .timeout(_refillWaitTimeout);
      if (replacement == null) return;

      if (_originAudio) {
        _currentOriginTrack = replacement;
        await _preloadPrimary();
      } else {
        _currentSupportTrack = replacement;
        await _preloadSupport();
      }
    } on TimeoutException {
      print('Forced inactive preload timed out');
    } catch (e) {
      print('Forced inactive preload failed: $e');
    }
  }

  /// Record that the playhead moved forward (resets the stuck clock).
  void _notePlaybackProgress(Duration pos) {
    if (!_expectingPlayback) return;
    if (pos > _lastProgressPosition + const Duration(milliseconds: 150)) {
      _lastProgressPosition = pos;
      _lastProgressAt = DateTime.now();
    }
  }

  /// Soft error while a track should be playing — try resume once, then let the
  /// 11s stuck watchdog decide whether to skip.
  void _onActivePlaybackGlitch() {
    if (!_expectingPlayback || _isTransitioning) return;
    // Ensure the stuck clock is running from the last real progress.
    _lastProgressAt ??= DateTime.now();
    _ensureStuckWatch();
    // Best-effort recover without flipping tracks.
    unawaited(activePlayer.play().catchError((Object _) {}));
  }

  /// Some OEMs pause ExoPlayer when the screen locks even though the user did
  /// not tap pause. If we still want radio, kick playback again immediately.
  void _recoverUnexpectedPause(PlayerState state) {
    if (!_expectingPlayback || _isTransitioning || _handlingPlaybackError) {
      return;
    }
    if (_resumeAfterInterruption) return; // phone-call path owns resume
    if (state.playing) return;
    if (state.processingState != ProcessingState.ready &&
        state.processingState != ProcessingState.buffering) {
      return;
    }
    final now = DateTime.now();
    final last = _lastUnexpectedResumeAt;
    if (last != null && now.difference(last) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastUnexpectedResumeAt = now;
    unawaited(_ensureAudioSessionActive());
    unawaited(activePlayer.play().catchError((Object _) {}));
  }

  void _armStuckWatch() {
    _lastProgressPosition = _currentTime;
    _lastProgressAt = DateTime.now();
    _ensureStuckWatch();
  }

  void _ensureStuckWatch() {
    _stuckWatchTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkStuckPlayback(),
    );
  }

  void _disarmStuckWatch() {
    _stuckWatchTimer?.cancel();
    _stuckWatchTimer = null;
    _lastProgressAt = null;
    _lastProgressPosition = Duration.zero;
  }

  void _checkStuckPlayback() {
    // Loading > 13s → always force next, even mid-transition. A hung
    // playNext/refill used to keep the cover spinner forever.
    if (_expectingPlayback && _isLoading) {
      _loadingSince ??= DateTime.now();
      final since = _loadingSince!;
      if (DateTime.now().difference(since) >= _loadingStuckTimeout) {
        print(
          'Cover loading stuck for ${_loadingStuckTimeout.inSeconds}s — forcing next',
        );
        unawaited(_recoverFromStuckLoading());
        return;
      }
    }

    if (!_expectingPlayback || _isTransitioning || _handlingPlaybackError) {
      return;
    }
    final last = _lastProgressAt;
    if (last == null) return;
    if (DateTime.now().difference(last) < _stuckTimeout) return;

    print(
      'Active track stuck for ${_stuckTimeout.inSeconds}s '
      'at ${_currentTime.inMilliseconds}ms — skipping',
    );
    unawaited(_onActiveTrackFailed(activeTrack));
  }

  /// Break a frozen Next/refresh: drop hung refill, clear locks, skip now.
  Future<void> _recoverFromStuckLoading() async {
    final generation = ++_loadingRecoveryGeneration;

    // Blow past any stuck transition / error lock so Next can run.
    _isTransitioning = false;
    _handlingPlaybackError = false;
    _queuedNext = false;
    _refillGeneration++;
    _refillFuture = null;
    // Fresh 13s window for this recovery attempt (and any later hang).
    _loadingSince = DateTime.now();
    _isLoading = true;
    _ensureStuckWatch();
    notifyListeners();

    print('Forcing next track after loading timeout (gen $generation)');

    try {
      // Call Next directly — _onActiveTrackFailed can no-op when a concurrent
      // transition flips _isTransitioning back on, which left users stuck.
      if (_isLiveMode) {
        // Live can't "skip to the next shuffle track" — recover the station.
        await _recoverLiveFailure();
      } else {
        await playNextMusic(fromUser: false);
      }
    } catch (e) {
      print('Loading-stuck recovery failed: $e');
      if (identical(generation, _loadingRecoveryGeneration) ||
          generation == _loadingRecoveryGeneration) {
        // Keep spinner + clock so the watchdog can fire again in 13s.
        _markLoading();
        _loadingSince = DateTime.now();
      }
    }
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
      if (!isPlaylistMode && !_isLiveMode) {
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
        await _playerPrimary.setUrl(replacement.audio).timeout(_setUrlTimeout);
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
        await _playerSupport.setUrl(replacement.audio).timeout(_setUrlTimeout);
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
    // Live mode owns a different recovery path — the shared station belongs to
    // every listener, so re-sync it before ever taking it over.
    if (_isLiveMode) {
      await _recoverLiveFailure();
      return;
    }
    if (_consecutiveLoadFailures >= _maxConsecutiveLoadFailures) {
      print('Too many consecutive load failures — stopping auto-skip');
      _expectingPlayback = false;
      _disarmStuckWatch();
      _isPlaying = false;
      _markNotLoading();
      notifyListeners();
      return;
    }

    _handlingPlaybackError = true;
    _consecutiveLoadFailures++;
    // Reset stuck clock so the replacement track gets a fresh 11s window.
    _disarmStuckWatch();
    try {
      if (failed != null && !isPlaylistMode && !_isLiveMode) {
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

  /// Starts playback on the active player and waits until audio is actually
  /// ready (or position advances). just_audio's play() future completes when
  /// playback later *stops*, so we must not await it directly.
  ///
  /// Important: do NOT treat `playing + buffering` as success — that cleared
  /// the loading spinner before any samples were audible.
  Future<void> _playActiveAndConfirm({
    Duration timeout = const Duration(seconds: 11),
  }) async {
    final player = activePlayer;
    final completer = Completer<void>();
    StreamSubscription<PlayerState>? stateSub;
    StreamSubscription<Duration>? positionSub;
    StreamSubscription<PlaybackEvent>? errorSub;

    void succeed() {
      if (!completer.isCompleted) completer.complete();
    }

    void fail(Object error) {
      if (!completer.isCompleted) completer.completeError(error);
    }

    bool isAudible(PlayerState state) =>
        state.playing && state.processingState == ProcessingState.ready;

    stateSub = player.playerStateStream.listen((state) {
      if (isAudible(state)) succeed();
    });
    // Some devices briefly report buffering even after samples start — treat
    // a moving playhead as confirmation that sound is out.
    positionSub = player.positionStream.listen((pos) {
      if (player.playing && pos > const Duration(milliseconds: 80)) {
        succeed();
      }
    });
    errorSub = player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) => fail(e),
    );

    try {
      if (isAudible(player.playerState) ||
          (player.playing &&
              player.position > const Duration(milliseconds: 80))) {
        succeed();
      } else {
        unawaited(player.play().catchError((Object e) {
          fail(e);
        }));
      }
      await completer.future.timeout(timeout);
      _consecutiveLoadFailures = 0;
      _isPlaying = true;
      _markNotLoading();
      _expectingPlayback = true;
      _armStuckWatch();
      notifyListeners();
    } finally {
      await stateSub.cancel();
      await positionSub.cancel();
      await errorSub.cancel();
    }
  }

  /// Nuxt `playMusic()` — toggles audio. Native has no intro gate, so the first
  /// call comes from `initialize()` (autoplay on boot); later calls are the cover
  /// tap (pause / resume).
  Future<void> playMusic() async {
    if (_isPlaying) {
      await pauseAudio();
      return;
    }

    // A LIVE request made while the gate was up is honoured now — Nuxt
    // `else if (wantLive.value) await enterLiveMode()`.
    if (_wantLive && !_isLiveMode) {
      await _applyDesiredMode();
      return;
    }

    if (!_hasStarted) {
      await startPlayback();
      return;
    }

    await resumeAudio();
  }

  // ---------------------------------------------------------------------------
  // Desired vs actual playback mode (Nuxt usePlaybackMode + watch(desiredMode))
  // ---------------------------------------------------------------------------

  /// Nuxt `requestLive()` — ask for the shared live station. Deferred (but
  /// remembered) while the Let's GO gate is still on screen.
  void requestLive() => _requestMode(true);

  /// Nuxt `requestRandom()` — ask to go back to the shuffle radio.
  void requestRandom() => _requestMode(false);

  void _requestMode(bool live) {
    if (_wantLive == live) return;
    _wantLive = live;
    notifyListeners();
    unawaited(_applyDesiredMode());
  }

  Future<void> _applyDesiredMode() async {
    // enterLiveMode / exitLiveMode guard against a no-op switch themselves.
    if (_liveBusy) return;
    if (_wantLive && _isLiveMode) return;
    if (!_wantLive && !_isLiveMode) return;

    try {
      if (_wantLive) {
        await enterLiveMode();
      } else {
        await exitLiveMode();
      }
    } catch (e) {
      print('Playback mode switch failed: $e');
      _emitToast('Could not switch radio mode.', 'Radio', ServiceToastKind.error);
      // Snap the requested mode back to what is actually playing.
      _wantLive = _isLiveMode;
      notifyListeners();
    }
  }

  /// Kept for callers that just want "flip it": now routes through the
  /// desired-mode state machine so the label / deferral rules stay identical.
  Future<void> toggleLiveMode() async {
    if (_liveBusy) return;
    _requestMode(!_wantLive);
  }

  Future<void> pauseAudio() async {
    _resumeAfterInterruption = false;
    _expectingPlayback = false;
    _disarmStuckWatch();
    // A deliberate pause ends the boot autoplay retry — the listener is in charge
    // from here on.
    _cancelBootAutoplayRetry();
    // Nuxt `pauseAudio()` pauses BOTH elements. Pausing only the active one can
    // leave a preloaded / mid-crossfade support buffer audible underneath, and in
    // live mode it is the station that has to go completely quiet.
    try {
      await Future.wait([
        _playerPrimary.pause(),
        _playerSupport.pause(),
      ]);
    } catch (e) {
      print('pauseAudio failed: $e');
    }
    _isPlaying = false;
    notifyListeners();
  }

  /// Hard-stop both players and clear playing state. Used when tearing down
  /// the OS media session (app swiped away / notification dismissed) so
  /// playback and system controls do not linger after the app is closed.
  Future<void> stopAudio() async {
    _resumeAfterInterruption = false;
    _expectingPlayback = false;
    _disarmStuckWatch();
    await Future.wait([
      _playerPrimary.stop(),
      _playerSupport.stop(),
    ]);
    _isPlaying = false;
    _markNotLoading();
    notifyListeners();
  }

  Future<void> resumeAudio() async {
    // In live mode "resume" means get back onto the shared station at the
    // correct elapsed position, not resume the local shuffle buffer.
    if (_isLiveMode) {
      await _playLiveStation(fromUser: true);
      return;
    }

    _resumeAfterInterruption = false;
    // Any path that puts sound out counts as "started", including a lock-screen
    // play that arrives before the Let's GO gate has been tapped.
    _hasStarted = true;
    // Intro already waited for a hot buffer — don't flash the
    // cover spinner on the first play().
    if (!_isHotEnoughToPlay(activePlayer)) {
      _markLoading();
    }
    _expectingPlayback = true;
    notifyListeners();

    try {
      await _ensureAudioSessionActive();
      await _playActiveAndConfirm();
    } catch (e) {
      print('resumeAudio failed: $e');
      _markNotLoading();
      notifyListeners();
      await _onActiveTrackFailed(activeTrack);
    }
  }

  void _nextOrRepeat() {
    // Nuxt `nextOrRepeat()`: in live mode the only way forward is to move the
    // shared station on — nobody gets to skip privately.
    if (_isLiveMode) {
      unawaited(_advanceLiveStation(force: true));
      return;
    }
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
    // Nuxt `playNextMusic()` returns immediately in live mode: the Next button
    // is hidden and the station is owned by whoever claimed it. Only the
    // end-of-track path (`_nextOrRepeat`) may advance the shared station.
    if (_isLiveMode) return;

    if (_isTransitioning) {
      if (fromUser) _queuedNext = true;
      return;
    }

    final recoveryGenAtStart = _loadingRecoveryGeneration;

    _markLoading();
    _expectingPlayback = true;
    // Keep the stuck/loading watchdog armed — a hung network refill used to
    // disarm it and freeze the cover spinner forever.
    notifyListeners();

    // Resolve inactive buffer BEFORE taking the transition lock so a slow API
    // cannot block every subsequent Next tap / auto-advance.
    await _ensureInactiveReadyForFlip();

    // A 13s loading recovery may have started a newer Next while we waited.
    if (recoveryGenAtStart != _loadingRecoveryGeneration) {
      return;
    }

    if (_isTransitioning) {
      if (fromUser) _queuedNext = true;
      return;
    }

    _isTransitioning = true;
    // Suppress completed storms from pause / seek(0) / inactive setUrl.
    _ignoreCompletedUntil =
        DateTime.now().add(const Duration(milliseconds: 1500));

    await _ensureAudioSessionActive();

    var playFailed = false;
    try {
      // Nuxt pauseAudio(): pause ONLY the active element — not both.
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
      _isPlaying = false;
      // Keep spinner up — recovery path below will clear it on success.
      _markLoading();
      notifyListeners();
    } finally {
      _isTransitioning = false;
    }

    // Background-refill the side we just left. Keep it paused — preload only.
    _scheduleInactiveRefill();

    if (_queuedNext) {
      _queuedNext = false;
      unawaited(playNextMusic(fromUser: true));
      return;
    }

    // Bad URL after the flip: mark it dead and auto-play the *next* track.
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
    try {
      final replacement = await _fetchNextTrack(excludeTrack: activeTrack)
          .timeout(_refillWaitTimeout);
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
    } on TimeoutException {
      print('Inactive refill API/preload timed out (gen=$generation)');
    } catch (e) {
      print('Inactive refill failed: $e');
    }
  }

  /// Nuxt `forcePlayNextAfterLoadFailure()` live branch: retry the station once
  /// (`playLiveStation`), and only claim a new track on the second consecutive
  /// failure so one bad buffer on this device cannot skip the whole audience.
  Future<void> _recoverLiveFailure() async {
    // Already given up? Stay quiet until the user does something — this is what
    // stops a failing CDN / dead station row from turning into an endless claim
    // loop that rewrites the station for every listener.
    if (_liveStationBlocked) {
      print('Live station is blocked after repeated failures — not claiming');
      _markNotLoading();
      notifyListeners();
      return;
    }

    // Nuxt debounces duplicate skips (LOADING_SKIP_DEBOUNCE_MS) so two racing
    // watchers can't both move.
    final skipNow = DateTime.now();
    final lastSkip = _lastLoadingSkipAt;
    if (lastSkip != null &&
        skipNow.difference(lastSkip) < _loadingSkipDebounce) {
      return;
    }
    _lastLoadingSkipAt = skipNow;

    _liveFailCount++;
    if (_liveFailCount < 2) {
      print('Live track failed to load — retrying station');
      await _playLiveStation();
      return;
    }
    _liveFailCount = 0;
    await _advanceLiveStation(force: true);
  }

  /// Nuxt `playPreviousMusic()`: restart the current track if we are more than
  /// three seconds in, otherwise walk the playback history backwards. Live
  /// mode ignores it entirely (the station clock is not ours to move).
  Future<void> playPreviousMusic() async {
    if (_isLiveMode) return;

    if (_currentTime.inSeconds > 3) {
      seek(Duration.zero);
      await resumeAudio();
      return;
    }

    if (_playbackHistory.isEmpty) {
      seek(Duration.zero);
      await resumeAudio();
      return;
    }

    final previous = _playbackHistory.removeLast();
    _queuedNext = false;
    _originAudio = false;
    _currentOriginTrack = previous;
    _isTransitioning = true;
    _ignoreCompletedUntil =
        DateTime.now().add(const Duration(milliseconds: 1500));
    try {
      await _playerPrimary.setUrl(previous.audio).timeout(_setUrlTimeout);
      _currentSupportTrack = _currentSupportTrack?.id == previous.id
          ? null
          : _currentSupportTrack;
      _currentTime = Duration.zero;
      _duration = _playerPrimary.duration ?? Duration.zero;
      _restoreFullVolume();
      notifyListeners();
      await _playActiveAndConfirm();
    } catch (e) {
      print('playPreviousMusic failed: $e');
      await _onActiveTrackFailed(previous);
    } finally {
      _isTransitioning = false;
    }

    if (_currentSupportTrack == null) {
      _scheduleInactiveRefill();
    }
  }

  /// Cold restart (pull-down): same path as opening the app — splash, fresh
  /// dual buffers from the API, then autoplay. Genre prefs are kept.
  Future<void> refreshRadio() async {
    // In live mode a pull-to-refresh just re-syncs the shared station.
    if (_isLiveMode) {
      await _playLiveStation(fromUser: true);
      return;
    }
    if (_softRefreshInFlight) return;
    _softRefreshInFlight = true;

    try {
      _queuedNext = false;
      _refillGeneration++;
      _refillFuture = null;
      _expectingPlayback = false;
      _disarmStuckWatch();
      _handlingPlaybackError = false;
      _loadingRecoveryGeneration++;
      _consecutiveLoadFailures = 0;
      _ignoreCompletedUntil = null;
      _playbackHistory.clear();
      _hasStarted = false;
      _originAudio = false;
      _isPlaying = false;
      _isRepeat = false;
      _activePlaybackPlaylist = null;
      _activePlaylistTracks = [];
      _markLoading();
      _isAudioReady = false;
      _currentOriginTrack = null;
      _currentSupportTrack = null;
      _currentTime = Duration.zero;
      _duration = Duration.zero;
      _isTransitioning = true;
      notifyListeners();

      try {
        await Future.wait([
          _playerPrimary.stop(),
          _playerSupport.stop(),
          // _isRepeat was just cleared, so the players' native repeat-one mode
          // has to be cleared with it or the refreshed track would loop forever.
          _playerPrimary.setLoopMode(LoopMode.off),
          _playerSupport.setLoopMode(LoopMode.off),
        ]);
      } catch (e) {
        print('refreshRadio stop error: $e');
      } finally {
        _isTransitioning = false;
      }

      await _loadInitialTracks();
      if (_isAudioReady) {
        await startPlayback();
      }
    } finally {
      _softRefreshInFlight = false;
    }
  }

  void seek(Duration position) {
    // Live playback follows the shared station clock — user scrubbing is
    // disabled (matches Nuxt onSliderInput returning early in live mode).
    if (_isLiveMode) return;

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
    // Seek is intentional progress — reset stuck clock so scrubbing cannot
    // look like a frozen playhead.
    if (_expectingPlayback) {
      _lastProgressPosition = target;
      _lastProgressAt = DateTime.now();
    }
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

    // Nuxt `isRepeat` is only consulted by `nextOrRepeat()`, and in live mode
    // that function takes the station-advance branch first — repeat simply has
    // no effect on air. Applying the player's native loop-one here would freeze
    // the shared station on one song for *every* listener (the `completed`
    // event that drives the live advance would never fire), so live never locks
    // the buffer. `_nextOrRepeat()` restarts the track itself in shuffle.
    if (_isLiveMode) return;

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
    // Genre filters don't apply in live mode (station draws from a fixed pool).
    if (_isLiveMode) return;

    // Match the frontend exactly: every genre can independently be enabled or
    // disabled, including turning all filters off (which means "all genres").
    final turningOff = genre.active;
    genre.active = !genre.active;
    notifyListeners();

    // Persist the same `myGenres` array used by the mobile web version.
    final prefs = await SharedPreferences.getInstance();
    final genresJson = jsonEncode(_genres.map((g) => g.toJson()).toList());
    await prefs.setString('myGenres', genresJson);

    // The inactive player already holds the next track. Nuxt
    // `refreshQueuedTrackIfMatchesGenre()` only refetches it when that buffer
    // actually belongs to the genre being switched off — never touch the
    // playing buffer.
    if (turningOff && !isPlaylistMode && !_isLiveMode) {
      final upcoming = _originAudio ? _currentOriginTrack : _currentSupportTrack;
      if (_trackHasGenre(upcoming, genre.genre)) {
        _scheduleInactiveRefill();
      }
    }
  }

  /// Nuxt `trackHasGenre()` — case-insensitive substring match on the genre.
  static bool _trackHasGenre(Music? track, String genreKeyword) {
    if (track == null || track.genre.isEmpty || genreKeyword.isEmpty) {
      return false;
    }
    return track.genre.toLowerCase().contains(genreKeyword.toLowerCase());
  }

  // ---------------------------------------------------------------------------
  // Live radio mode — shared `live-music` station (web + this app stay in sync)
  // ---------------------------------------------------------------------------

  /// Enter the shared live station (primary player only, station-clock synced).
  Future<void> enterLiveMode() async {
    if (_isLiveMode) return;
    _wantLive = true;
    _liveBusy = true;
    notifyListeners();
    try {
      _stopLiveSync();
      _cancelBootAutoplayRetry();

      // Drop shuffle / playlist ownership of the players.
      _activePlaybackPlaylist = null;
      _activePlaylistTracks = [];
      _isRepeat = false;
      await _playerPrimary.setLoopMode(LoopMode.off);
      await _playerSupport.setLoopMode(LoopMode.off);
      try {
        await _playerSupport.stop();
      } catch (_) {}

      _originAudio = false;
      _playbackHistory.clear();
      _consecutiveLoadFailures = 0;
      _isLiveMode = true;
      _hasStarted = true;
      _expectingPlayback = true;
      _liveLoadedAudio = '';
      _lastAppliedLiveIdentity = '';
      _liveStation = null;
      _liveAdvanceBusy = false;
      _liveAdvanceQueued = false;
      _liveFailCount = 0;
      _lastLiveAdvanceAt = null;
      _liveClaimsInRow = 0;
      _liveStationBlocked = false;
      _lastLiveStationRetryAt = null;

      _disarmStuckWatch();
      _markLoading();
      notifyListeners();

      await _ensureAudioSessionActive();
      await _playLiveStation(fromUser: true);

      // Keep in sync with the station: realtime + polling (same as the web app),
      // plus a local resync tick to correct drift and advance on expiry.
      _liveSubscriptionCancel = _liveService.subscribeLiveStation(
        (row) => unawaited(_onLiveStationChange(row)),
      );
      _startLiveResyncTimer();

      _emitToast('Radio Live', 'Live radio');
    } finally {
      _liveBusy = false;
      notifyListeners();
    }
  }

  /// [silent] skips the "back to shuffle" toast — used when a playlist takes
  /// over the players (Nuxt clears the live mode inline in playFromPlaylist).
  Future<void> exitLiveMode({bool silent = false}) async {
    if (!_isLiveMode) return;
    _isLiveMode = false;
    _wantLive = false;
    _liveBusy = true;
    notifyListeners();
    try {
      _stopLiveSync();
      _liveStation = null;
      _liveLoadedAudio = '';
      _lastAppliedLiveIdentity = '';
      _originAudio = false;

      // Nuxt `exitLiveMode()` = `returnToMainRandom({ silent: true })`: reload the
      // dual shuffle buffers and *always* play (`playAudio()` is unconditional),
      // so a live session that was paused still hands back to a running radio.
      await returnToMainRandom();
      if (!silent) {
        _emitToast('You can change tracks.', 'Random radio');
      }
    } finally {
      _liveBusy = false;
      notifyListeners();
    }
  }

  /// Ensures a live track is on air and plays it on the primary player.
  ///
  /// [fromUser] marks a deliberate request (play button, pull-to-refresh, entering
  /// live): it clears the claim circuit breaker, so a listener who explicitly asks
  /// for the station always gets one fresh attempt instead of being stuck behind a
  /// failure counted by the background tick.
  Future<void> _playLiveStation({bool fromUser = false}) async {
    _lastLiveStationRetryAt = DateTime.now();
    if (fromUser) {
      _liveStationBlocked = false;
      _liveClaimsInRow = 0;
    }
    _expectingPlayback = true;
    _markLoading();
    notifyListeners();
    try {
      final row = await _liveService.ensureLiveStation(
        excludeTrack: _currentOriginTrack,
      );
      if (row == null || !row.hasAudio) {
        _markNotLoading();
        notifyListeners();
        _emitToast('Live radio is unavailable right now.', 'Live', ServiceToastKind.warning);
        return;
      }
      if (await _applyLiveRow(row, play: true)) {
        await _advanceLiveStation(force: true);
      }
    } catch (e) {
      // Nuxt `playLiveStation()` catch → `forcePlayNextAfterLoadFailure()`: the
      // station is re-synced once locally before it is taken over for everyone.
      print('playLiveStation failed: $e');
      _markNotLoading();
      notifyListeners();
      await _recoverLiveFailure();
    }
  }

  /// Nuxt `waitForAudioReady(myMusic.value)` inside `applyLiveRow`. The station
  /// clock — and especially the "this track is already over" decision — can only
  /// be judged once the media duration is known. Reading a half-buffered player
  /// used to mistake a partial buffer for the end of the song, which made the
  /// app claim a brand new station track (skipping it for every other listener).
  Future<void> _waitLiveBufferReady() async {
    if (_playerPrimary.processingState == ProcessingState.ready &&
        _playerPrimary.duration != null) {
      return;
    }

    final done = Completer<void>();
    final sub = _playerPrimary.playerStateStream.listen((state) {
      if (!done.isCompleted &&
          state.processingState == ProcessingState.ready &&
          _playerPrimary.duration != null) {
        done.complete();
      }
    });
    try {
      await done.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      // Not fatal: the play confirmation below still gets its own window, and a
      // hard failure now travels through the station-recovery path.
      print('Live buffer stayed unready — continuing with the station clock');
    } finally {
      await sub.cancel();
    }
  }

  /// Loads [row] on the primary player (only if the audio actually changed) and
  /// seeks to the elapsed station time so every listener is phase-aligned.
  ///
  /// Returns `true` when the on-air track is already over (Nuxt's `'ended'`),
  /// which the caller turns into a station advance. Load/play failures **throw**
  /// instead of advancing: exactly like Nuxt's `applyLiveRow`, so the caller can
  /// retry the station (`_recoverLiveFailure`) before taking it over.
  Future<bool> _applyLiveRow(LiveStation row, {bool play = true}) async {
    if (!row.hasAudio) return false;

    _originAudio = false;
    _currentOriginTrack = row.toMusic();
    _liveStation = row;
    _lastAppliedLiveIdentity = row.identity;

    if (_liveLoadedAudio != row.audio) {
      try {
        await _playerPrimary.setUrl(row.audio).timeout(_setUrlTimeout);
        _liveLoadedAudio = row.audio;
      } catch (e) {
        print('Live setUrl failed: $e');
        rethrow;
      }
    }

    await _waitLiveBufferReady();

    final elapsed = LiveStation.getElapsedSeconds(row.startedAt);
    final mediaDuration = _playerPrimary.duration;
    final mediaSeconds = (mediaDuration?.inMilliseconds ?? 0) / 1000.0;

    // Nuxt `seekLiveAudioToElapsed()`: at/past the end of the buffered media the
    // station has moved on — no DB-duration exception to this rule.
    if (mediaSeconds > 0 && elapsed >= (mediaSeconds - 0.35).clamp(0.4, 1e9)) {
      return true;
    }

    final target = Duration(milliseconds: (elapsed * 1000).round());
    if ((_playerPrimary.position - target).abs() >
        const Duration(milliseconds: 350)) {
      try {
        await _playerPrimary.seek(target);
      } catch (_) {}
    }
    _currentTime = _playerPrimary.position;
    if (mediaDuration != null && mediaDuration > Duration.zero) {
      _duration = mediaDuration;
    }
    // Re-baseline the stuck-playhead clock. It still holds the *previous* buffer's
    // position, so joining a station 100 s in (or a shorter track) would never
    // satisfy `pos > _lastProgressPosition + 150ms` — the 11 s watchdog then read
    // healthy live audio as frozen and advanced the shared station for everyone.
    _lastProgressPosition = _playerPrimary.position;
    _lastProgressAt = DateTime.now();
    notifyListeners();

    // Nuxt `applyLiveRow()` → `updateVolume()` before playing. The live branch of
    // `updateVolume()` always uses the full user volume (no end-of-track fade),
    // which also clears any fade the shuffle buffer was mid-way through — without
    // it the station could start quiet or completely silent.
    _restoreFullVolume();

    if (play) {
      try {
        await _playActiveAndConfirm();
        _consecutiveLoadFailures = 0;
        _liveFailCount = 0;
        // The station is audible: hand the claim budget back, so a later genuine
        // end-of-track can advance normally again.
        _liveClaimsInRow = 0;
        _liveStationBlocked = false;
      } catch (e) {
        print('Live play confirm failed: $e');
        rethrow;
      }
    }
    return false;
  }

  /// Reacts to a station update from realtime / polling.
  ///
  /// Everything it touches is the primary player, and a player that has no media
  /// (or is still buffering) **throws** on seek/play. This runs inside an
  /// `unawaited(...)` from the Supabase subscription, so an escaping error becomes
  /// an uncaught async error and Android kills the app — which is what "it crashes
  /// when I switch to live" looked like. Nuxt wraps the same function in a
  /// try/catch (`→ forcePlayNextAfterLoadFailure`); the outer wrapper does that here.
  Future<void> _onLiveStationChange(LiveStation row) async {
    try {
      await _handleLiveStationChange(row);
    } catch (e) {
      print('onLiveStationChange failed: $e');
      try {
        await _recoverLiveFailure();
      } catch (_) {}
    }
  }

  Future<void> _handleLiveStationChange(LiveStation row) async {
    if (!_isLiveMode || !row.hasAudio) return;

    // Nuxt's subscription tests expiry *before* the identity match, so a row that
    // aged out is moved on even when it is the one already applied. Checking it
    // after the identity branch made that case a no-op (drift was still small).
    if (LiveStation.isTrackExpired(row)) {
      _liveStation = row;
      await _advanceLiveStation(force: true);
      return;
    }
    if (_liveAdvanceBusy) return;

    final identity = row.identity;
    if (identity.isNotEmpty && identity == _lastAppliedLiveIdentity) {
      // Same track — only correct drift if we've fallen behind the station.
      if (!_expectingPlayback) return;
      final elapsed = LiveStation.getElapsedSeconds(row.startedAt);
      final drift =
          (_playerPrimary.position.inMilliseconds / 1000.0 - elapsed).abs();
      if (drift <= 2.5) return;
      // Nuxt re-checks the buffer end after a drift seek: catching up can land
      // the playhead past the media, which means the station has moved on.
      final mediaSeconds =
          (_playerPrimary.duration?.inMilliseconds ?? 0) / 1000.0;
      if (mediaSeconds > 0 && elapsed >= mediaSeconds - 0.35) {
        await _advanceLiveStation(force: true);
        return;
      }
      try {
        await _playerPrimary
            .seek(Duration(milliseconds: (elapsed * 1000).round()));
      } catch (e) {
        // A drift correction is cosmetic — never let it bubble up (see above).
        print('Live drift seek skipped: $e');
        return;
      }
      // ...and keeps the element sounding if the seek paused the buffer.
      if (_expectingPlayback && !_playerPrimary.playing) {
        unawaited(_playerPrimary.play().catchError((Object _) {}));
      }
      return;
    }

    _liveStation = row;
    if (await _applyLiveRow(row, play: _expectingPlayback)) {
      await _advanceLiveStation(force: true);
    }
  }

  /// Claims/publishes the next track on the shared station and plays it.
  Future<void> _advanceLiveStation({bool force = false}) async {
    if (!_isLiveMode) return;
    // Circuit breaker open (too many claims that never reached playback): reading
    // the station is still allowed — sync/drift happen in the tick and in
    // `_onLiveStationChange` — but this app stops *writing* the shared row.
    if (_liveStationBlocked) {
      print('Live advance skipped — claim circuit breaker is open');
      _markNotLoading();
      notifyListeners();
      return;
    }
    if (_liveAdvanceBusy) {
      // Nuxt queues the request instead of dropping it — a track that ends (or
      // a station update that arrives) during an in-flight advance still gets
      // processed once the current pass finishes.
      _liveAdvanceQueued = true;
      return;
    }

    _liveAdvanceBusy = true;
    _expectingPlayback = true;
    _markLoading();
    notifyListeners();
    try {
      var guard = 0;
      while (_isLiveMode) {
        _liveAdvanceQueued = false;
        if (++guard > 4) break;

        // Re-read the authoritative row (the web client does the same at the top
        // of every advance) instead of trusting the cached `_liveStation`, so the
        // compare-and-swap uses the real startedAt and a healthy on-air track is
        // never mistaken for an expired one.
        final current = await _liveService.fetchLiveStation() ?? _liveStation;

        // Nuxt: unless we truly reached the end (`force`), a still-valid track
        // that is on air is only synced to. Claiming a new song when the on-air
        // row is healthy is what made the station flip through tracks.
        if (!force &&
            current != null &&
            current.hasAudio &&
            !LiveStation.isTrackExpired(current)) {
          final ended = await _applyLiveRow(current, play: _expectingPlayback);
          if (!ended) break;
        }

        // Throttle real claims so a burst of events cannot flip through many
        // tracks in a couple of seconds. The web never needs this because it has
        // no local timer; on native the tick + focus noise make 6s the floor.
        final last = _lastLiveAdvanceAt;
        if (last != null &&
            DateTime.now().difference(last) < _liveClaimThrottle) {
          _markNotLoading();
          break;
        }
        _lastLiveAdvanceAt = DateTime.now();

        // Count the write. If this many claims in a row never became audible,
        // something is wrong here (CDN, dead row, clock) — stop rewriting the
        // station for every other listener and wait for the user.
        if (++_liveClaimsInRow > _maxLiveClaimsWithoutPlayback) {
          _liveStationBlocked = true;
          print('Live station claimed $_liveClaimsInRow tracks without playback '
              '— blocking station writes');
          _markNotLoading();
          _emitToast(
            'Live radio is unavailable right now.',
            'Live',
            ServiceToastKind.warning,
          );
          break;
        }

        final next = await _liveService.advanceLiveStation(
          currentRow: current,
          excludeTrack: _currentOriginTrack,
        );
        if (next == null || !next.hasAudio) {
          _markNotLoading();
          break;
        }
        _lastAppliedLiveIdentity = '';
        if (await _applyLiveRow(next, play: _expectingPlayback)) {
          // The freshly claimed row was already over → keep advancing (Nuxt sets
          // `force = true` here so the next pass skips the sync shortcut).
          force = true;
          _liveAdvanceQueued = true;
        }

        // Nuxt `while (liveAdvanceQueued && isLiveMode)`: stop as soon as the
        // station holds a track that is actually playable, otherwise a single
        // user-initiated advance would claim several songs in a row.
        if (!_liveAdvanceQueued) break;
      }
    } catch (e) {
      // Nuxt `advanceSharedLiveStation()` catch → `forcePlayNextAfterLoadFailure()`
      // (fire and forget, so the busy flag is released immediately).
      print('advanceLiveStation failed: $e');
      _markNotLoading();
      unawaited(_recoverLiveFailure());
    } finally {
      _liveAdvanceBusy = false;
      if (_liveAdvanceQueued && _isLiveMode) {
        _liveAdvanceQueued = false;
        unawaited(_advanceLiveStation(force: true));
      }
      notifyListeners();
    }
  }

  /// Local clock check every 2s: advance when the on-air track expires and
  /// nudge the player back onto the station position if it drifted.
  void _startLiveResyncTimer() {
    _liveResyncTimer?.cancel();
    _liveResyncTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_liveResyncTick()),
    );
  }

  Future<void> _liveResyncTick() async {
    if (!_isLiveMode) return;

    // Nuxt has no timer at all while the user is paused: nothing may claim a new
    // station track (that would skip songs for every other listener). Resuming
    // goes through `resumeAudio()` → `_playLiveStation()`, which re-syncs to
    // whatever is on air — or publishes the next track if it aged out.
    if (!_expectingPlayback) return; // user-paused — don't fight them

    final row = _liveStation;
    if (row == null) {
      // Nothing was ever applied — the very first station load failed. Without
      // this the app would sit in live mode in permanent silence (spinner
      // cleared, no subscription row cached, watchdog idle) until the user
      // toggled out and back in. Rate-limited: it used to hammer Supabase every
      // 2s forever when the station was simply unreachable.
      if (_liveStationBlocked || _liveAdvanceBusy) return;
      final lastRetry = _lastLiveStationRetryAt;
      if (lastRetry != null &&
          DateTime.now().difference(lastRetry) < const Duration(seconds: 8)) {
        return;
      }
      unawaited(_playLiveStation());
      return;
    }

    if (LiveStation.isTrackExpired(row)) {
      // The cached row says the song is over. Never claim on that alone — a stale
      // cache, a wrong device clock or a bogus duration would rewrite the shared
      // station for everybody. Re-read the authoritative row and only advance if
      // the database agrees that it is really expired.
      final fresh = await _liveService.fetchLiveStation();
      if (fresh == null || !fresh.hasAudio) return;
      _liveStation = fresh;

      if (!LiveStation.isTrackExpired(fresh)) {
        // Somebody already moved the station on: sync to it, don't claim it.
        if (fresh.identity != _lastAppliedLiveIdentity) {
          await _onLiveStationChange(fresh);
        }
        return;
      }
      await _advanceLiveStation(force: true);
      return;
    }

    final elapsed = LiveStation.getElapsedSeconds(row.startedAt);
    final mediaSeconds = (_playerPrimary.duration?.inMilliseconds ?? 0) / 1000.0;
    if (mediaSeconds > 0 && elapsed >= mediaSeconds - 0.35) {
      // The station clock passed the end of the loaded media. Same rule as the
      // web's `maybeAdvanceLiveIfFinished()`, and the claim breaker caps it if
      // the media duration turns out to be nonsense.
      unawaited(_advanceLiveStation(force: true));
      return;
    }

    final drift =
        (_playerPrimary.position.inMilliseconds / 1000.0 - elapsed).abs();
    if (drift > 2.5) {
      // Guarded: a seek on an idle / still-buffering player throws, and an
      // unhandled async error from a Timer.periodic callback crashes Android.
      unawaited(
        _playerPrimary
            .seek(Duration(milliseconds: (elapsed * 1000).round()))
            .catchError((Object e) {
          print('Live resync seek failed: $e');
        }),
      );
    }
    if (!_playerPrimary.playing) {
      unawaited(_playerPrimary.play().catchError((Object _) {}));
    }
  }

  void _stopLiveSync() {
    _liveSubscriptionCancel?.call();
    _liveSubscriptionCancel = null;
    _liveResyncTimer?.cancel();
    _liveResyncTimer = null;
    // Nuxt `stopLiveSync()` clears the advance bookkeeping too.
    _liveAdvanceQueued = false;
    _liveFailCount = 0;
    _liveAdvanceBusy = false;
    _lastAppliedLiveIdentity = '';
  }

  @override
  void dispose() {
    _stopLiveSync();
    _cancelBootAutoplayRetry();
    _disarmStuckWatch();
    _interruptionSub?.cancel();
    _becomingNoisySub?.cancel();
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
