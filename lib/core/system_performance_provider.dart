import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'runtime_capabilities.dart';

enum PerformanceMetric {
  fps(1),
  cpu(2),
  gpu(4),
  memory(8);

  const PerformanceMetric(this.bit);
  final int bit;
  static const allMask = 15;
  bool enabledIn(int mask) => mask & bit != 0;
  static int validMask(Object? value) =>
      value is int && value >= 0 && value <= allMask ? value : allMask;
}

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
  final int metricsMask;

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
    this.metricsMask = PerformanceMetric.allMask,
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
      metricsMask: PerformanceMetric.validMask(map['metricsMask']),
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
    if (previous == null ||
        !PerformanceMetric.cpu.enabledIn(current.metricsMask)) {
      _cpuPercent = null;
    }
    if (previous != null &&
        PerformanceMetric.cpu.enabledIn(current.metricsMask)) {
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
  static bool _fpsEnabled = false;
  static String _fpsExecutable = '';
  static int _configuration = 0;
  static final fpsStatus = ValueNotifier<String>('selectProcess');
  static const MethodChannel _channel = MethodChannel(
    'md3_music_widget/system_performance',
  );

  static Future<void> configure({
    required bool enabled,
    required String executable,
    int metricsMask = PerformanceMetric.allMask,
  }) async {
    ++_configuration;
    final fpsEnabled = enabled && PerformanceMetric.fps.enabledIn(metricsMask);
    if (!fpsEnabled) {
      fpsStatus.value = 'disabled';
    } else if (!_fpsEnabled || _fpsExecutable != executable) {
      fpsStatus.value = executable.isEmpty ? 'selectProcess' : 'starting';
    }
    _fpsEnabled = fpsEnabled;
    _fpsExecutable = executable;
    try {
      await _channel.invokeMethod<void>('configure', {
        'enabled': enabled,
        'executable': executable,
        'metricsMask': metricsMask & PerformanceMetric.allMask,
      });
    } on PlatformException {
      fpsStatus.value = 'captureFailed';
      RuntimeCapabilities.instance.set(
        RuntimeCapability.systemMetrics,
        const CapabilityStatus(
          CapabilityPhase.temporarilyUnavailable,
          reason: 'metrics_configuration_failed',
        ),
      );
    } on MissingPluginException {
      fpsStatus.value = 'unavailable';
      RuntimeCapabilities.instance.set(
        RuntimeCapability.systemMetrics,
        const CapabilityStatus(
          CapabilityPhase.unsupported,
          reason: 'native_metrics_unavailable',
        ),
      );
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
    final configuration = _configuration;
    try {
      final data = await _channel.invokeMapMethod<Object?, Object?>('sample');
      if (data == null) return null;
      final sample = SystemPerformanceSample.fromMap(data);
      if (configuration == _configuration) {
        fpsStatus.value = _fpsEnabled ? sample.fpsStatus : 'disabled';
        RuntimeCapabilities.instance.set(
          RuntimeCapability.systemMetrics,
          const CapabilityStatus(CapabilityPhase.ready),
        );
      }
      return sample.totalMemoryBytes > 0 ||
              !PerformanceMetric.memory.enabledIn(sample.metricsMask)
          ? sample
          : null;
    } on PlatformException {
      RuntimeCapabilities.instance.set(
        RuntimeCapability.systemMetrics,
        const CapabilityStatus(
          CapabilityPhase.temporarilyUnavailable,
          reason: 'metrics_sample_failed',
        ),
      );
      return null;
    } on MissingPluginException {
      RuntimeCapabilities.instance.set(
        RuntimeCapability.systemMetrics,
        const CapabilityStatus(
          CapabilityPhase.unsupported,
          reason: 'native_metrics_unavailable',
        ),
      );
      return null;
    }
  }
}
