import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lyrics_document.dart';
import 'platform_provider.dart';
import 'lyrics_disk_cache.dart';

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

  const LyricsState({
    required this.status,
    this.providerId = '',
    this.document,
    this.lineIndex = -1,
    this.issue = LyricsIssue.none,
    this.attempt = 1,
    this.maximumAttempts = 1,
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

  LyricsCoordinator(
    this.providers, {
    this.cache,
    int maximumAttempts = 1,
    this.retryMissing = false,
  }) : maximumAttempts = maximumAttempts.clamp(1, 5);

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

  LyricsState get state => _state;

  Future<void> setTrack(
    PlatformTrack? track, {
    String? providerId,
    bool force = false,
  }) async {
    final identity = track?.identity;
    final displayIdentity = track?.queueIdentity;
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
            _state.status == LyricsStatus.loading) &&
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
    final generation = ++_generation;
    _positionMs = 0;
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
      if (!force && useDisk && cache != null) {
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
        
        
        _setState(
          LyricsState(
            status: LyricsStatus.loading,
            providerId: provider.id,
            maximumAttempts: maximumAttempts,
          ),
        );
        for (var attempt = 1; attempt <= maximumAttempts; attempt++) {
          if (_disposed || generation != _generation) return;
          if (attempt > 1) {
            _setState(
              LyricsState(
                status: LyricsStatus.loading,
                providerId: provider.id,
                attempt: attempt,
                maximumAttempts: maximumAttempts,
              ),
            );
          }
          try {
            document = await provider.loadLyrics(track!);
            if (_disposed || generation != _generation) return;
            if (document != null && !document.isEmpty) break;
            if (!retryMissing ||
                provider is! RetryableLyricsProvider ||
                attempt == maximumAttempts) {
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
            if (rateLimited || !transient || attempt == maximumAttempts) {
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
      }
    } catch (error) {
      if (_disposed || generation != _generation) return;
      final issue = switch (error) {
        HttpException(message: final message)
            when message.contains('rate limited') =>
          LyricsIssue.rateLimited,
        HttpException() ||
        SocketException() ||
        TimeoutException() => LyricsIssue.network,
        FormatException() => LyricsIssue.invalidData,
        _ => LyricsIssue.unknown,
      };
      _setState(
        LyricsState(
          status: LyricsStatus.failed,
          providerId: provider.id,
          issue: issue,
        ),
      );
    }
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
