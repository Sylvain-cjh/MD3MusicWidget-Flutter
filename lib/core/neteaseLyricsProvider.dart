import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lyricsDocument.dart';
import 'lyricsHttpClient.dart';
import 'lyricsPrimaryAttempt.dart';
import 'lyricsSongMatcher.dart';
import 'platformProvider.dart';

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


final class NeteasePublicClient {
  final HttpClient _client;
  final Future<Object?> Function(Uri)? fetchJson;
  NeteasePublicClient({HttpClient? client, this.fetchJson})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 5)
            ..maxConnectionsPerHost = 2);

  Future<Object?> get(
    String path,
    Map<String, String> query, {
    LyricsPrimaryAttempt? attempt,
  }) async {
    final uri = Uri.https('music.163.com', path, query);
    if (fetchJson != null) return fetchJson!(uri);
    HttpClientRequest? request;
    final deadline = Timer(
      const Duration(seconds: 8),
      () => request?.abort(TimeoutException('网易云歌词请求超时')),
    );
    try {
      request = attempt == null
          ? await _client.getUrl(uri).timeout(const Duration(seconds: 5))
          : await attempt.open(_client, uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.refererHeader, 'https://music.163.com/');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 MD3MusicWidget',
      );
      final response = await request.close().timeout(
        attempt?.remaining ?? const Duration(seconds: 5),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('网易云公开接口不可用：${response.statusCode}');
      }
      final bytes = BytesBuilder(copy: false);
      var size = 0;
      await for (final chunk in response.timeout(
        attempt?.remaining ?? const Duration(seconds: 5),
      )) {
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
      if (request != null) attempt?.release(request);
    }
  }

  void close() => _client.close(force: true);
  void useDirectConnection() => directLyricsHttpClient(_client);
}

