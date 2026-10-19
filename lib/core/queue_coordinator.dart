import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';

import 'platform_provider.dart';

final class QueueCoordinator extends ChangeNotifier {
  final PlatformProviderRegistry registry;
  PlatformQueue? _queue;
  String? _trackIdentity;
  String? _lookupIdentity;
  String? _providerId;
  String? _error;
  bool _loading = false;
  int _requestSerial = 0;
  String? _contextKey;
  final int maximumAttempts;
  Timer? _retryTimer;
  Completer<void>? _retryWake;

  QueueCoordinator(this.registry, {int maximumAttempts = 1})
    : maximumAttempts = maximumAttempts.clamp(1, 3);

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final wake = _retryWake;
    _retryWake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  Future<void> _waitRetry(int attempt) {
    final wake = Completer<void>();
    _retryWake = wake;
    _retryTimer = Timer(Duration(milliseconds: attempt == 1 ? 500 : 1500), () {
      _retryTimer = null;
      _retryWake = null;
      wake.complete();
    });
    return wake.future;
  }

  PlatformQueue? get queue => _queue;
  String? get error => _error;
  bool get isLoading => _loading;
  String? get providerId => _providerId;

  Future<void> setTrack(
    PlatformTrack? track, {
    required bool enabled,
    bool force = false,
    String? providerId,
  }) async {
    final provider = enabled && track != null
        ? registry.queueFor(track, providerId: providerId)
        : null;
    final identity = provider == null ? null : track!.contextIdentity;
    final lookupIdentity = provider == null ? null : track!.queueIdentity;
    final contextKey = provider is QueueContextProvider
        ? (provider as QueueContextProvider).queueContextKey
        : provider?.id;
    if (!force &&
        identity == _trackIdentity &&
        lookupIdentity == _lookupIdentity &&
        provider?.id == _providerId &&
        contextKey == _contextKey) {
      return;
    }
    final serial = ++_requestSerial;
    _cancelRetry();
    final keepQueue =
        identity != null &&
        identity == _trackIdentity &&
        provider?.id == _providerId &&
        contextKey == _contextKey;
    _trackIdentity = identity;
    _lookupIdentity = lookupIdentity;
    _providerId = provider?.id;
    _contextKey = contextKey;
    if (!keepQueue) _queue = null;
    _error = null;
    _loading = provider != null;
    notifyListeners();
    if (provider == null || track == null) return;
    try {
      PlatformQueue? loaded;
      for (var attempt = 1; attempt <= maximumAttempts; attempt++) {
        try {
          loaded = await provider.loadQueue(track);
          break;
        } catch (error) {
          if (serial != _requestSerial) return;
          final denied =
              error is HttpException &&
              RegExp(
                r'\b(401|403|404|429)\b|rate limited',
              ).hasMatch(error.message);
          final transient =
              !denied &&
              (error is SocketException ||
                  error is TimeoutException ||
                  error is HttpException);
          if (!transient || attempt == maximumAttempts) rethrow;
          await _waitRetry(attempt);
          if (serial != _requestSerial) return;
        }
      }
      if (serial != _requestSerial) return;
      if (loaded != null || !keepQueue) _queue = loaded;
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

  @override
  void dispose() {
    _cancelRetry();
    _requestSerial++;
    super.dispose();
  }
}
