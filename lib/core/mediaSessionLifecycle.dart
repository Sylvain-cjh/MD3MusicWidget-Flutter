import 'dart:async';
import 'mediaProvider.dart';
import 'platformProvider.dart';

enum MediaTrackChange { track, restart, enrichment, transport, cleared }

final class MediaSessionUpdate {
  final MediaSnapshot snapshot;
  final PlatformTrack? track;
  final MediaTrackChange change;
  const MediaSessionUpdate(this.snapshot, this.track, this.change);
  bool get startsTrack =>
      change == MediaTrackChange.track || change == MediaTrackChange.restart;
}



final class MediaSessionLifecycle {
  static int _nextEpoch = 0;
  final void Function(MediaSessionUpdate) onUpdate;
  final double Function() estimatedPositionMs;
  final Duration emptyGrace;
  PlatformTrack? _track;
  MediaSnapshot? _lastSnapshot;
  MediaSnapshot? _pendingEmpty;
  Timer? _emptyTimer;
  int _producer = 0, _lastTimestamp = 0;
  final _retiredProducers = <int>[];
  bool _disposed = false;
  int accepted = 0, staleRejected = 0;

  MediaSessionLifecycle({
    required this.onUpdate,
    required this.estimatedPositionMs,
    this.emptyGrace = const Duration(milliseconds: 600),
  });

  static String _text(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  static bool _knownArtist(String value) =>
      !const {'', '未知歌手', '无媒体会话', 'unknown artist'}.contains(_text(value));
  static String _artists(String value) {
    final names = value.split(RegExp(r'[/&、]')).map(_text).toList()..sort();
    return names.join('|');
  }

  void accept(MediaSnapshot snapshot) {
    if (_disposed) return;
    if (snapshot.processId > 0) {
      if (_retiredProducers.contains(snapshot.processId)) {
        staleRejected++;
        return;
      }
      if (_producer != 0 && snapshot.processId != _producer) {
        _retiredProducers.add(_producer);
        if (_retiredProducers.length > 4) _retiredProducers.removeAt(0);
        _lastTimestamp = 0;
      }
      _producer = snapshot.processId;
    }
    if (snapshot.fetcherUpdatedAtMs > 0 &&
        _lastTimestamp > snapshot.fetcherUpdatedAtMs) {
      staleRejected++;
      return;
    }
    if (snapshot.fetcherUpdatedAtMs > 0) {
      _lastTimestamp = snapshot.fetcherUpdatedAtMs;
    }
    final incoming = PlatformTrack.fromSnapshot(snapshot);
    if (incoming == null && _track != null) {
      _pendingEmpty = snapshot;
      _emptyTimer ??= Timer(emptyGrace, () {
        _emptyTimer = null;
        final empty = _pendingEmpty;
        _pendingEmpty = null;
        if (!_disposed && empty != null) _publish(empty, null);
      });
      return;
    }
    _emptyTimer?.cancel();
    _emptyTimer = null;
    _pendingEmpty = null;
    _publish(snapshot, incoming);
  }

  void _publish(MediaSnapshot snapshot, PlatformTrack? incoming) {
    final previous = _track;
    final sameSong =
        previous != null &&
        incoming != null &&
        _text(previous.title) == _text(incoming.title) &&
        (previous.sourceAppId.isEmpty ||
            incoming.sourceAppId.isEmpty ||
            _text(previous.sourceAppId) == _text(incoming.sourceAppId)) &&
        (!_knownArtist(previous.artist) ||
            !_knownArtist(incoming.artist) ||
            _artists(previous.artist) == _artists(incoming.artist)) &&
        PlatformTrack.compatibleDuration(
          previous.durationMs,
          incoming.durationMs,
        );
    if (sameSong) {
      snapshot = snapshot.withMetadata(
        artist: !_knownArtist(incoming.artist) && _knownArtist(previous.artist)
            ? previous.artist
            : incoming.artist,
        sourceAppId: incoming.sourceAppId.isEmpty
            ? previous.sourceAppId
            : incoming.sourceAppId,
      );
      incoming = PlatformTrack.fromSnapshot(snapshot)!;
    }
    final last = _lastSnapshot;
    
    
    
    final previousPosition = sameSong ? estimatedPositionMs() : 0.0;
    final restart =
        sameSong &&
        last != null &&
        last.captureRoute == snapshot.captureRoute &&
        last.timelinePositionKnown != false &&
        snapshot.timelinePositionKnown != false &&
        last.isPlaying &&
        snapshot.isPlaying &&
        previous.durationMs >= 5000 &&
        last.durationMs > 0 &&
        snapshot.durationMs > 0 &&
        snapshot.positionMs >= 0 &&
        snapshot.positionMs < 3500 &&
        previousPosition >= previous.durationMs - 12000 &&
        previousPosition - snapshot.positionMs > 5000 &&
        (previous.trackVersion != incoming!.trackVersion ||
            previousPosition >= previous.durationMs - 2200);
    final lookupDuration = sameSong && incoming!.durationMs <= 0
        ? previous.durationMs
        : incoming?.durationMs ?? 0.0;
    final change = incoming == null
        ? MediaTrackChange.cleared
        : !sameSong
        ? MediaTrackChange.track
        : restart
        ? MediaTrackChange.restart
        : previous.title != incoming.title ||
              previous.artist != incoming.artist ||
              previous.sourceAppId != incoming.sourceAppId ||
              previous.durationMs != lookupDuration
        ? MediaTrackChange.enrichment
        : MediaTrackChange.transport;
    if (incoming != null) {
      incoming = PlatformTrack(
        sourceAppId: incoming.sourceAppId,
        trackVersion: incoming.trackVersion,
        title: incoming.title,
        artist: incoming.artist,
        durationMs: lookupDuration,
        lifecycleId: sameSong && !restart
            ? previous.lifecycleId
            : 'media-session:${++_nextEpoch}',
      );
    }
    _track = incoming;
    _lastSnapshot = snapshot;
    accepted++;
    onUpdate(MediaSessionUpdate(snapshot, incoming, change));
  }

  void dispose() {
    _disposed = true;
    _emptyTimer?.cancel();
    _pendingEmpty = null;
  }
}
