import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_state.dart';
import 'ui/player_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await AppState.loadSettings();

  WindowOptions windowOptions = WindowOptions(
    size: Size(AppState.playerWidth, AppState.baseWindowHeight),
    minimumSize: Size.zero,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: AppState.isAlwaysOnTop,
  );

  runApp(const MusicWidgetApp());

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setAlwaysOnTop(AppState.isAlwaysOnTop);
    await windowManager.setIgnoreMouseEvents(
      AppState.isMousePassthrough,
      forward: true,
    );
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAspectRatio(0);
    await windowManager.setResizable(false);
    await windowManager.setPreventClose(true);
  });

  unawaited(
    Future<void>.delayed(
      const Duration(milliseconds: 450),
      AppState.loadSystemFonts,
    ),
  );
}

class MusicWidgetApp extends StatelessWidget {
  const MusicWidgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PlayerView(),
    );
  }
}
