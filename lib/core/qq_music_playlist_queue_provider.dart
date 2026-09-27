import 'dart:convert';
import 'dart:io';

import 'platform_provider.dart';

String? parseQqPlaylistId(String input) {
  final value = input.trim();
  if (RegExp(r'^\d{1,20}$').hasMatch(value)) return value;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !(uri.host == 'y.qq.com' || uri.host.endsWith('.y.qq.com'))) {
    return null;
  }
  final pathMatch = RegExp(
    r'/playlist/(\d{1,20})(?:\.html)?/?$',
  ).firstMatch(uri.path);
  final id =
      pathMatch?.group(1) ??
      uri.queryParameters['disstid'] ??
      uri.queryParameters['id'];
  return id != null && RegExp(r'^\d{1,20}$').hasMatch(id) ? id : null;
}

List<PlatformQueueItem> parseQqPlaylistResponse(Object? decoded) {
  if (decoded is! Map || decoded['code'] != 0) {
    throw const FormatException('QQ 音乐歌单响应无效');
  }
  final lists = decoded['cdlist'];
  if (lists is! List || lists.isEmpty || lists.first is! Map) {
    throw const FormatException('QQ 音乐歌单不存在');
  }
  final songs = (lists.first as Map)['songlist'];
  if (songs is! List || songs.length > 3000) {
    throw const FormatException('QQ 音乐歌单为空或曲目过多');
  }
  final items = <PlatformQueueItem>[];
  for (final song in songs) {
    if (song is! Map) continue;
    final title = (song['songname'] ?? song['name'])?.toString().trim() ?? '';
    if (title.isEmpty) continue;
    final singers = song['singer'];
    final artist = singers is List
        ? singers
              .whereType<Map>()
              .map((singer) => singer['name']?.toString().trim() ?? '')
              .where((name) => name.isNotEmpty)
              .join(' / ')
        : '';
    items.add(
      PlatformQueueItem(
        id: (song['songmid'] ?? song['songid'] ?? items.length).toString(),
        title: title,
        artist: artist,
      ),
    );
  }
  return List.unmodifiable(items);
}

final class QqMusicPlaylistQueueProvider implements QueuePlatformProvider {
  final String Function() playlistInput;
  final HttpClient _client;
  final Uri _endpoint;
  final Future<Object?> Function(Uri)? fetchJson;
  String? _cachedId;
  List<PlatformQueueItem>? _cachedItems;
  DateTime? _cacheExpires;

  QqMusicPlaylistQueueProvider({
    required this.playlistInput,
    HttpClient? client,
    Uri? endpoint,
    this.fetchJson,
  }) : _client = client ?? HttpClient(),
       _endpoint =
           endpoint ??
           Uri.https(
             'c.y.qq.com',
             '/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg',
           );

  @override
  String get id => 'qqMusicPlaylist';

  @override
  bool accepts(PlatformTrack track) =>
      track.platform == MusicPlatform.qqMusic &&
      parseQqPlaylistId(playlistInput()) != null;

  void invalidate() {
    _cachedId = null;
    _cachedItems = null;
    _cacheExpires = null;
  }

  @override
  Future<PlatformQueue?> loadQueue(PlatformTrack track) async {
    final id = parseQqPlaylistId(playlistInput());
    if (id == null || !accepts(track)) return null;
    final items =
        _cachedId == id &&
            _cachedItems != null &&
            _cacheExpires != null &&
            DateTime.now().isBefore(_cacheExpires!)
        ? _cachedItems!
        : await _fetchPlaylist(id);
    _cachedId = id;
    _cachedItems = items;
    _cacheExpires = DateTime.now().add(const Duration(minutes: 5));

    final matches = <int>[];
    final title = _normalized(track.title);
    final artist = _normalizedArtist(track.artist);
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (_normalized(item.title) != title) continue;
      final singers = item.artist.split(' / ').map(_normalizedArtist);
      if (artist.isNotEmpty &&
          artist != '未知歌手' &&
          _normalizedArtist(item.artist) != artist &&
          !singers.contains(artist)) {
        continue;
      }
      matches.add(index);
    }
    return PlatformQueue(
      items: items,
      currentIndex: matches.length == 1 ? matches.single : null,
    );
  }

  Future<List<PlatformQueueItem>> _fetchPlaylist(String id) async {
    final uri = _endpoint.replace(
      queryParameters: {
        'type': '1',
        'json': '1',
        'utf8': '1',
        'onlysong': '0',
        'disstid': id,
        'format': 'json',
      },
    );
    if (fetchJson != null) {
      return parseQqPlaylistResponse(await fetchJson!(uri));
    }
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    request.headers.set(HttpHeaders.refererHeader, 'https://y.qq.com/');
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('QQ 音乐歌单请求失败：${response.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 8))) {
      bytes.addAll(chunk);
      if (bytes.length > 8 * 1024 * 1024) {
        throw const FormatException('QQ 音乐歌单响应过大');
      }
    }
    return parseQqPlaylistResponse(jsonDecode(utf8.decode(bytes)));
  }
}

String _normalized(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

String _normalizedArtist(String text) =>
    _normalized(text.replaceAll(RegExp(r'\s*[/、,;]\s*'), ' / '));
