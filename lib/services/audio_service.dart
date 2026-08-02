import 'dart:async';
import 'dart:convert';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music.dart';
import '../models/genre.dart';
import 'supabase_service.dart';

class AudioService extends ChangeNotifier {
  final SupabaseService _supabaseService = SupabaseService();
  
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
  double _volume = 1.0; // 0.0 to 1.0

  Duration _currentTime = Duration.zero;
  Duration _duration = Duration.zero;

  final List<Music> _playbackHistory = [];
  List<Genre> _genres = [];

  // Subscriptions to clean up
  StreamSubscription? _primaryPositionSub;
  StreamSubscription? _primaryDurationSub;
  StreamSubscription? _primaryStateSub;
  
  StreamSubscription? _supportPositionSub;
  StreamSubscription? _supportDurationSub;
  StreamSubscription? _supportStateSub;

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
  double get volume => _volume;

  Duration get currentTime => _currentTime;
  Duration get duration => _duration;

  List<Genre> get genres => _genres;
  List<String> get activeGenreFilters =>
      _genres.where((g) => g.active).map((g) => g.genre).toList();

  AudioService() {
    _playerPrimary = AudioPlayer();
    _playerSupport = AudioPlayer();
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

    // 2. Fetch initial tracks in parallel
    await _loadInitialTracks();

    // 3. Start playing automatically as soon as the app is ready
    if (_isAudioReady) {
      resumeAudio();
    } else {
      // If not ready, listen to player state or just force play when ready
      _preloadPrimary().then((_) {
        resumeAudio();
      });
    }
  }

