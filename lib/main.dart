// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/player_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // Required for media_kit
  runApp(
    const ProviderScope(
      child: DashCamApp(),
    ),
  );
}

class DashCamApp extends StatelessWidget {
  const DashCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:        'DashCam Player',
      debugShowCheckedModeBanner: false,
      themeMode:    ThemeMode.dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor:  const Color(0xFF4FC3F7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        sliderTheme: const SliderThemeData(
          trackHeight:  3,
          thumbShape:   RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
        ),
      ),
      home: const PlayerScreen(),
    );
  }
}