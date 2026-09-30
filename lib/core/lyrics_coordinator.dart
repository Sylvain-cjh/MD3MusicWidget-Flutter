import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lyrics_document.dart';
import 'platform_provider.dart';

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

  const LyricsState({
    required this.status,
    this.providerId = '',
    this.document,
    this.lineIndex = -1,
    this.issue = LyricsIssue.none,
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
  double _positionMs = 0;
  bool _disposed = false;

  LyricsCoordinator(this.providers);

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
        _state.status == LyricsStatus.ready &&
        _selectedProviderId == providerId &&
        _providerRevision == providers.revision) {
      _trackIdentity = identity;
      return;
    }
    _trackIdentity = identity;
    _displayTrackIdentity = displayIdentity;
    _selectedProviderId = providerId;
    _providerRevision = providers.revision;
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
    _setState(
      LyricsState(status: LyricsStatus.loading, providerId: provider.id),
    );
    try {
      final document = await provider.loadLyrics(track!);
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
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
