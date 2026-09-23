import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lyrics_document.dart';
import 'platform_provider.dart';

final class LrclibLyricsProvider implements LyricsPlatformProvider {
  static const String providerId = 'lrclib';
  static const int _maximumResponseBytes = 2 * 1024 * 1024;
  final HttpClient _client;
  final Uri _endpoint;
  final LinkedHashMap<String, (LyricsDocument?, DateTime)> _cache =
      LinkedHashMap<String, (LyricsDocument?, DateTime)>();
  Future<void> _tail = Future<void>.value();
  DateTime _nextRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  LrclibLyricsProvider({HttpClient? client, Uri? endpoint})
    : _client = client ?? HttpClient(),
      _endpoint = endpoint ?? Uri.https('lrclib.net', '/api/get');

  @override
  String get id => providerId;

  @override
  bool accepts(PlatformTrack track) => track.title.trim().isNotEmpty;

  @override
  Future<LyricsDocument?> loadLyrics(PlatformTrack track) {
    if (!accepts(track)) return Future<LyricsDocument?>.value();
    final key =
        '${track.title.trim().toLowerCase()}|'
        '${track.artist.trim().toLowerCase()}|${(track.durationMs / 1000).round()}';
    final cached = _cache[key];
    if (cached != null && DateTime.now().isBefore(cached.$2)) {
      return Future<LyricsDocument?>.value(cached.$1);
    }
    final request = _tail.then((_) async {
      return _load(track, key);
    });
    _tail = request.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    return request;
  }

  Future<LyricsDocument?> _load(PlatformTrack track, String key) async {
    final parameters = <String, String>{
      'track_name': track.title.trim(),
      'artist_name': track.artist.trim(),
    };
    final seconds = (track.durationMs / 1000).round();
    if (seconds >= 1 && seconds <= 3600) {
      parameters['duration'] = seconds.toString();
    }
    final artistKnown =
        track.artist.trim().isNotEmpty &&
        track.artist.trim() != '未知歌手' &&
        track.artist.trim() != '无媒体会话';
    final exact = artistKnown
        ? await _requestJson(_endpoint.replace(queryParameters: parameters))
        : null;
    final exactCandidate = exact is Map
        ? Map<String, dynamic>.from(exact)
        : null;
    final exactDocument = exactCandidate == null
        ? null
        : _documentIfMatching(track, exactCandidate);
    if (exactDocument != null) {
      _remember(key, exactDocument, const Duration(hours: 2));
      return exactDocument;
    }

    final query = artistKnown
        ? '${track.title.trim()} ${track.artist.trim()}'
        : track.title.trim();
    final searchUri = _endpoint.replace(
      path: _endpoint.path.replaceFirst(RegExp(r'/get/?$'), '/search'),
      queryParameters: {'q': query},
    );
    final results = await _requestJson(searchUri);
    if (results is List) {
      final candidates = <(int, LyricsDocument)>[];
      for (final item in results) {
        if (item is! Map) continue;
        final data = Map<String, dynamic>.from(item);
        final document = _documentIfMatching(track, data);
        if (document == null) continue;
        candidates.add((_matchScore(track, data), document));
      }
      candidates.sort((a, b) => b.$1.compareTo(a.$1));
      if (candidates.isNotEmpty) {
        final document = candidates.first.$2;
        _remember(key, document, const Duration(hours: 2));
        return document;
      }
    }
    _remember(key, null, const Duration(minutes: 5));
    return null;
  }

  Future<dynamic> _requestJson(Uri uri) async {
    final wait = _nextRequestAt.difference(DateTime.now());
    if (wait > const Duration(seconds: 2)) {
      throw const HttpException('LRCLIB rate limited the request');
    }
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 4));
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'MD3MusicWidget/0.10.0 (https://github.com/Sylvain-cjh/MD3-MusicWidget)',
    );
    try {
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode == HttpStatus.notFound) {
        await response.drain<void>().timeout(const Duration(seconds: 2));
        return null;
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        final retrySeconds = int.tryParse(
          response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
        );
        _nextRequestAt = DateTime.now().add(
          Duration(seconds: (retrySeconds ?? 30).clamp(1, 300)),
        );
        await response.drain<void>().timeout(const Duration(seconds: 2));
        throw const HttpException('LRCLIB rate limited the request');
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().timeout(const Duration(seconds: 2));
        throw HttpException('LRCLIB returned HTTP ${response.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      int total = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 5))) {
        total += chunk.length;
        if (total > _maximumResponseBytes) {
          throw const FormatException('Lyric response is too large');
        }
        builder.add(chunk);
      }
      return jsonDecode(utf8.decode(builder.takeBytes()));
    } finally {
      final nextAllowed = DateTime.now().add(const Duration(milliseconds: 300));
      if (_nextRequestAt.isBefore(nextAllowed)) _nextRequestAt = nextAllowed;
    }
  }

  LyricsDocument? _documentIfMatching(
    PlatformTrack track,
    Map<String, dynamic> data,
  ) {
    final responseTitle = data['trackName']?.toString().trim() ?? '';
    final responseArtist = data['artistName']?.toString().trim() ?? '';
    if (!_matchesTitle(track.title, responseTitle) ||
        !_matchesArtist(track.artist, responseArtist)) {
      return null;
    }
    final responseDuration = (data['duration'] as num?)?.toDouble();
    if (track.durationMs > 0 &&
        responseDuration != null &&
        (responseDuration - track.durationMs / 1000).abs() > 12) {
      return null;
    }
    final synced = data['syncedLyrics']?.toString() ?? '';
    final plain = data['plainLyrics']?.toString() ?? '';
    final document = synced.trim().isNotEmpty
        ? LyricsDocument.parseLrc(synced)
        : LyricsDocument(lines: const [], plainText: plain.trim());
    return document.isEmpty ? null : document;
  }

  static String _matchKey(String text) => text.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );

  static bool _matchesTitle(String wanted, String candidate) {
    final a = _matchKey(wanted);
    final b = _matchKey(candidate);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    return shorter.length >= 4 &&
        shorter.length / longer.length >= 0.7 &&
        longer.contains(shorter);
  }

  static bool _matchesArtist(String wanted, String candidate) {
    if (wanted == '未知歌手' || wanted == '无媒体会话') return true;
    final a = _matchKey(wanted);
    final b = _matchKey(candidate);
    return a.isEmpty ||
        b.isEmpty ||
        a == b ||
        (a.length >= 3 && b.contains(a)) ||
        (b.length >= 3 && a.contains(b));
  }

  static int _matchScore(PlatformTrack track, Map<String, dynamic> data) {
    final titleExact =
        _matchKey(track.title) ==
        _matchKey(data['trackName']?.toString() ?? '');
    final artistExact =
        _matchKey(track.artist) ==
        _matchKey(data['artistName']?.toString() ?? '');
    final duration = (data['duration'] as num?)?.toDouble();
    final durationClose =
        track.durationMs > 0 &&
        duration != null &&
        (duration - track.durationMs / 1000).abs() <= 3;
    final timed = (data['syncedLyrics']?.toString() ?? '').trim().isNotEmpty;
    return (titleExact ? 8 : 0) +
        (artistExact ? 4 : 0) +
        (durationClose ? 2 : 0) +
        (timed ? 1 : 0);
  }

  void _remember(String key, LyricsDocument? document, Duration duration) {
    _cache.remove(key);
    _cache[key] = (document, DateTime.now().add(duration));
    if (_cache.length > 8) _cache.remove(_cache.keys.first);
  }
}
