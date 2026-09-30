import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemPerformanceSample {
  final int idleTicks;
  final int kernelTicks;
  final int userTicks;
  final int totalMemoryBytes;
  final int availableMemoryBytes;
  final double? framesPerSecond;
  final double? gpuPercent;
  final String fpsStatus;
  final int processId;
  final int revision;

  const SystemPerformanceSample({
    required this.idleTicks,
    required this.kernelTicks,
    required this.userTicks,
    required this.totalMemoryBytes,
    required this.availableMemoryBytes,
    this.framesPerSecond,
    this.gpuPercent,
    this.fpsStatus = 'selectProcess',
    this.processId = 0,
    this.revision = 0,
  });

  factory SystemPerformanceSample.fromMap(Map<Object?, Object?> map) {
    int read(String key) => (map[key] as num).toInt();
    return SystemPerformanceSample(
      idleTicks: read('idleTicks'),
      kernelTicks: read('kernelTicks'),
      userTicks: read('userTicks'),
      totalMemoryBytes: read('totalMemoryBytes'),
      availableMemoryBytes: read('availableMemoryBytes'),
      framesPerSecond: (map['framesPerSecond'] as num?)?.toDouble(),
      gpuPercent: (map['gpuPercent'] as num?)?.toDouble(),
      fpsStatus: map['fpsStatus'] as String? ?? 'selectProcess',
      processId: (map['processId'] as num?)?.toInt() ?? 0,
      revision: (map['revision'] as num?)?.toInt() ?? 0,
    );
  }
}

class SystemPerformanceReading {
  final double? cpuPercent;
  final double? framesPerSecond;
  final double? gpuPercent;
  final double usedMemoryGiB;
  final double totalMemoryGiB;

  const SystemPerformanceReading({
    required this.cpuPercent,
    required this.framesPerSecond,
    required this.gpuPercent,
    required this.usedMemoryGiB,
    required this.totalMemoryGiB,
  });
}

class SystemPerformanceTracker {
  SystemPerformanceSample? _previous;
  double? _cpuPercent;

  SystemPerformanceReading update(SystemPerformanceSample current) {
    final previous = _previous?.revision == current.revision ? _previous : null;
    _previous = current;
    if (previous == null) _cpuPercent = null;
    if (previous != null) {
      final idleDelta = current.idleTicks - previous.idleTicks;
      final totalDelta =
          current.kernelTicks +
          current.userTicks -
          previous.kernelTicks -
          previous.userTicks;
      if (totalDelta > 0 && idleDelta >= 0 && idleDelta <= totalDelta) {
        _cpuPercent = 100 * (1 - idleDelta / totalDelta);
      }
    }
    const gib = 1024 * 1024 * 1024;
    return SystemPerformanceReading(
      cpuPercent: _cpuPercent,
      framesPerSecond: current.framesPerSecond,
      gpuPercent: current.gpuPercent,
      usedMemoryGiB:
          (current.totalMemoryBytes - current.availableMemoryBytes) / gib,
      totalMemoryGiB: current.totalMemoryBytes / gib,
    );
  }
}

class PerformanceProcess {
  final String executable;
  final String title;
  const PerformanceProcess({required this.executable, required this.title});

  factory PerformanceProcess.fromMap(Map<Object?, Object?> data) =>
      PerformanceProcess(
        executable: data['executable'] as String,
        title: data['title'] as String? ?? '',
      );
}

class SystemPerformanceProvider {
  static final fpsStatus = ValueNotifier<String>('selectProcess');
  static const MethodChannel _channel = MethodChannel(
    'md3_music_widget/system_performance',
  );

  static Future<void> configure({
    required bool enabled,
    required String executable,
  }) async {
    if (enabled) {
      fpsStatus.value = executable.isEmpty ? 'selectProcess' : 'starting';
    }
    try {
      await _channel.invokeMethod<void>('configure', {
        'enabled': enabled,
        'executable': executable,
      });
    } on PlatformException {
      fpsStatus.value = 'captureFailed';
    } on MissingPluginException {
      fpsStatus.value = 'unavailable';
    }
  }

  static Future<List<PerformanceProcess>> processes() async {
    try {
      final entries = await _channel.invokeListMethod<Object?>('processes');
      return entries
              ?.whereType<Map>()
              .map(
                (entry) => PerformanceProcess.fromMap(
                  Map<Object?, Object?>.from(entry),
                ),
              )
              .toList() ??
          [];
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  static Future<void> shutdown() async {
    try {
      await _channel.invokeMethod<void>('shutdown');
    } on PlatformException {
       
    } on MissingPluginException {
       
    }
  }

  static Future<bool> restartElevated() async {
    try {
      return await _channel.invokeMethod<bool>('restartElevated') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<SystemPerformanceSample?> sample() async {
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>('sample');
      if (data == null) return null;
      final sample = SystemPerformanceSample.fromMap(data);
      fpsStatus.value = sample.fpsStatus;
      return sample.totalMemoryBytes > 0 ? sample : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
