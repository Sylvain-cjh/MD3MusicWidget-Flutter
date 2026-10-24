import 'package:flutter/foundation.dart';

enum RuntimeCapability { mediaStream, coverLayers, lyricSmoke, systemMetrics }

enum CapabilityPhase {
  initializing,
  ready,
  temporarilyUnavailable,
  unsupported,
  missingDependency,
}

final class CapabilityStatus {
  final CapabilityPhase phase;
  final String reason;
  final DateTime? retryAt;
  const CapabilityStatus(this.phase, {this.reason = '', this.retryAt});
  bool equivalent(CapabilityStatus other) =>
      phase == other.phase &&
      reason == other.reason &&
      retryAt == other.retryAt;
}



final class RuntimeCapabilities extends ChangeNotifier {
  static final instance = RuntimeCapabilities();
  final _statuses = <RuntimeCapability, CapabilityStatus>{};
  CapabilityStatus? operator [](RuntimeCapability capability) =>
      _statuses[capability];
  void set(RuntimeCapability capability, CapabilityStatus status) {
    if (_statuses[capability]?.equivalent(status) == true) return;
    _statuses[capability] = status;
    notifyListeners();
  }

  Map<String, Object?> toMap() => {
    for (final entry in _statuses.entries)
      entry.key.name: {
        'phase': entry.value.phase.name,
        'reason': entry.value.reason,
        if (entry.value.retryAt != null)
          'retryAt': entry.value.retryAt!.toUtc().toIso8601String(),
      },
  };
}
