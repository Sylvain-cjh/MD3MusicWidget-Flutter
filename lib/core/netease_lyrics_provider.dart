import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lyrics_document.dart';
import 'platform_provider.dart';

String _normalize(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
List<String> _artists(Map song) {
  final value = song['artists'] ?? song['ar'];
  return (value is List ? value : const [])
      .whereType<Map>()
      .map((artist) => artist['name']?.toString().trim() ?? '')
      .where((name) => name.isNotEmpty)
      .toList();
}

bool _artistMatches(String wanted, List<String> artists) {
  if (wanted.trim().isEmpty || wanted == '未知歌手') return true;
  final key = _normalize(wanted);
  if (_normalize(artists.join(' / ')) == key) return true;
  final parts = wanted
      .split(RegExp(r'[/&、]'))
      .map(_normalize)
      .where((part) => part.isNotEmpty)
      .toSet();
  final names = artists.map(_normalize).toSet();
  return parts.isNotEmpty && parts.every(names.contains);
}


final class NeteasePublicClient {
  final HttpClient _client;
  final Future<Object?> Function(Uri)? fetchJson;
  NeteasePublicClient({HttpClient? client, this.fetchJson})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 5)
            ..maxConnectionsPerHost = 2);

  Future<Object?> get(String path, Map<String, String> query) async {
    final uri = Uri.https('music.163.com', path, query);
    if (fetchJson != null) return fetchJson!(uri);
    HttpClientRequest? request;
    final deadline = Timer(
      const Duration(seconds: 8),
      () => request?.abort(TimeoutException('网易云歌词请求超时')),
    );
    try {
      request = await _client.getUrl(uri).timeout(const Duration(seconds: 5));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.refererHeader, 'https://music.163.com/');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 MD3MusicWidget',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('网易云公开接口不可用：${response.statusCode}');
      }
      final bytes = BytesBuilder(copy: false);
      var size = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 5))) {
        size += chunk.length;
        if (size > 4 * 1024 * 1024) throw const FormatException('网易云响应过大');
        bytes.add(chunk);
      }
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } catch (_) {
      request?.abort();
      rethrow;
    } finally {
      deadline.cancel();
    }
  }

  void close() => _client.close(force: true);
}

final class NeteaseLyricsProvider
    implements LyricsPlatformProvider, RetryableLyricsProvider {
  static const providerId = 'neteaseCloud';
  final NeteasePublicClient client;
  final LyricsPlatformProvider fallback;
  final LinkedHashMap<String, (LyricsDocument?, DateTime)> _cache =
      LinkedHashMap();
  final Map<String, Future<LyricsDocument?>> _pending = {};
  NeteaseLyricsProvider({required this.fallback, NeteasePublicClient? client})
    : client = client ?? NeteasePublicClient();
  @override
  String get id => providerId;
  @override
  bool accepts(PlatformTrack track) => track.title.trim().isNotEmpty;

  @override
  void invalidateMiss(PlatformTrack track) {
    final key =
        '${_normalize(track.title)}|${_normalize(track.artist)}|${track.durationMs.isFinite ? track.durationMs.round() : 0}';
    if (_cache[key]?.$1 == null) _cache.remove(key);
    if (fallback is RetryableLyricsProvider) {
      (fallback as RetryableLyricsProvider).invalidateMiss(track);
    }
  }

  @override
  Future<LyricsDocument?> loadLyrics(PlatformTrack track) {
    if (!accepts(track)) return Future.value(null);
    final key =
        '${_normalize(track.title)}|${_normalize(track.artist)}|${track.durationMs.isFinite ? track.durationMs.round() : 0}';
    return _pending.putIfAbsent(
      key,
      () => _load(track, key).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<LyricsDocument?> _load(PlatformTrack track, String key) async {
    final cached = _cache[key];
    if (cached != null && DateTime.now().isBefore(cached.$2)) {
      _cache.remove(key);
      _cache[key] = cached;
      if (cached.$1 != null) return cached.$1;
    } else {
      LyricsDocument? document;
      var failed = false;
      try {
        document = await _loadPublic(track);
      } catch (_) {
        failed = true;
      }
      _cache.remove(key);
      _cache[key] = (
        document,
        DateTime.now().add(
          document != null
              ? const Duration(hours: 2)
              : failed
              ? const Duration(minutes: 1)
              : const Duration(minutes: 5),
        ),
      );
      while (_cache.length > 8) {
        _cache.remove(_cache.keys.first);
      }
      if (document != null) return document;
    }
    return (await fallback.loadLyrics(
      track,
    ))?.withSourceProviderId(fallback.id);
  }

  Future<LyricsDocument?> _loadPublic(PlatformTrack track) async {
    final query = track.artist.isEmpty || track.artist == '未知歌手'
        ? track.title
        : '${track.title} ${track.artist}';
    final json = await client.get('/api/search/get', {
      's': query,
      'type': '1',
      'limit': '20',
      'offset': '0',
    });
    if (json is! Map || json['code'] != 200 || json['result'] is! Map) {
      return null;
    }
    final songs = (json['result'] as Map)['songs'];
    if (songs is! List) return null;
    final byId = <String, double>{};
    for (final song in songs.whereType<Map>()) {
      final id = song['id']?.toString() ?? '';
      if (!RegExp(r'^\d+$').hasMatch(id) ||
          _normalize(song['name']?.toString() ?? '') !=
              _normalize(track.title) ||
          !_artistMatches(track.artist, _artists(song))) {
        continue;
      }
      final value = song['duration'] ?? song['dt'];
      final duration = value is num && value.isFinite ? value : null;
      final difference =
          duration == null ||
              !track.durationMs.isFinite ||
              track.durationMs <= 0
          ? 0.0
          : (duration.toDouble() - track.durationMs).abs();
      if (difference > 12000) continue;
      byId[id] = difference;
    }
    final candidates = [
      for (final entry in byId.entries) (entry.value, entry.key),
    ];
    candidates.sort((a, b) => a.$1.compareTo(b.$1));
    if (candidates.isEmpty ||
        (candidates.length > 1 &&
            candidates[0].$1 == candidates[1].$1 &&
            candidates[0].$2 != candidates[1].$2)) {
      return null;
    }
    final lyric = await client.get('/api/song/lyric', {
      'id': candidates.first.$2,
      'lv': '-1',
      'kv': '-1',
      'tv': '-1',
    });
    if (lyric is! Map || lyric['code'] != 200 || lyric['lrc'] is! Map) {
      return null;
    }
    final text = (lyric['lrc'] as Map)['lyric'];
    if (text is! String || text.trim().isEmpty) return null;
    final document = LyricsDocument.parseLrc(text);
    return document.isEmpty ? null : document.withSourceProviderId(providerId);
  }
}
