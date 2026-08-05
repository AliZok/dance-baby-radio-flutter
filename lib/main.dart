import 'dart:async';

import 'package:audio_service/audio_service.dart' as os_audio;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/supabase_service.dart';
import 'services/audio_service.dart';
import 'services/auth_service.dart';
import 'services/playlist_service.dart';
import 'services/media_audio_handler.dart';
import 'screens/player_screen.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Make status bar and navigation bar transparent/translucent for full-screen immersion
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize Supabase
  await SupabaseService.initialize();

  final authService = AuthService();
  await authService.init();

  final playlistService = PlaylistService(authService);
  final audioService = AudioService();

  // Render the Flutter UI before starting the media session or loading tracks.
  // This guarantees that an audio-service startup error can never leave Android
  // on a blank launch window.
  runApp(MyApp(
    audioService: audioService,
    authService: authService,
    playlistService: playlistService,
  ));

  // Track loading and the OS media session are independent. Starting them in
  // parallel prevents a vendor-specific media-service delay from trapping the
  // UI on its loading screen. Playback itself waits for Let's GO / post-login.
  unawaited(audioService.initialize());
  unawaited(_initializeMediaSession(audioService));
}

Future<void> _initializeMediaSession(AudioService audioService) async {
  try {
    await os_audio.AudioService.init(
      builder: () => MediaAudioHandler(audioService),
      config: const os_audio.AudioServiceConfig(
        androidNotificationChannelId: 'com.dancebabyradio.app.audio',
        androidNotificationChannelName: 'Dance Baby Radio',
        // Keep the media session and its controls alive while paused, so the
        // user can resume from the lock screen without reopening the app.
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        fastForwardInterval: Duration(seconds: 10),
        rewindInterval: Duration(seconds: 10),
      ),
    );
  } catch (error, stackTrace) {
    debugPrint('Media session initialization failed: $error\n$stackTrace');
  }
}

class MyApp extends StatelessWidget {
  final AudioService audioService;
  final AuthService authService;
  final PlaylistService playlistService;

  const MyApp({
    Key? key,
    required this.audioService,
    required this.authService,
    required this.playlistService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dance Baby Radio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: Colors.black,
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: PlayerScreen(
        audioService: audioService,
        authService: authService,
        playlistService: playlistService,
      ),
    );
  }
}
