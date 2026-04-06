// lib/main.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/player_screen.dart';
import 'services/log_service.dart';
import 'services/shortcut_service.dart';

/// Command-line arguments passed at launch (e.g. file/folder path from
/// Windows file association or "Open with" context menu).
List<String> launchArgs = const [];

void main(List<String> args) async {
  launchArgs = args;
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.instance.init();
  ShortcutService.init();
  appLog('App', 'Application starting');

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size:        Size(1280, 800),
      minimumSize: Size(640, 480),
      title:       'DashCam Player',
      center:      true,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  MediaKit.ensureInitialized();

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
