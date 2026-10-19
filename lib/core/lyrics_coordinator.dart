import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lyrics_document.dart';
import 'platform_provider.dart';
import 'lyrics_disk_cache.dart';
import 'lyrics_request_error.dart';
import 'lyrics_reconnect_policy.dart';

enum LyricsStatus { unavailable, loading, ready, failed }

enum LyricsIssue {
  none,
  noTrack,
  noProvider,
  noMatch,
  network,
  rateLimited,
  invalidData,
  unknown,
}

final class LyricsState {
  final LyricsStatus status;
  final String providerId;
  final LyricsDocument? document;
  final int lineIndex;
  final LyricsIssue issue;
  final int attempt;
  final int maximumAttempts;
  final DateTime? retryAt;
  final bool automaticRetryScheduled;
  final DateTime? reconnectUntil;
  final int reconnectAttempt;
  final int maximumReconnectAttempts;

  const LyricsState({
    required this.status,
    this.providerId = '',
    this.document,
    this.lineIndex = -1,
    this.issue = LyricsIssue.none,
    this.attempt = 1,
    this.maximumAttempts = 1,
    this.retryAt,
    this.automaticRetryScheduled = false,
    this.reconnectUntil,
    this.reconnectAttempt = 0,
    this.maximumReconnectAttempts = 0,
  });

  LyricLine? get currentLine =>
      document == null || lineIndex < 0 ? null : document!.lines[lineIndex];
}

final class LyricsCoordinator extends ChangeNotifier {
  final PlatformProviderRegistry providers;
  LyricsState _state = const LyricsState(
    status: LyricsStatus.unavailable,
    issue: LyricsIssue.noTrack,
  );
  String? _trackIdentity;
  String? _displayTrackIdentity;
  int _providerRevision = -1;
  String? _selectedProviderId;
  int _generation = 0;
  int? _cacheLookupGeneration;
  double _positionMs = 0;
  bool _disposed = false;
  final LyricsDiskCache? cache;
  final int maximumAttempts;
  final bool retryMissing;
  Timer? _retryTimer;
  Completer<void>? _retryWake;
  Timer? _cooldownTimer;
  int _reconnectAttempts = 0;
  DateTime? _reconnectUntil;
  String? _reconnectProviderId;
  final LyricsReconnectPolicy reconnectPolicy;
  final DateTime Function() _now;
  final bool Function()? preferWordTimings;

  LyricsCoordinator(
    this.providers, {
    this.cache,
    int maximumAttempts = 1,
    this.retryMissing = false,
    this.reconnectPolicy = const LyricsReconnectPolicy(),
    DateTime Function()? clock,
    this.preferWordTimings,
  }) : maximumAttempts = maximumAttempts.clamp(1, 5),
       _now = clock ?? DateTime.now;

