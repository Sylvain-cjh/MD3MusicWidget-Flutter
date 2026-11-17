import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';

import 'platformProvider.dart';

final class QueueCoordinator extends ChangeNotifier {
  final PlatformProviderRegistry registry;
  PlatformQueue? _queue;
  String? _trackIdentity;
  (String, double)? _lookupIdentity;
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
  
  
  PlatformQueue? queueForTrack(PlatformTrack? track, {String? providerId}) {
    if (_queue == null ||
        track == null ||
        track.contextIdentity != _trackIdentity ||
        !_sameLookup(_lookupFor(track), _lookupIdentity)) {
      return null;
    }
    final provider = registry.queueFor(track, providerId: providerId);
    return identical(provider, _provider) &&
            _contextFor(provider) == _contextKey
        ? _queue
        : null;
  }

  QueuePlatformProvider? _provider;
  static (String, double) _lookupFor(PlatformTrack track) =>
      (track.queueIdentity, track.durationMs);

  static bool _sameLookup((String, double)? a, (String, double)? b) {
    if (a == null || b == null) return a == b;
    return a.$1 == b.$1 &&
        (a.$2 > 0) == (b.$2 > 0) &&
        PlatformTrack.compatibleDuration(a.$2, b.$2);
  }

  static String? _contextFor(QueuePlatformProvider? provider) =>
      provider is QueueContextProvider
      ? (provider as QueueContextProvider).queueContextKey
      : provider?.id;
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
    final lookupIdentity = provider == null ? null : _lookupFor(track!);
    final contextKey = _contextFor(provider);
    if (!force &&
        identity == _trackIdentity &&
        _sameLookup(lookupIdentity, _lookupIdentity) &&
        identical(provider, _provider) &&
        contextKey == _contextKey) {
      return;
    }
    final serial = ++_requestSerial;
    _cancelRetry();
    final keepQueue =
        identity != null &&
        identity == _trackIdentity &&
        _sameLookup(lookupIdentity, _lookupIdentity) &&
        identical(provider, _provider) &&
        contextKey == _contextKey;
    _trackIdentity = identity;
    _lookupIdentity = lookupIdentity;
    _provider = provider;
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