  Future<void> _loadInitialTracks() async {
    _isLoading = true;
    _isAudioReady = false;
    notifyListeners();

    try {
      final filters = activeGenreFilters;
      
      // Fetch both in parallel
      final results = await Future.wait([
        _supabaseService.getRandomActiveMusic(genreFilters: filters),
        _supabaseService.getRandomActiveMusic(genreFilters: filters),
      ]);

      _currentOriginTrack = results[0];
      _currentSupportTrack = results[1];

      // If they are the same, fetch support again
      if (_currentOriginTrack != null &&
          _currentSupportTrack != null &&
          _currentOriginTrack!.id == _currentSupportTrack!.id) {
        _currentSupportTrack = await _supabaseService.getRandomActiveMusic(
          genreFilters: filters,
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

  Future<void> _preloadPrimary() async {
    if (_currentOriginTrack?.audio != null && _currentOriginTrack!.audio.isNotEmpty) {
      try {
        await _playerPrimary.setUrl(_currentOriginTrack!.audio);
      } catch (e) {
        print('Error preloading primary player: $e');
        _handleTrackError(_currentOriginTrack);
      }
    }
  }

  Future<void> _preloadSupport() async {
    if (_currentSupportTrack?.audio != null && _currentSupportTrack!.audio.isNotEmpty) {
      try {
        await _playerSupport.setUrl(_currentSupportTrack!.audio);
      } catch (e) {
        print('Error preloading support player: $e');
        _handleTrackError(_currentSupportTrack);
      }
    }
  }

  void _setupListeners() {
    // Primary Player Listeners
    _primaryPositionSub = _playerPrimary.positionStream.listen((pos) {
      if (!_originAudio) {
        _currentTime = pos;
        notifyListeners();
      }
    });

    _primaryDurationSub = _playerPrimary.durationStream.listen((dur) {
      if (!_originAudio && dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    _primaryStateSub = _playerPrimary.playerStateStream.listen((state) {
      if (!_originAudio) {
        _isPlaying = state.playing;
        _isLoading = state.processingState == ProcessingState.buffering ||
                     state.processingState == ProcessingState.loading;
        
        if (state.processingState == ProcessingState.completed) {
          _nextOrRepeat();
        }
        notifyListeners();
      }
    });

    // Support Player Listeners
    _supportPositionSub = _playerSupport.positionStream.listen((pos) {
      if (_originAudio) {
        _currentTime = pos;
        notifyListeners();
      }
    });

    _supportDurationSub = _playerSupport.durationStream.listen((dur) {
      if (_originAudio && dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    _supportStateSub = _playerSupport.playerStateStream.listen((state) {
      if (_originAudio) {
        _isPlaying = state.playing;
        _isLoading = state.processingState == ProcessingState.buffering ||
                     state.processingState == ProcessingState.loading;
        
        if (state.processingState == ProcessingState.completed) {
          _nextOrRepeat();
        }
        notifyListeners();
      }
    });
  }

  void _handleTrackError(Music? track) async {
    if (track != null) {
      print('Track failed to load/play: ${track.title} (ID: ${track.id})');
      // Mark track as inactive in Supabase
      await _supabaseService.updateMusicById(track.id, {'is_active': false});
      
      // Load a replacement track
      final filters = activeGenreFilters;
      final replacement = await _supabaseService.getRandomActiveMusic(
        genreFilters: filters,
        excludeTrack: _originAudio ? _currentSupportTrack : _currentOriginTrack,
      );

      if (_originAudio) {
        _currentSupportTrack = replacement;
        await _preloadSupport();
      } else {
        _currentOriginTrack = replacement;
        await _preloadPrimary();
      }
      notifyListeners();
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

  Future<void> resumeAudio() async {
    _isLoading = true;
    notifyListeners();

    try {
      final player = activePlayer;
      await player.play();
      _isPlaying = true;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('resumeAudio failed: $e');
      _isLoading = false;
      notifyListeners();
      _handleTrackError(activeTrack);
      playNextMusic();
    }
  }

  void _nextOrRepeat() {
    if (_isRepeat) {
      seek(Duration.zero);
      resumeAudio();
    } else {
      playNextMusic();
    }
  }

  Future<void> playNextMusic() async {
    _isLoading = true;
    notifyListeners();

    // Pause current player and reset its position
    await activePlayer.pause();
    await activePlayer.seek(Duration.zero);

    // Save current track to playback history
    final currentTrack = activeTrack;
    if (currentTrack != null) {
      if (_playbackHistory.isEmpty || _playbackHistory.last.id != currentTrack.id) {
        _playbackHistory.add(currentTrack);
        if (_playbackHistory.length > 20) {
          _playbackHistory.removeAt(0);
        }
      }
    }

    // Toggle active player
    _originAudio = !_originAudio;
    _currentTime = Duration.zero;
    _duration = activePlayer.duration ?? Duration.zero;
    notifyListeners();

    // Start playing the preloaded track on the now-active player
    try {
      await activePlayer.play();
      _isPlaying = true;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('Error playing preloaded track: $e');
      _isLoading = false;
      notifyListeners();
      _handleTrackError(activeTrack);
      // Try to skip to next
      _originAudio = !_originAudio;
      playNextMusic();
      return;
    }

    // Fetch replacement for the now-inactive player in the background
    _fetchReplacementForInactivePlayer();
  }

  Future<void> _fetchReplacementForInactivePlayer() async {
    final filters = activeGenreFilters;
    final replacement = await _supabaseService.getRandomActiveMusic(
      genreFilters: filters,
      excludeTrack: activeTrack,
    );

    if (_originAudio) {
      // Primary player is now inactive, replace its track
      _currentOriginTrack = replacement;
      await _preloadPrimary();
    } else {
      // Support player is now inactive, replace its track
      _currentSupportTrack = replacement;
      await _preloadSupport();
    }
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
    notifyListeners();

    try {
      await activePlayer.play();
      _isPlaying = true;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('playPreviousMusic failed: $e');
      _isLoading = false;
      notifyListeners();
      _handleTrackError(activeTrack);
      playNextMusic();
    }
  }

  void seek(Duration position) {
    activePlayer.seek(position);
    _currentTime = position;
    notifyListeners();
  }

  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    _playerPrimary.setVolume(_volume);
    _playerSupport.setVolume(_volume);
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
    genre.active = !genre.active;
    notifyListeners();

    // Persist the same `myGenres` array used by the mobile web version.
    final prefs = await SharedPreferences.getInstance();
    final genresJson = jsonEncode(_genres.map((g) => g.toJson()).toList());
    await prefs.setString('myGenres', genresJson);
  }

  @override
  void dispose() {
    _primaryPositionSub?.cancel();
    _primaryDurationSub?.cancel();
    _primaryStateSub?.cancel();
    _supportPositionSub?.cancel();
    _supportDurationSub?.cancel();
    _supportStateSub?.cancel();
    
    _playerPrimary.dispose();
    _playerSupport.dispose();
    super.dispose();
  }
}
