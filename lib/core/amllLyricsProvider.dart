import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lyricsDocument.dart';
import 'lyricsHttpClient.dart';
import 'lyricsPrimaryAttempt.dart';
import 'lyricsRequestError.dart';
import 'lyricsSongMatcher.dart';
import 'platformProvider.dart';



final class AmllLyricsProvider
    implements
        LyricsPlatformProvider,
        RetryableLyricsProvider,
        WordTimingLyricsProvider,
        ExhaustiveLyricsProvider {
  static const providerId = 'amll';
  final HttpClient _client;
  final Uri endpoint;
  final LyricsPlatformProvider? fallback;
  final Duration lookupBudget;
  final _pending = <String, Future<LyricsDocument?>>{};
  final LinkedHashMap<String, (LyricsDocument?, DateTime)> _cache =
      LinkedHashMap();
  DateTime? _retryAt;

  AmllLyricsProvider({
    HttpClient? client,
    Uri? endpoint,
    this.fallback,
    this.lookupBudget = const Duration(seconds: 4),
  }) : _client = directLyricsHttpClient(client),
       endpoint = endpoint ?? Uri.https('api.amll.dev', '/v1/lyrics/') {
    _client.maxConnectionsPerHost = 2;
  }

  @override
  String get id => providerId;
  @override
  bool accepts(PlatformTrack track) => track.title.trim().isNotEmpty;
  String _key(PlatformTrack track) => jsonEncode([
    LyricsSongMatcher.compact(track.title),
    LyricsSongMatcher.compact(track.artist),
    track.durationMs.isFinite ? track.durationMs.round() : 0,
  ]);

  @override
  void invalidateMiss(PlatformTrack track) {
    final key = _key(track);
    if (_cache[key]?.$1 == null) _cache.remove(key);
  }

  @override
  Future<LyricsDocument?> loadLyrics(PlatformTrack track) {
    if (!accepts(track)) return Future.value(null);
    final key = _key(track), cached = _cache[_key(track)];
    if (cached != null && DateTime.now().isBefore(cached.$2)) {
      return Future.value(cached.$1);
    }
    return _pending.putIfAbsent(
      key,
      () => _load(track, key).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  @override
  Future<LyricsDocument?> upgradeWordTiming(PlatformTrack track) {
    final key = _key(track);
    if (_cache[key]?.$1?.isWordTimed == true) {
      return Future.value(_cache[key]!.$1);
    }
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().isBefore(cached.$2) &&
        (cached.$1 == null ||
            cached.$1!.wordTimingRetryAt?.isAfter(DateTime.now()) == true)) {
      return Future.value(null);
    }
    return _pending.putIfAbsent(
      'words|$key',
      () => _lookup(track)
          .then((doc) {
            _remember(key, doc);
            return doc;
          })
          .whenComplete(() {
            _pending.remove('words|$key');
          }),
    );
  }

  void _remember(String key, LyricsDocument? value) {
    _cache.remove(key);
    _cache[key] = (
      value,
      DateTime.now().add(
        value == null ? const Duration(minutes: 5) : const Duration(hours: 2),
      ),
    );
    while (_cache.length > 8) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<LyricsDocument?> _load(PlatformTrack track, String key) async {
    Object? failure;
    try {
      final document = await _lookup(track);
      if (document != null) {
        _remember(key, document);
        return document;
      }
    } catch (error) {
      failure = error;
    }
    final document = await fallback?.loadLyrics(track);
    if (document != null && !document.isEmpty) {
      final resolved =
          (document.sourceProviderId.isEmpty
                  ? document.withSourceProviderId(fallback!.id)
                  : document)
              .withWordTimingRetryAt(
                _retryAt ?? DateTime.now().add(const Duration(minutes: 30)),
              );
      _remember(key, resolved);
      return resolved;
    }
    if (failure != null) Error.throwWithStackTrace(failure, StackTrace.current);
    _remember(key, null);
    return null;
  }

  Future<LyricsDocument?> _lookup(PlatformTrack track) async {
    if (_retryAt?.isAfter(DateTime.now()) == true) {
      throw LyricsRateLimitException(
        providerId: id,
        retryAt: _retryAt!,
        fromServer: false,
      );
    }
    final attempt = LyricsPrimaryAttempt(lookupBudget);
    return attempt.run(() async {
      final query = LyricsSongMatcher(track);
      final search = await _get('search', {
        'musicName': track.title.trim(),
        'pageSize': '30',
      }, attempt);
      final data = search is Map ? search['data'] : null;
      final items = data is Map ? data['items'] : null;
      if (items is! List) return null;
      final ranked = <(int, String)>[];
      for (final item in items.whereType<Map>()) {
        final names = item['musicNames'], artists = item['artistNames'];
        final identity = item['id']?.toString() ?? '';
        if (names is! List ||
            artists is! List ||
            !RegExp(r'^\d{1,16}$').hasMatch(identity)) {
          continue;
        }
        int? best;
        for (final name in names.whereType<String>()) {
          final score = query.score(
            title: name,
            artists: artists.whereType<String>(),
          );
          if (score != null && (best == null || score > best)) best = score;
        }
        if (best != null) ranked.add((best, identity));
      }
      ranked.sort((a, b) => b.$1.compareTo(a.$1));
      for (final candidate in ranked.take(2)) {
        final payload = await _get('get', {'id': candidate.$2}, attempt);
        final item = payload is Map ? payload['data'] : null;
        if (item is! Map || item['lyrics'] is! String) continue;
        try {
          final doc = (await LyricsDocument.parseAsync(
            item['lyrics'] as String,
            format: 'ttml',
          )).withSourceProviderId(id);
          if (!doc.isEmpty) {
            return doc.isWordTimed
                ? doc
                : doc.withWordTimingRetryAt(
                    DateTime.now().add(const Duration(minutes: 30)),
                  );
          }
        } on FormatException {
           
        }
      }
      return null;
    });
  }

  Future<Object?> _get(
    String action,
    Map<String, String> query,
    LyricsPrimaryAttempt attempt,
  ) async {
    final base = endpoint.path.endsWith('/')
        ? endpoint.path
        : '${endpoint.path}/';
    final request = await attempt.open(
      _client,
      endpoint.replace(path: '$base$action', queryParameters: query),
    );
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'MD3MusicWidget (Windows; lyrics client)',
    );
    try {
      final response = await request.close().timeout(attempt.remaining);
      if (response.statusCode == HttpStatus.notFound) {
        request.abort();
        return null;
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        _retryAt = lyricsRetryDeadline(
          response.headers.value(HttpHeaders.retryAfterHeader),
          now: DateTime.now(),
          serverDate: response.headers.value(HttpHeaders.dateHeader),
          fallback: const Duration(seconds: 30),
        );
        throw LyricsRateLimitException(
          providerId: id,
          retryAt: _retryAt!,
          fromServer: true,
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('AMLL returned HTTP ${response.statusCode}');
      }
      final bytes = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.timeout(attempt.remaining)) {
        length += chunk.length;
        if (length > 2 * 1024 * 1024) {
          throw const FormatException('AMLL response too large');
        }
        bytes.add(chunk);
      }
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } catch (_) {
      request.abort();
      rethrow;
    } finally {
      attempt.release(request);
    }
  }
}
