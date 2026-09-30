import 'dart:convert';

import 'lyrics_document.dart';
import 'media_provider.dart';

enum MusicPlatform {
  qqMusic,
  neteaseCloud,
  spotify,
  appleMusic,
  kugou,
  kuwo,
  other,
}

extension MusicPlatformLabel on MusicPlatform {
  String get label => switch (this) {
    MusicPlatform.qqMusic => 'QQ 音乐',
    MusicPlatform.neteaseCloud => '网易云音乐',
    MusicPlatform.spotify => 'Spotify',
    MusicPlatform.appleMusic => 'Apple Music',
    MusicPlatform.kugou => '酷狗音乐',
    MusicPlatform.kuwo => '酷我音乐',
    MusicPlatform.other => '系统播放器',
  };
}

MusicPlatform identifyMusicPlatform(String sourceAppId) {
  final source = sourceAppId.toLowerCase();
  if (source.contains('qqmusic')) return MusicPlatform.qqMusic;
  if (source.contains('cloudmusic')) return MusicPlatform.neteaseCloud;
  if (source.contains('spotify')) return MusicPlatform.spotify;
  if (source.contains('applemusic')) return MusicPlatform.appleMusic;
  if (source.contains('kugou')) return MusicPlatform.kugou;
  if (source.contains('kuwo') || source.contains('kwmusic')) {
    return MusicPlatform.kuwo;
  }
  return MusicPlatform.other;
}

final class PlatformTrack {
  final String sourceAppId;
  final String trackVersion;
  final String title;
  final String artist;
  final double durationMs;

  const PlatformTrack({
    required this.sourceAppId,
    required this.trackVersion,
    required this.title,
    required this.artist,
    required this.durationMs,
  });

  static PlatformTrack? fromSnapshot(MediaSnapshot snapshot) {
    final source = snapshot.sourceAppId.trim();
    final title = snapshot.title.trim();
    if (title.isEmpty ||
        title == '暂无音乐播放' ||
        title == '未在播放' ||
        title == '未知歌曲') {
      return null;
    }
    return PlatformTrack(
      sourceAppId: source,
      trackVersion: snapshot.trackVersion,
      title: snapshot.title,
      artist: snapshot.artist,
      durationMs: snapshot.durationMs.isFinite ? snapshot.durationMs : 0,
    );
  }

  String get identity => jsonEncode([
    sourceAppId.toLowerCase(),
    trackVersion,
    title,
    artist,
    durationMs.round(),
  ]);

  String get queueIdentity =>
      jsonEncode([sourceAppId.toLowerCase(), title.trim(), artist.trim()]);

  MusicPlatform get platform => identifyMusicPlatform(sourceAppId);
}

final class PlatformQueueItem {
  final String id;
  final String title;
  final String artist;

  const PlatformQueueItem({
    required this.id,
    required this.title,
    required this.artist,
  });
}

final class PlatformQueue {
  final List<PlatformQueueItem> items;
  final int? currentIndex;

  PlatformQueue({required List<PlatformQueueItem> items, this.currentIndex})
    : items = List.unmodifiable(items);

  PlatformQueueItem? nextItem({bool wrap = false}) {
    final index = currentIndex;
    if (index == null || items.isEmpty) return null;
    final next = index + 1;
    if (next < items.length) return items[next];
    return wrap ? items.first : null;
  }
}

abstract interface class MusicPlatformProvider {
  String get id;
  bool accepts(PlatformTrack track);
}

abstract interface class LyricsPlatformProvider
    implements MusicPlatformProvider {
  Future<LyricsDocument?> loadLyrics(PlatformTrack track);
}

abstract interface class QueuePlatformProvider
    implements MusicPlatformProvider {
  Future<PlatformQueue?> loadQueue(PlatformTrack track);
}

final class PlatformProviderRegistry {
  final List<MusicPlatformProvider> _providers = [];
  int _revision = 0;

  int get revision => _revision;

  void register(MusicPlatformProvider provider) {
    _providers.removeWhere((existing) => existing.id == provider.id);
    _providers.add(provider);
    _revision++;
  }

  void unregister(String id) {
    _providers.removeWhere((provider) => provider.id == id);
    _revision++;
  }

  LyricsPlatformProvider? lyricsFor(PlatformTrack track, {String? providerId}) {
    for (final provider in _providers) {
      if (provider is LyricsPlatformProvider &&
          (providerId == null || provider.id == providerId) &&
          provider.accepts(track)) {
        return provider;
      }
    }
    return null;
  }

  QueuePlatformProvider? queueFor(PlatformTrack track) {
    for (final provider in _providers) {
      if (provider is QueuePlatformProvider && provider.accepts(track)) {
        return provider;
      }
    }
    return null;
  }
}
