import 'package:flutter/services.dart';

class SystemPerformanceSample {
  final int idleTicks;
  final int kernelTicks;
  final int userTicks;
  final int totalMemoryBytes;
  final int availableMemoryBytes;
  final int? displayedFrames;

  const SystemPerformanceSample({
    required this.idleTicks,
    required this.kernelTicks,
    required this.userTicks,
    required this.totalMemoryBytes,
    required this.availableMemoryBytes,
    this.displayedFrames,
  });

  factory SystemPerformanceSample.fromMap(Map<Object?, Object?> map) {
    int read(String key) => (map[key] as num).toInt();
    return SystemPerformanceSample(
      idleTicks: read('idleTicks'),
      kernelTicks: read('kernelTicks'),
      userTicks: read('userTicks'),
      totalMemoryBytes: read('totalMemoryBytes'),
      availableMemoryBytes: read('availableMemoryBytes'),
      displayedFrames: (map['displayedFrames'] as num?)?.toInt(),
    );
  }
}

class SystemPerformanceReading {
  final double? cpuPercent;
  final double? desktopFramesPerSecond;
  final double usedMemoryGiB;
  final double totalMemoryGiB;

  const SystemPerformanceReading({
    required this.cpuPercent,
    required this.desktopFramesPerSecond,
    required this.usedMemoryGiB,
    required this.totalMemoryGiB,
  });
}

class SystemPerformanceTracker {
  SystemPerformanceSample? _previous;

  SystemPerformanceReading update(
    SystemPerformanceSample current, {
    required Duration elapsed,
  }) {
    final previous = _previous;
    _previous = current;
    double? cpuPercent;
    double? desktopFramesPerSecond;
    if (previous != null) {
      final idleDelta = current.idleTicks - previous.idleTicks;
      final totalDelta =
          current.kernelTicks +
          current.userTicks -
          previous.kernelTicks -
          previous.userTicks;
      if (totalDelta > 0 && idleDelta >= 0 && idleDelta <= totalDelta) {
        cpuPercent = 100 * (1 - idleDelta / totalDelta);
      }
      final displayedFrames = current.displayedFrames;
      if (displayedFrames != null &&
          displayedFrames >= 0 &&
          elapsed.inMicroseconds > 0) {
        final fps = displayedFrames * 1000000 / elapsed.inMicroseconds;
        desktopFramesPerSecond = fps;
      }
    }
    const gib = 1024 * 1024 * 1024;
    return SystemPerformanceReading(
      cpuPercent: cpuPercent,
      desktopFramesPerSecond: desktopFramesPerSecond,
      usedMemoryGiB:
          (current.totalMemoryBytes - current.availableMemoryBytes) / gib,
      totalMemoryGiB: current.totalMemoryBytes / gib,
    );
  }
}

class SystemPerformanceProvider {
  static const MethodChannel _channel = MethodChannel(
    'md3_music_widget/system_performance',
  );

  static Future<SystemPerformanceSample?> sample() async {
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>('sample');
      return data == null ? null : SystemPerformanceSample.fromMap(data);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
