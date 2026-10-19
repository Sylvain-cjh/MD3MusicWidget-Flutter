import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lyrics_document.dart';
import 'lyrics_http_client.dart';
import 'lyrics_disk_cache.dart';
import 'lyrics_primary_attempt.dart';
import 'lyrics_song_matcher.dart';
import 'lyrics_request_error.dart';
import 'platform_provider.dart';

final class LrclibLyricsProvider
    implements
        LyricsPlatformProvider,
        RetryableLyricsProvider,
        ExhaustiveLyricsProvider {
  static const String providerId = 'lrclib';
  static const int _maximumResponseBytes = 2 * 1024 * 1024;
  final HttpClient _client;
  final Uri _endpoint;
  final LyricsDiskCache? cache;
  final Duration lookupBudget;
  final Duration exactBudget;
  final Duration minimumRequestInterval;
  final Map<String, Future<LyricsDocument?>> _pending = {};
  final LinkedHashMap<String, (LyricsDocument?, DateTime)> _cache =
      LinkedHashMap<String, (LyricsDocument?, DateTime)>();
  Future<void> _tail = Future<void>.value();
  DateTime _nextRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _retryAt;
  int _consecutiveLimits = 0;
  int _activeRequests = 0;
  final List<Completer<void>> _requestWaiters = [];

  LrclibLyricsProvider({
    HttpClient? client,
    Uri? endpoint,
    this.cache,
    this.lookupBudget = const Duration(seconds: 6),
    this.exactBudget = const Duration(seconds: 2),
    this.minimumRequestInterval = const Duration(milliseconds: 750),
  }) : _client = directLyricsHttpClient(client),
       _endpoint = endpoint ?? Uri.https('lrclib.net', '/api/get') {
    _client.maxConnectionsPerHost = 2;
  }

  void _checkCooldown() {
    final retryAt = _retryAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) {
      throw LyricsRateLimitException(
        providerId: providerId,
        retryAt: retryAt,
        fromServer: false,
      );
    }
  }

  @override
  String get id => providerId;

  @override
  bool accepts(PlatformTrack track) => track.title.trim().isNotEmpty;

  @override
  void invalidateMiss(PlatformTrack track) {
    final key =
        '${track.title.trim().toLowerCase()}|${track.artist.trim().toLowerCase()}|${(track.durationMs / 1000).round()}';
    if (_cache[key]?.$1 == null) _cache.remove(key);
  }

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
    return _pending.putIfAbsent(key, () {
      final request =
          Future<LyricsDocument?>(() async {
            final stored = await cache?.get(track, providerId);
            if (stored != null) {
              _remember(key, stored, const Duration(hours: 2));
              return stored;
            }
            final result = await _load(track, key);
            if (result != null && !result.isEmpty && cache != null) {
              unawaited(cache!.put(track, providerId, result));
            }
            return result;
          }).whenComplete(() {
            _pending.remove(key);
          });
      return request;
    });
  }

  Future<LyricsDocument?> _load(PlatformTrack track, String key) async {
    final attempt = LyricsPrimaryAttempt(lookupBudget);
    return attempt.run(() => _loadNetwork(track, key, attempt));
  }

  Future<LyricsDocument?> _loadNetwork(
    PlatformTrack track,
    String key,
    LyricsPrimaryAttempt attempt,
  ) async {
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
    Object? exact;
    if (artistKnown) {
      try {
        final phase = attempt.slice(exactBudget);
        exact = await phase.run(
          () => _requestJson(
            _endpoint.replace(queryParameters: parameters),
            phase,
          ),
        );
      } catch (error) {
        if (error is LyricsRateLimitException) {
          rethrow;
        }
        
      }
    }
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
    final results = await _requestJson(searchUri, attempt);
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

  Future<void> _reserveRequest(LyricsPrimaryAttempt attempt) {
    final slot = _tail.then((_) async {
      _checkCooldown();
      final wait = _nextRequestAt.difference(DateTime.now());
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait).timeout(attempt.remaining);
      }
      
      _checkCooldown();
      
      attempt.remaining;
      _nextRequestAt = DateTime.now().add(minimumRequestInterval);
    });
    _tail = slot.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return slot;
  }

  Future<void> _acquireRequest(LyricsPrimaryAttempt attempt) async {
    _checkCooldown();
    if (_activeRequests < 2) {
      _activeRequests++;
      return;
    }
    final waiter = Completer<void>();
    _requestWaiters.add(waiter);
    try {
      await waiter.future.timeout(attempt.remaining);
      _checkCooldown();
    } catch (_) {
      
      
      if (!_requestWaiters.remove(waiter)) _releaseRequest();
      rethrow;
    }
  }

  void _releaseRequest() {
    _activeRequests--;
    if (_requestWaiters.isNotEmpty) {
      _activeRequests++;
      _requestWaiters.removeAt(0).complete();
    }
  }

  Future<dynamic> _requestJson(Uri uri, LyricsPrimaryAttempt attempt) async {
    await _acquireRequest(attempt);
    try {
      return await _sendRequestJson(uri, attempt);
    } finally {
      _releaseRequest();
    }
  }

  Future<dynamic> _sendRequestJson(
    Uri uri,
    LyricsPrimaryAttempt attempt,
  ) async {
    await _reserveRequest(attempt);
    final request = await attempt.open(_client, uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'MD3MusicWidget/1.0.0 (https://github.com/Sylvain-cjh/MD3-MusicWidget)',
    );
    try {
      
      
      _checkCooldown();
      final response = await request.close().timeout(attempt.remaining);
      if (response.statusCode == HttpStatus.notFound) {
        _consecutiveLimits = 0;
        request.abort();
        return null;
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        final nextDeadline = lyricsRetryDeadline(
          response.headers.value(HttpHeaders.retryAfterHeader),
          now: DateTime.now(),
          serverDate: response.headers.value(HttpHeaders.dateHeader),
          fallback: Duration(
            seconds: 30 * (1 << _consecutiveLimits.clamp(0, 5)),
          ),
        );
        _consecutiveLimits++;
        if (_retryAt == null || nextDeadline.isAfter(_retryAt!)) {
          _retryAt = nextDeadline;
        }
        request.abort();
        throw LyricsRateLimitException(
          providerId: providerId,
          retryAt: _retryAt!,
          fromServer: true,
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        request.abort();
        throw HttpException('LRCLIB returned HTTP ${response.statusCode}');
      }
      _consecutiveLimits = 0;
      final builder = BytesBuilder(copy: false);
      int total = 0;
      await for (final chunk in response.timeout(attempt.remaining)) {
        total += chunk.length;
        if (total > _maximumResponseBytes) {
          throw const FormatException('Lyric response is too large');
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

  LyricsDocument? _documentIfMatching(
    PlatformTrack track,
    Map<String, dynamic> data,
  ) {
    final responseTitle = data['trackName']?.toString().trim() ?? '';
    final responseArtist = data['artistName']?.toString().trim() ?? '';
    if (LyricsSongMatcher(track).score(
          title: responseTitle,
          artists: [responseArtist],
          durationMs: (data['duration'] as num?)?.toDouble() == null
              ? null
              : (data['duration'] as num).toDouble() * 1000,
        ) ==
        null) {
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

  static int _matchScore(PlatformTrack track, Map<String, dynamic> data) {
    final duration = (data['duration'] as num?)?.toDouble();
    final timed = (data['syncedLyrics']?.toString() ?? '').trim().isNotEmpty;
    return (LyricsSongMatcher(track).score(
                  title: data['trackName']?.toString() ?? '',
                  artists: [data['artistName']?.toString() ?? ''],
                  durationMs: duration == null ? null : duration * 1000,
                ) ??
                0) *
            2 +
        (timed ? 1 : 0);
  }

  void _remember(String key, LyricsDocument? document, Duration duration) {
    _cache.remove(key);
    _cache[key] = (document, DateTime.now().add(duration));
    if (_cache.length > 8) _cache.remove(_cache.keys.first);
  }
}
