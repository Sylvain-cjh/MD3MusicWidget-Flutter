import 'package:flutter/services.dart';

enum WindowsTrayAction { activate, restore, exit, available, unavailable }

class WindowsTrayBridge {
  WindowsTrayBridge({
    this.channel = const MethodChannel('md3_music_widget/system_tray'),
  });

  final MethodChannel channel;
  bool _listening = false;

  Future<bool> start(Future<void> Function(WindowsTrayAction) onAction) async {
    _listening = true;
    channel.setMethodCallHandler((call) async {
      final action = _decode(call.method);
      if (_listening && action != null) await onAction(action);
    });
    return await channel.invokeMethod<bool>('start') ?? false;
  }

  Future<WindowsTrayAction?> showMenu() async =>
      _decode(await channel.invokeMethod<String>('menu'));

  WindowsTrayAction? _decode(String? method) => switch (method) {
    'activate' => WindowsTrayAction.activate,
    'restore' => WindowsTrayAction.restore,
    'exit' => WindowsTrayAction.exit,
    'available' => WindowsTrayAction.available,
    'unavailable' => WindowsTrayAction.unavailable,
    _ => null,
  };

  Future<void> stop() async {
    if (!_listening) return;
    _listening = false;
    channel.setMethodCallHandler(null);
    try {
      await channel.invokeMethod<void>('stop');
    } on PlatformException {
      
    } on MissingPluginException {
      
    }
  }
}
