import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lyrics_document.dart';
import 'lyrics_http_client.dart';
import 'lyrics_primary_attempt.dart';
import 'lrclib_lyrics_provider.dart';
import 'platform_provider.dart';

final class QqMusicLyricsProvider
    implements LyricsPlatformProvider, RetryableLyricsProvider {
  static const providerId = 'qqMusic';
  static const _maxBytes = 2 * 1024 * 1024;
  final HttpClient _client;
  final LrclibLyricsProvider _fallback;
  final Uri _searchEndpoint;
  final Uri _lyricEndpoint;
  final Duration primaryBudget;
  final Map<String, Future<LyricsDocument?>> _pending = {};
  final LinkedHashMap<String, (LyricsDocument?, DateTime)> _cache =
      LinkedHashMap<String, (LyricsDocument?, DateTime)>();

  QqMusicLyricsProvider({
    HttpClient? client,
    required this._fallback,
    Uri? searchEndpoint,
    Uri? lyricEndpoint,
    this.primaryBudget = const Duration(seconds: 4),
  }) : _client = directLyricsHttpClient(client),
       _searchEndpoint =
           searchEndpoint ??
           Uri.https('c.y.qq.com', '/soso/fcgi-bin/client_search_cp'),
       _lyricEndpoint =
           lyricEndpoint ??
           Uri.https('c.y.qq.com', '/lyric/fcgi-bin/fcg_query_lyric_new.fcg');

  @override
  String get id => providerId;

  @override
  bool accepts(PlatformTrack track) => track.title.trim().isNotEmpty;

  @override
  void invalidateMiss(PlatformTrack track) {
    final key =
        '${_key(track.title)}|${_key(track.artist)}|${(track.durationMs / 1000).round()}';
    if (_cache[key]?.$1 == null) _cache.remove(key);
    _fallback.invalidateMiss(track);
  }

  @override
  Future<LyricsDocument?> loadLyrics(PlatformTrack track) {
    if (!accepts(track)) return Future.value(null);
    final key =
        '${_key(track.title)}|${_key(track.artist)}|${(track.durationMs / 1000).round()}';
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
      if (cached.$1 != null) {
        return cached.$1;
      }
    } else {
      try {
        final attempt = LyricsPrimaryAttempt(primaryBudget);
        final fromQq = (await attempt.run(
          () => _loadFromQq(track, attempt),
        ))?.withSourceProviderId(providerId);
        _remember(
          key,
          fromQq,
          fromQq == null
              ? const Duration(minutes: 5)
              : const Duration(hours: 2),
        );
        if (fromQq != null) return fromQq;
      } catch (_) {
        _remember(key, null, const Duration(minutes: 1));
      }
    }
    final fallback = (await _fallback.loadLyrics(
      track,
    ))?.withSourceProviderId(_fallback.id);
    if (fallback != null && !fallback.isEmpty) {
      _remember(key, fallback, const Duration(hours: 2));
      return fallback;
    }
    return null;
  }

  void _remember(String key, LyricsDocument? document, Duration duration) {
    _cache.remove(key);
    _cache[key] = (document, DateTime.now().add(duration));
    if (_cache.length > 8) _cache.remove(_cache.keys.first);
  }

  Future<LyricsDocument?> _loadFromQq(
    PlatformTrack track,
    LyricsPrimaryAttempt attempt,
  ) async {
    final title = track.title.trim();
    final artist = track.artist.trim();
    final query = artist.isEmpty || artist == '未知歌手' ? title : '$title $artist';
    final search = await _getJson(
      _searchEndpoint.replace(
        queryParameters: {'format': 'json', 'p': '1', 'n': '20', 'w': query},
      ),
      attempt,
    );
    if (search is! Map) return null;
    final data = search['data'];
    if (data is! Map || data['song'] is! Map) return null;
    final songs = (data['song'] as Map)['list'];
    if (songs is! List) return null;
    final matches = <(int, String)>[];
    for (final item in songs) {
      if (item is! Map) continue;
      final songTitle = item['songname']?.toString() ?? '';
      final songMid = item['songmid']?.toString() ?? '';
      if (songMid.isEmpty || !_titleMatches(title, songTitle)) continue;
      final singers = item['singer'];
      final artistMatches =
          artist.isEmpty ||
          artist == '未知歌手' ||
          (singers is List &&
              singers.whereType<Map>().any(
                (singer) =>
                    _artistMatches(artist, singer['name']?.toString() ?? ''),
              ));
      if (!artistMatches) continue;
      final duration = (item['interval'] as num?)?.toDouble();
      final durationDifference = duration == null || track.durationMs <= 0
          ? 0.0
          : (duration - track.durationMs / 1000).abs();
      if (durationDifference > 12) continue;
      final score =
          (_key(title) == _key(songTitle) ? 4 : 0) +
          (durationDifference <= 3 ? 2 : 0) +
          (artistMatches ? 1 : 0);
      matches.add((score, songMid));
    }
    matches.sort((a, b) => b.$1.compareTo(a.$1));
    if (matches.isEmpty) return null;
    final lyric = await _getJson(
      _lyricEndpoint.replace(
        queryParameters: {
          'songmid': matches.first.$2,
          'format': 'json',
          'nobase64': '1',
          'g_tk': '5381',
        },
      ),
      attempt,
    );
    if (lyric is! Map || lyric['retcode'] != 0) return null;
    final lrc = lyric['lyric']?.toString() ?? '';
    if (lrc.trim().isEmpty) return null;
    final document = LyricsDocument.parseLrc(_decodeEntities(lrc));
    return document.isEmpty ? null : document;
  }

  Future<dynamic> _getJson(Uri uri, LyricsPrimaryAttempt attempt) async {
    final request = await attempt.open(_client, uri);
    try {
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 MD3MusicWidget/0.10.1',
      );
      request.headers.set(HttpHeaders.refererHeader, 'https://y.qq.com/');
      final response = await request.close().timeout(attempt.remaining);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().timeout(attempt.remaining);
        return null;
      }
      final builder = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.timeout(attempt.remaining)) {
        total += chunk.length;
        if (total > _maxBytes) {
          throw const FormatException('QQ lyric response is too large');
        }
        builder.add(chunk);
      }
      return jsonDecode(utf8.decode(builder.takeBytes()));
    } catch (_) {
      request.abort();
      rethrow;
    } finally {
      attempt.release(request);
    }
  }

  static String _key(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );

  static bool _titleMatches(String wanted, String candidate) {
    final a = _key(wanted);
    final b = _key(candidate);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    return shorter.length >= 4 &&
        shorter.length / longer.length >= 0.7 &&
        longer.contains(shorter);
  }

  static bool _artistMatches(String wanted, String candidate) {
    final a = _key(wanted);
    final b = _key(candidate);
    return a.isNotEmpty &&
        b.isNotEmpty &&
        (a == b ||
            (a.length >= 3 && b.contains(a)) ||
            (b.length >= 3 && a.contains(b)));
  }

  static String _decodeEntities(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
