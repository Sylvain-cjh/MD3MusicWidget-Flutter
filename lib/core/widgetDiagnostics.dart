import 'dart:async';
import 'dart:ui';


abstract final class WidgetDiagnostics {
  static const enabled = bool.fromEnvironment('WIDGET_DIAGNOSTICS');
  static const liveCapture =
      enabled && bool.fromEnvironment('WIDGET_DIAGNOSTICS_LIVE_CAPTURE');
  static final marks = <String, int>{};
  static final frameMarks = <String, int>{};
  static final frames = <FrameTiming>[];
  static final actions = <String, Future<void> Function(Object?)>{};
  static final errors = <String>[];
  static final counters = <String, int>{};
  static final spans = <Map<String, Object?>>[];
  
  static bool suppressDither = false;
  static bool suppressPalette = false;

  static void mark(String name) {
    if (enabled) marks[name] = DateTime.now().microsecondsSinceEpoch;
  }

  static void markOnce(String name) {
    if (enabled) {
      marks.putIfAbsent(name, () => DateTime.now().microsecondsSinceEpoch);
    }
  }

  static void markPaintOnce(String name) {
    if (!enabled || frameMarks.containsKey(name)) return;
    frameMarks[name] = PlatformDispatcher.instance.frameData.frameNumber;
    markOnce(name);
  }

  static void count(String name) {
    if (enabled) counters.update(name, (value) => value + 1, ifAbsent: () => 1);
  }

  static Future<void> invoke(String name, [Object? argument]) async {
    if (!enabled) throw StateError('Diagnostics are not enabled');
    final action = actions[name];
    if (action == null) throw StateError('Missing diagnostic action: $name');
    await action(argument);
  }

  static Future<T> measure<T>(String name, Future<T> Function() work) {
    if (!enabled) return work();
    final start = DateTime.now().microsecondsSinceEpoch;
    final elapsed = Stopwatch()..start();
    return Future<T>.sync(work).whenComplete(() {
      elapsed.stop();
      spans.add({
        'name': name,
        'startUs': start,
        'durationUs': elapsed.elapsedMicroseconds,
      });
    });
  }
}
