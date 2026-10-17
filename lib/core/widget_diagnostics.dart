import 'dart:async';
import 'dart:ui';


abstract final class WidgetDiagnostics {
  static const enabled = bool.fromEnvironment('WIDGET_DIAGNOSTICS');
  static final marks = <String, int>{};
  static final frames = <FrameTiming>[];
  static final actions = <String, Future<void> Function(Object?)>{};
  static final errors = <String>[];

  static void mark(String name) {
    if (enabled) marks[name] = DateTime.now().microsecondsSinceEpoch;
  }

  static Future<void> invoke(String name, [Object? argument]) async {
    if (!enabled) throw StateError('Diagnostics are not enabled');
    final action = actions[name];
    if (action == null) throw StateError('Missing diagnostic action: $name');
    await action(argument);
  }
}
