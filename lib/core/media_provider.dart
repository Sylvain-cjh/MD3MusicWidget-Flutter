import 'dart:typed_data';

abstract final class MediaCapability {
  static const int metadata = 1 << 0;
  static const int artwork = 1 << 1;
  static const int timeline = 1 << 2;
  static const int playPause = 1 << 3;
  static const int previous = 1 << 4;
  static const int next = 1 << 5;
  static const int seek = 1 << 6;
  static const int spectrum = 1 << 7;

  static const int smtcDefault =
      metadata |
      artwork |
      timeline |
      playPause |
      previous |
      next |
      seek |
      spectrum;

  static bool supports(int capabilities, int capability) =>
      capabilities & capability != 0;
}

final class MediaSnapshot {
  final int processId;
  final String title;
  final String artist;
  final String trackVersion;
  final bool isPlaying;
  final String coverVersion;
  final String legacyCoverBase64;
  final double positionMs;
  final double durationMs;
  final int timelineUpdatedAtMs;
  final int fetcherUpdatedAtMs;
  final int capabilities;

  const MediaSnapshot({
    required this.processId,
    required this.title,
    required this.artist,
    required this.trackVersion,
    required this.isPlaying,
    required this.coverVersion,
    required this.legacyCoverBase64,
    required this.positionMs,
    required this.durationMs,
    required this.timelineUpdatedAtMs,
    required this.fetcherUpdatedAtMs,
    required this.capabilities,
  });

  factory MediaSnapshot.fromJson(Map<String, dynamic> data) => MediaSnapshot(
    processId: (data['processId'] as num?)?.toInt() ?? 0,
    title: data['title']?.toString() ?? '未知歌曲',
    artist: data['artist']?.toString() ?? '未知歌手',
    trackVersion: data['trackVersion']?.toString() ?? '',
    isPlaying: data['isPlaying'] == true,
    coverVersion: data['coverVersion']?.toString() ?? '',
    legacyCoverBase64: data['coverBase64']?.toString() ?? '',
    positionMs: (data['positionMs'] as num?)?.toDouble() ?? 0.0,
    durationMs: (data['durationMs'] as num?)?.toDouble() ?? 0.0,
    timelineUpdatedAtMs: (data['timelineUpdatedAtMs'] as num?)?.toInt() ?? 0,
    fetcherUpdatedAtMs: (data['fetcherUpdatedAtMs'] as num?)?.toInt() ?? 0,
    capabilities:
        (data['capabilities'] as num?)?.toInt() ?? MediaCapability.smtcDefault,
  );
}

sealed class MediaProviderEvent {
  const MediaProviderEvent();
}

final class MediaSnapshotEvent extends MediaProviderEvent {
  final MediaSnapshot snapshot;

  const MediaSnapshotEvent(this.snapshot);
}

final class MediaSpectrumEvent extends MediaProviderEvent {
  final Uint8List packet;

  const MediaSpectrumEvent(this.packet);
}

final class MediaHeartbeatEvent extends MediaProviderEvent {
  const MediaHeartbeatEvent();
}

final class MediaDisconnectedEvent extends MediaProviderEvent {
  final Object? error;

  const MediaDisconnectedEvent([this.error]);
}

abstract interface class MediaProvider {
  Stream<MediaProviderEvent> get events;
  bool get isConnected;

  Future<bool> connect();
  void setSpectrumEnabled(bool enabled);
  Future<void> close();
}
