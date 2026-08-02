import 'dart:async';

import 'package:audio_service/audio_service.dart' as os_audio;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/supabase_service.dart';
import 'services/audio_service.dart';
import 'services/media_audio_handler.dart';
import 'screens/player_screen.dart';

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

  // Render the Flutter UI before starting the media session or loading tracks.
  // This guarantees that an audio-service startup error can never leave Android
  // on a blank launch window.
  final audioService = AudioService();
  runApp(MyApp(audioService: audioService));

  // Track loading and the OS media session are independent. Starting them in
  // parallel prevents a vendor-specific media-service delay from trapping the
  // UI on its loading screen.
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

  const MyApp({
    Key? key,
    required this.audioService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dance Baby Radio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF84F3FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF84F3FF),
          secondary: Color(0xFF52DCFF),
          surface: Color(0xFF10191A),
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: PlayerScreen(audioService: audioService),
    );
  }
}