final class NeteaseLyricsProvider
    implements
        LyricsPlatformProvider,
        RetryableLyricsProvider,
        BackgroundWordTimingLyricsProvider,
        ExhaustiveLyricsProvider {
  static const providerId = 'neteaseCloud';
  final NeteasePublicClient client;
  final LyricsPlatformProvider fallback;
  final WordTimingLyricsProvider? wordFallback;
  final LinkedHashMap<String, (LyricsDocument?, DateTime)> _cache =
      LinkedHashMap();
  final Map<String, Future<LyricsDocument?>> _pending = {};
  final Duration primaryBudget;
  NeteaseLyricsProvider({
    required this.fallback,
    this.wordFallback,
    NeteasePublicClient? client,
    this.primaryBudget = const Duration(seconds: 4),
  }) : client = client ?? NeteasePublicClient() {
    this.client.useDirectConnection();
  }
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

  @override
  Future<LyricsDocument?> upgradeWordTiming(PlatformTrack track) {
    final key =
        '${_normalize(track.title)}|${_normalize(track.artist)}|${track.durationMs.isFinite ? track.durationMs.round() : 0}';
    return _pending.putIfAbsent(
      'words|$key',
      () => Future<LyricsDocument?>(() async {
        try {
          final cached = _cache[key]?.$1;
          if (cached?.isWordTimed == true) return cached;
          if (wordFallback != null &&
              cached != null &&
              cached.wordTimingRetryAt?.isAfter(DateTime.now()) == true) {
            return await wordFallback!.upgradeWordTiming(track);
          }
          final attempt = LyricsPrimaryAttempt(primaryBudget);
          final fresh = await attempt.run(() => _loadPublic(track, attempt));
          if (fresh != null) {
            _cache[key] = (fresh, DateTime.now().add(const Duration(hours: 2)));
            while (_cache.length > 8) {
              _cache.remove(_cache.keys.first);
            }
          }
          return fresh;
        } finally {
          _pending.remove('words|$key');
        }
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
        final attempt = LyricsPrimaryAttempt(primaryBudget);
        document = await attempt.run(() => _loadPublic(track, attempt));
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
    final document = await fallback.loadLyrics(track);
    final sourced = document == null
        ? null
        : document.sourceProviderId.isEmpty
        ? document.withSourceProviderId(fallback.id)
        : document;
    final resolved = sourced?.isWordTimed == true
        ? sourced
        : sourced?.withWordTimingRetryAt(
            DateTime.now().add(const Duration(minutes: 30)),
          );
    if (resolved != null && !resolved.isEmpty) {
      _cache.remove(key);
      _cache[key] = (resolved, DateTime.now().add(const Duration(hours: 2)));
      while (_cache.length > 8) {
        _cache.remove(_cache.keys.first);
      }
      return resolved;
    }
    return null;
  }

  Future<LyricsDocument?> _loadPublic(
    PlatformTrack track,
    LyricsPrimaryAttempt attempt,
  ) async {
    final query = track.artist.isEmpty || track.artist == '未知歌手'
        ? track.title
        : '${track.title} ${track.artist}';
    final json = await client.get('/api/search/get', {
      's': query,
      'type': '1',
      'limit': '20',
      'offset': '0',
    }, attempt: attempt);
    if (json is! Map || json['code'] != 200 || json['result'] is! Map) {
      return null;
    }
    final songs = (json['result'] as Map)['songs'];
    if (songs is! List) return null;
    final byId = <String, int>{};
    final matcher = LyricsSongMatcher(track);
    for (final song in songs.whereType<Map>()) {
      final id = song['id']?.toString() ?? '';
      if (!RegExp(r'^\d+$').hasMatch(id)) {
        continue;
      }
      final value = song['duration'] ?? song['dt'];
      final duration = value is num && value.isFinite ? value : null;
      final score = matcher.score(
        title: song['name']?.toString() ?? '',
        artists: _artists(song),
        durationMs: duration?.toDouble(),
      );
      if (score != null) byId[id] = score;
    }
    final candidates = [
      for (final entry in byId.entries) (entry.value, entry.key),
    ];
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    if (candidates.isEmpty ||
        (candidates.length > 1 &&
            candidates[0].$1 == candidates[1].$1 &&
            candidates[0].$2 != candidates[1].$2)) {
      return null;
    }
    Object? lyric;
    try {
      final wordAttempt = attempt.slice(
        const Duration(milliseconds: 1600),
        reserve: const Duration(milliseconds: 100),
      );
      lyric = await wordAttempt.run(
        () => client.get('/api/song/lyric/v1', {
          'id': candidates.first.$2,
          'cp': 'false',
          'lv': '0',
          'kv': '0',
          'tv': '0',
          'rv': '0',
          'yv': '0',
          'ytv': '0',
          'yrv': '0',
        }, attempt: wordAttempt),
      );
    } catch (_) {
      
    }
    final document = await _parsePayload(lyric);
    if (document != null) return document;
    lyric = await client.get('/api/song/lyric', {
      'id': candidates.first.$2,
      'lv': '-1',
      'kv': '-1',
      'tv': '-1',
    }, attempt: attempt);
    return _parsePayload(lyric);
  }

  Future<LyricsDocument?> _parsePayload(Object? lyric) async {
    if (lyric is! Map || lyric['code'] != 200) {
      return null;
    }
    for (final key in const ['yrc', 'klyric']) {
      final timed = lyric[key];
      if (timed is Map && timed['lyric'] is String) {
        try {
          final words = await LyricsDocument.parseAsync(
            timed['lyric'] as String,
            format: 'yrc',
          );
          if (words.isWordTimed) return words.withSourceProviderId(providerId);
        } on FormatException {
          
        }
      }
    }
    if (lyric['lrc'] is! Map) return null;
    final text = (lyric['lrc'] as Map)['lyric'];
    if (text is! String || text.trim().isEmpty) return null;
    try {
      final document = await LyricsDocument.parseAsync(text);
      return document.isEmpty
          ? null
          : document
                .withSourceProviderId(providerId)
                .withWordTimingRetryAt(
                  DateTime.now().add(const Duration(minutes: 30)),
                );
    } on FormatException {
      return null;
    }
  }
}