  void _cancelRetry() {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
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

  LyricsState get state => _state;

  Future<void> setTrack(
    PlatformTrack? track, {
    String? providerId,
    bool force = false,
  }) => _loadTrack(track, providerId: providerId, force: force);

  Future<void> _loadTrack(
    PlatformTrack? track, {
    String? providerId,
    bool force = false,
    bool cooldownRecovery = false,
  }) async {
    final identity = track?.identity;
    final displayIdentity = track?.contextIdentity;
    final sameContext =
        displayIdentity != null &&
        displayIdentity == _displayTrackIdentity &&
        _selectedProviderId == providerId &&
        _providerRevision == providers.revision;
    
    
    if (sameContext &&
        !cooldownRecovery &&
        _state.retryAt?.isAfter(_now()) == true) {
      return;
    }
    if (!force &&
        identity == _trackIdentity &&
        _selectedProviderId == providerId &&
        _providerRevision == providers.revision) {
      return;
    }
    if (!force &&
        displayIdentity != null &&
        displayIdentity == _displayTrackIdentity &&
        (_state.status == LyricsStatus.ready ||
            _state.status == LyricsStatus.loading ||
            _state.issue == LyricsIssue.rateLimited ||
            _reconnectUntil != null) &&
        _selectedProviderId == providerId &&
        _providerRevision == providers.revision) {
      _trackIdentity = identity;
      return;
    }
    _trackIdentity = identity;
    _displayTrackIdentity = displayIdentity;
    _selectedProviderId = providerId;
    _providerRevision = providers.revision;
    _cancelRetry();
    if (!sameContext ||
        (force &&
            !cooldownRecovery &&
            (_reconnectUntil == null || !_now().isBefore(_reconnectUntil!)))) {
      _resetReconnect();
    }
    final generation = ++_generation;
    if (!sameContext) _positionMs = 0;
    final provider = track == null
        ? null
        : providers.lyricsFor(track, providerId: providerId);
    if (provider == null) {
      _setState(
        LyricsState(
          status: LyricsStatus.unavailable,
          issue: track == null ? LyricsIssue.noTrack : LyricsIssue.noProvider,
        ),
      );
      return;
    }
    try {
      LyricsDocument? document;
      final useDisk = provider.id != 'localLrc';
      if ((!force || cooldownRecovery) && useDisk && cache != null) {
        _cacheLookupGeneration = generation;
        try {
          document = await cache!.get(track!, provider.id);
        } finally {
          if (_cacheLookupGeneration == generation) {
            _cacheLookupGeneration = null;
          }
        }
      }
      final restoredFromDisk = document != null;
      if (_disposed || generation != _generation) return;
      if (document == null) {
        
        
        final attemptLimit = cooldownRecovery ? 1 : maximumAttempts;
        if (force && !cooldownRecovery && provider is RetryableLyricsProvider) {
          (provider as RetryableLyricsProvider).invalidateMiss(track!);
        }
        
        
        _setState(
          LyricsState(
            status: LyricsStatus.loading,
            providerId: cooldownRecovery
                ? (_reconnectProviderId ?? provider.id)
                : provider.id,
            maximumAttempts: attemptLimit,
            reconnectUntil: _reconnectUntil,
            reconnectAttempt: _reconnectAttempts,
            maximumReconnectAttempts: reconnectPolicy.maximumAttempts,
          ),
        );
        for (var attempt = 1; attempt <= attemptLimit; attempt++) {
          if (_disposed || generation != _generation) return;
          if (attempt > 1) {
            _setState(
              LyricsState(
                status: LyricsStatus.loading,
                providerId: cooldownRecovery
                    ? (_reconnectProviderId ?? provider.id)
                    : provider.id,
                attempt: attempt,
                maximumAttempts: attemptLimit,
                reconnectUntil: _reconnectUntil,
                reconnectAttempt: _reconnectAttempts,
                maximumReconnectAttempts: reconnectPolicy.maximumAttempts,
              ),
            );
          }
          try {
            document = await provider.loadLyrics(track!);
            if (_disposed || generation != _generation) return;
            if (document != null && !document.isEmpty) break;
            if (!retryMissing ||
                provider is ExhaustiveLyricsProvider ||
                provider is! RetryableLyricsProvider ||
                attempt == attemptLimit) {
              break;
            }
            (provider as RetryableLyricsProvider).invalidateMiss(track);
          } catch (error) {
            if (_disposed || generation != _generation) return;
            final rateLimited =
                error is HttpException &&
                RegExp(
                  r'\b(401|403|404|429)\b|rate limited',
                ).hasMatch(error.message);
            final transient =
                error is SocketException ||
                error is TimeoutException ||
                error is HttpException;
            if (rateLimited || !transient || attempt == attemptLimit) {
              rethrow;
            }
            if (provider is RetryableLyricsProvider) {
              (provider as RetryableLyricsProvider).invalidateMiss(track!);
            }
          }
          await _waitRetry(attempt);
        }
      }
      if (_disposed || generation != _generation) return;
      _resetReconnect();
      if (document == null || document.isEmpty) {
        _setState(
          LyricsState(
            status: LyricsStatus.unavailable,
            providerId: provider.id,
            issue: LyricsIssue.noMatch,
          ),
        );
      } else {
        if (useDisk && cache != null && !restoredFromDisk) {
          unawaited(cache!.put(track!, provider.id, document));
        }
        _setState(
          LyricsState(
            status: LyricsStatus.ready,
            providerId: document.sourceProviderId.isEmpty
                ? provider.id
                : document.sourceProviderId,
            document: document,
            lineIndex: document.lineIndexAt(_positionMs),
          ),
        );
        final canEnrichNow =
            !restoredFromDisk &&
            preferWordTimings?.call() == true &&
            provider is BackgroundWordTimingLyricsProvider;
        if ((restoredFromDisk || canEnrichNow) &&
            !document.wordTimingChecked &&
            cache != null &&
            (canEnrichNow ||
                document.wordTimingRetryAt == null ||
                !document.wordTimingRetryAt!.isAfter(_now()))) {
          
          
          unawaited(_upgradeWordTiming(track!, provider, document, generation));
        }
      }
    } catch (error) {
      if (_disposed || generation != _generation) return;
      final issue = switch (error) {
        LyricsRateLimitException() => LyricsIssue.rateLimited,
        HttpException(message: final message)
            when RegExp(r'\b429\b|rate limited').hasMatch(message) =>
          LyricsIssue.rateLimited,
        HttpException() ||
        SocketException() ||
        TimeoutException() => LyricsIssue.network,
        FormatException() => LyricsIssue.invalidData,
        _ => LyricsIssue.unknown,
      };
      final rateLimit = error is LyricsRateLimitException
          ? error
          : issue == LyricsIssue.rateLimited
          ? LyricsRateLimitException(
              providerId: provider.id,
              retryAt: _now().add(const Duration(seconds: 30)),
              fromServer: true,
            )
          : null;
      final recoverableNetwork =
          cooldownRecovery &&
          issue == LyricsIssue.network &&
          !(error is HttpException &&
              RegExp(r'\b4\d\d\b').hasMatch(error.message));
      if (rateLimit != null) {
        _reconnectUntil ??= _now().add(reconnectPolicy.window);
        _reconnectProviderId = rateLimit.providerId;
      }
      final nextAttempt =
          (rateLimit != null || recoverableNetwork) && _reconnectUntil != null
          ? reconnectPolicy.nextAttempt(
              now: _now(),
              windowEnd: _reconnectUntil!,
              completedAttempts: _reconnectAttempts,
              serverRetryAt: rateLimit?.retryAt,
            )
          : null;
      final retryAt = nextAttempt ?? rateLimit?.retryAt;
      _setReconnectFailure(
        providerId:
            rateLimit?.providerId ??
            (cooldownRecovery ? _reconnectProviderId : null) ??
            provider.id,
        issue: issue,
        retryAt: retryAt,
        automatic: nextAttempt != null,
      );
      if (retryAt != null && track != null) {
        _scheduleCooldown(
          retryAt,
          track,
          providerId,
          generation,
          recover: nextAttempt != null,
        );
      }
    }
  }

  void _resetReconnect() {
    _reconnectUntil = null;
    _reconnectProviderId = null;
    _reconnectAttempts = 0;
  }

  void _setReconnectFailure({
    required String providerId,
    required LyricsIssue issue,
    required DateTime? retryAt,
    required bool automatic,
  }) => _setState(
    LyricsState(
      status: LyricsStatus.failed,
      providerId: providerId,
      issue: issue,
      retryAt: retryAt,
      automaticRetryScheduled: automatic,
      reconnectUntil: _reconnectUntil,
      reconnectAttempt: _reconnectAttempts,
      maximumReconnectAttempts: reconnectPolicy.maximumAttempts,
    ),
  );

  void _scheduleCooldown(
    DateTime retryAt,
    PlatformTrack track,
    String? providerId,
    int generation, {
    required bool recover,
  }) {
    if (_disposed || generation != _generation) return;
    final remaining = retryAt.difference(_now());
    
    final delay = remaining <= Duration.zero
        ? Duration.zero
        : remaining > const Duration(days: 1)
        ? const Duration(days: 1)
        : remaining;
    _cooldownTimer = Timer(delay, () {
      _cooldownTimer = null;
      if (_disposed || generation != _generation) return;
      if (_now().isBefore(retryAt)) {
        _scheduleCooldown(
          retryAt,
          track,
          providerId,
          generation,
          recover: recover,
        );
      } else if (recover &&
          _reconnectUntil != null &&
          reconnectPolicy.canStart(
            now: _now(),
            windowEnd: _reconnectUntil!,
            completedAttempts: _reconnectAttempts,
          )) {
        _reconnectAttempts++;
        unawaited(
          _loadTrack(
            track,
            providerId: providerId,
            force: true,
            cooldownRecovery: true,
          ),
        );
      } else {
        
        
        _setReconnectFailure(
          providerId: _state.providerId,
          issue: _state.issue,
          retryAt: _state.retryAt,
          automatic: false,
        );
      }
    });
  }

  Future<void> _upgradeWordTiming(
    PlatformTrack track,
    LyricsPlatformProvider provider,
    LyricsDocument cached,
    int generation,
  ) async {
    var replacement = cached.withWordTimingRetryAt(
      _now().add(const Duration(minutes: 5)),
    );
    try {
      final fresh = provider is WordTimingLyricsProvider
          ? await (provider as WordTimingLyricsProvider).upgradeWordTiming(
              track,
            )
          : await provider.loadLyrics(track);
      if (fresh != null && !fresh.isEmpty) {
        replacement = fresh.isWordTimed
            ? fresh.withWordTimingChecked()
            : cached.withWordTimingRetryAt(
                fresh.wordTimingRetryAt ??
                    _now().add(const Duration(minutes: 30)),
              );
      }
    } catch (error) {
      
      if (error is LyricsRateLimitException) {
        replacement = cached.withWordTimingRetryAt(error.retryAt);
      }
    }
    if (_disposed || generation != _generation) return;
    await cache!.put(track, provider.id, replacement);
    if (_disposed || generation != _generation || !replacement.isWordTimed) {
      return;
    }
    _setState(
      LyricsState(
        status: LyricsStatus.ready,
        providerId: replacement.sourceProviderId.isEmpty
            ? provider.id
            : replacement.sourceProviderId,
        document: replacement,
        lineIndex: replacement.lineIndexAt(_positionMs),
      ),
    );
  }

  void setPositionMs(double positionMs) {
    if (!positionMs.isFinite) return;
    _positionMs = positionMs < 0 ? 0 : positionMs;
    if (_cacheLookupGeneration == _generation) return;
    final document = _state.document;
    if (document == null) return;
    final index = document.lineIndexAt(_positionMs);
    if (index == _state.lineIndex) return;
    _setState(
      LyricsState(
        status: LyricsStatus.ready,
        providerId: _state.providerId,
        document: document,
        lineIndex: index,
      ),
    );
  }

  void _setState(LyricsState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelRetry();
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
