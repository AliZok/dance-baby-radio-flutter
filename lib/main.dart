import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/supabase_service.dart';
import 'services/audio_service.dart';
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

  // Initialize Audio Service
  final audioService = AudioService();
  await audioService.initialize();

  runApp(MyApp(audioService: audioService));
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
        primaryColor: const Color(0xFF00FFFF),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: PlayerScreen(audioService: audioService),
    );
  }
}
