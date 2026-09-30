import 'package:flutter/foundation.dart';

import 'platform_provider.dart';

final class QueueCoordinator extends ChangeNotifier {
  final PlatformProviderRegistry registry;
  PlatformQueue? _queue;
  String? _trackIdentity;
  String? _providerId;
  String? _error;
  bool _loading = false;
  int _requestSerial = 0;

  QueueCoordinator(this.registry);

  PlatformQueue? get queue => _queue;
  String? get error => _error;
  bool get isLoading => _loading;
  String? get providerId => _providerId;

  Future<void> setTrack(
    PlatformTrack? track, {
    required bool enabled,
    bool force = false,
  }) async {
    final provider = enabled && track != null ? registry.queueFor(track) : null;
    final identity = provider == null ? null : track!.queueIdentity;
    if (!force && identity == _trackIdentity && provider?.id == _providerId) {
      return;
    }
    final serial = ++_requestSerial;
    _trackIdentity = identity;
    _providerId = provider?.id;
    _queue = null;
    _error = null;
    _loading = provider != null;
    notifyListeners();
    if (provider == null || track == null) return;
    try {
      final loaded = await provider.loadQueue(track);
      if (serial != _requestSerial) return;
      _queue = loaded;
    } catch (error) {
      if (serial != _requestSerial) return;
      _error = error.toString();
    } finally {
      if (serial == _requestSerial) {
        _loading = false;
        notifyListeners();
      }
    }
  }
}
