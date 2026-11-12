import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/appState.dart';
import 'core/fontCredits.dart';
import 'core/widgetDiagnostics.dart';
import 'ui/playerView.dart';
import 'ui/widgets/nativeClientViewport.dart';

const Size _maximumWindowSize = Size(16384, 16384);

Future<void> main() async {
  WidgetDiagnostics.mark('dartEntry');
  WidgetsFlutterBinding.ensureInitialized();
  WidgetDiagnostics.mark('bindingReady');
  FontCredits.register();
  await windowManager.ensureInitialized();
  WidgetDiagnostics.mark('windowManagerReady');

  await AppState.loadSettings();
  WidgetDiagnostics.mark('settingsReady');

  WindowOptions windowOptions = WindowOptions(
    size: Size(AppState.playerWidth, AppState.baseWindowHeight),
    minimumSize: Size.zero,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    alwaysOnTop: AppState.isAlwaysOnTop,
  );

  final windowReady = Completer<void>();
  final viewport =
      Platform.isWindows &&
          (!WidgetDiagnostics.enabled ||
              Platform.environment['MD3_LEGACY_VIEWPORT'] != '1')
      ? NativeClientViewport()
      : null;
  runApp(MusicWidgetApp(windowReady: windowReady.future, viewport: viewport));
  WidgetDiagnostics.mark('runApp');
  
  
  await windowManager.waitUntilReadyToShow(windowOptions);
  WidgetDiagnostics.mark('windowOptionsReady');
  await windowManager.setAsFrameless();
  await windowManager.setHasShadow(false);
  await windowManager.setIgnoreMouseEvents(false, forward: true);
  await windowManager.setAspectRatio(0);
  await windowManager.setMaximumSize(_maximumWindowSize);
  await windowManager.setResizable(false);
  await windowManager.setPreventClose(true);
  await viewport?.start();
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  if (!windowReady.isCompleted) windowReady.complete();
  await windowManager.show();
  await windowManager.focus();
  WidgetDiagnostics.mark('windowShown');

  unawaited(
    Future<void>.delayed(
      const Duration(milliseconds: 450),
      AppState.loadSystemFonts,
    ),
  );
}

class MusicWidgetApp extends StatelessWidget {
  final Future<void> windowReady;
  final NativeClientViewport? viewport;

  const MusicWidgetApp({super.key, required this.windowReady, this.viewport});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppState.buildTheme(),
      builder: viewport == null
          ? null
          : (context, child) => ClientViewportProjection(
              viewport: viewport!,
              child: child ?? const SizedBox.shrink(),
            ),
      home: PlayerView(
        windowReady: windowReady,
        startPlatformServices:
            !WidgetDiagnostics.enabled || WidgetDiagnostics.liveCapture,
      ),
    );
  }
}
