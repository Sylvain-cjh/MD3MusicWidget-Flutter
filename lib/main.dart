import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_state.dart';
import 'ui/player_view.dart';

const Size _maximumWindowSize = Size(16384, 16384);

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

  final windowReady = Completer<void>();
  runApp(MusicWidgetApp(windowReady: windowReady.future));

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setAlwaysOnTop(AppState.isAlwaysOnTop);
    await windowManager.setIgnoreMouseEvents(false, forward: true);
    await windowManager.setAspectRatio(0);
    await windowManager.setMinimumSize(Size.zero);
    await windowManager.setMaximumSize(_maximumWindowSize);
    await windowManager.setResizable(false);
    await windowManager.setPreventClose(true);
    if (!windowReady.isCompleted) windowReady.complete();
    await windowManager.show();
    await windowManager.focus();
  });

  unawaited(
    Future<void>.delayed(
      const Duration(milliseconds: 450),
      AppState.loadSystemFonts,
    ),
  );
}

class MusicWidgetApp extends StatelessWidget {
  final Future<void> windowReady;

  const MusicWidgetApp({super.key, required this.windowReady});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PlayerView(windowReady: windowReady),
    );
  }
}
