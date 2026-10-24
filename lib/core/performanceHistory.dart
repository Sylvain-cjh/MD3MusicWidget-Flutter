import 'dart:collection';
import 'systemPerformanceProvider.dart';


class PerformanceHistory {
  static const capacity = 60;
  final ListQueue<Map<PerformanceMetric, double?>> _samples = ListQueue();
  int get length => _samples.length;

  void add(SystemPerformanceReading? reading, int mask) {
    double? finite(double? value) =>
        value != null && value.isFinite ? value : null;
    _samples.add({
      for (final metric in PerformanceMetric.values)
        metric: !metric.enabledIn(mask) || reading == null
            ? null
            : finite(switch (metric) {
                PerformanceMetric.fps => reading.framesPerSecond,
                PerformanceMetric.cpu => reading.cpuPercent,
                PerformanceMetric.gpu => reading.gpuPercent,
                PerformanceMetric.memory =>
                  reading.totalMemoryGiB > 0
                      ? reading.usedMemoryGiB / reading.totalMemoryGiB * 100
                      : null,
              }),
    });
    if (_samples.length > capacity) _samples.removeFirst();
  }

  List<double?> values(PerformanceMetric metric) =>
      List.unmodifiable(_samples.map((sample) => sample[metric]));
  void clearMetric(PerformanceMetric metric) {
    for (final sample in _samples) {
      sample[metric] = null;
    }
  }
}
