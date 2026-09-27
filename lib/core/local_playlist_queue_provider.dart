import 'dart:convert';
import 'dart:io';

import 'platform_provider.dart';

final class LocalPlaylistQueueProvider implements QueuePlatformProvider {
  final String Function() playlistPath;

  const LocalPlaylistQueueProvider(this.playlistPath);

  @override
  String get id => 'localPlaylist';

  @override
  bool accepts(PlatformTrack track) => playlistPath().trim().isNotEmpty;

  @override
  Future<PlatformQueue?> loadQueue(PlatformTrack track) async {
    final path = playlistPath().trim();
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) throw const FileSystemException('播放列表文件不存在');
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('播放列表文件超过 2 MiB');
    }
    final contents = await file.readAsString();
    final lowerPath = path.toLowerCase();
    final items = lowerPath.endsWith('.json')
        ? parsePlaylistJson(contents)
        : parseM3uPlaylist(contents);
    if (items.isEmpty) return PlatformQueue(items: items);
    final title = _normalize(track.title);
    final artist = _normalize(track.artist);
    final matches = <int>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (_normalize(item.title) != title) continue;
      if (item.artist.isNotEmpty && _normalize(item.artist) != artist) continue;
      matches.add(i);
    }
    return PlatformQueue(
      items: items,
      currentIndex: matches.length == 1 ? matches.single : null,
    );
  }
}

String _normalize(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

List<PlatformQueueItem> parsePlaylistJson(String contents) {
  final decoded = jsonDecode(contents);
  final Object? rawItems = decoded is Map ? decoded['tracks'] : decoded;
  if (rawItems is! List) throw const FormatException('JSON 需要 tracks 数组');
  if (rawItems.length > 2000) throw const FormatException('播放列表超过 2000 首');
  final items = <PlatformQueueItem>[];
  for (final raw in rawItems) {
    if (raw is! Map) continue;
    final title = raw['title']?.toString().trim() ?? '';
    final artist = raw['artist']?.toString().trim() ?? '';
    if (title.isEmpty) continue;
    items.add(
      PlatformQueueItem(
        id: raw['id']?.toString() ?? '${items.length}',
        title: title,
        artist: artist,
      ),
    );
  }
  return List.unmodifiable(items);
}

List<PlatformQueueItem> parseM3uPlaylist(String contents) {
  final lines = const LineSplitter().convert(
    contents.replaceFirst('\uFEFF', ''),
  );
  if (lines.length > 6000) throw const FormatException('播放列表行数过多');
  final items = <PlatformQueueItem>[];
  String? pendingTitle;
  String pendingArtist = '';
  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF:')) {
      final comma = line.indexOf(',');
      if (comma < 0) continue;
      final label = line.substring(comma + 1).trim();
      final split = label.indexOf(' - ');
      pendingArtist = split < 0 ? '' : label.substring(0, split).trim();
      pendingTitle = split < 0 ? label : label.substring(split + 3).trim();
      continue;
    }
    if (line.isEmpty || line.startsWith('#')) continue;
    final filename = _filenameTitle(line);
    final separator = filename.indexOf(' - ');
    final title =
        pendingTitle ??
        (separator < 0 ? filename : filename.substring(separator + 3).trim());
    final artist = pendingTitle == null && separator >= 0
        ? filename.substring(0, separator).trim()
        : pendingArtist;
    if (title.isNotEmpty) {
      items.add(
        PlatformQueueItem(id: '${items.length}', title: title, artist: artist),
      );
    }
    pendingTitle = null;
    pendingArtist = '';
    if (items.length > 2000) throw const FormatException('播放列表超过 2000 首');
  }
  return List.unmodifiable(items);
}

String _filenameTitle(String path) {
  final slash = path.replaceAll('\\', '/').split('/').last;
  final dot = slash.lastIndexOf('.');
  return (dot > 0 ? slash.substring(0, dot) : slash).trim();
}
