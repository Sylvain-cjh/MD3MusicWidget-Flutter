import 'dart:convert';
import 'dart:io';

import 'platformProvider.dart';

final class MusicSource {
  final String id;
  final bool isPlaying;

  const MusicSource({required this.id, required this.isPlaying});

  String get label {
    final platform = identifyMusicPlatform(id);
    return platform == MusicPlatform.other ? id : '${platform.label} · $id';
  }

  static MusicSource? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['sourceAppId'];
    if (id is! String || id.trim().isEmpty) return null;
    return MusicSource(id: id, isPlaying: value['isPlaying'] == true);
  }
}

final class MusicSourceSnapshot {
  final String selectedSourceAppId;
  final List<MusicSource> sources;

  const MusicSourceSnapshot({
    required this.selectedSourceAppId,
    required this.sources,
  });

  factory MusicSourceSnapshot.fromJson(Object? value) {
    if (value is! Map || value['sources'] is! List) {
      throw const FormatException('Invalid music source list');
    }
    return MusicSourceSnapshot(
      selectedSourceAppId: value['selectedSourceAppId'] is String
          ? value['selectedSourceAppId'] as String
          : '',
      sources: (value['sources'] as List)
          .map(MusicSource.fromJson)
          .whereType<MusicSource>()
          .toList(growable: false),
    );
  }
}

abstract interface class MusicSourceClient {
  Future<MusicSourceSnapshot> fetchSources();
  Future<void> selectSource(String id);
  void close();
}

final class HttpMusicSourceClient implements MusicSourceClient {
  final HttpClient _client;
  final Uri baseUri;
  final Duration timeout;
  bool _closed = false;

  HttpMusicSourceClient({
    HttpClient? client,
    Uri? baseUri,
    this.timeout = const Duration(milliseconds: 2100),
  }) : _client = client ?? HttpClient(),
       baseUri = baseUri ?? Uri.parse('http://127.0.0.1:12580') {
    _client.connectionTimeout = const Duration(milliseconds: 500);
    _client.findProxy = (_) => 'DIRECT';
  }

  @override
  Future<MusicSourceSnapshot> fetchSources() async {
    final body = await _request(baseUri.resolve('/sources'), false);
    if (_closed) throw StateError('Music source client closed');
    return MusicSourceSnapshot.fromJson(jsonDecode(body));
  }

  @override
  Future<void> selectSource(String id) async {
    final uri = baseUri
        .resolve('/source')
        .replace(queryParameters: {'appId': id});
    await _request(uri, true);
  }

  Future<String> _request(Uri uri, bool post) async {
    if (_closed) throw StateError('Music source client closed');
    HttpClientRequest? request;
    var cancelled = false;
    try {
      return await (() async {
        final opened = await _client.openUrl(post ? 'POST' : 'GET', uri);
        request = opened;
        if (_closed || cancelled) {
          opened.abort();
          throw StateError('Music source request cancelled');
        }
        opened.persistentConnection = false;
        final response = await opened.close();
        if (response.statusCode !=
            (post ? HttpStatus.noContent : HttpStatus.ok)) {
          throw HttpException(
            'Music source request failed: ${response.statusCode}',
            uri: uri,
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (_closed || cancelled) {
            throw StateError('Music source request cancelled');
          }
          if (bytes.length + chunk.length > 256 * 1024) {
            throw const FormatException('Music source response is too large');
          }
          bytes.addAll(chunk);
        }
        if (_closed || cancelled) {
          throw StateError('Music source request cancelled');
        }
        return utf8.decode(bytes);
      })().timeout(timeout);
    } catch (_) {
      cancelled = true;
      request?.abort();
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
  }
}


final class MusicSourceService {
  MusicSourceService._();
  static final MusicSourceClient _client = HttpMusicSourceClient();
  static Future<MusicSourceSnapshot> fetchSources() => _client.fetchSources();
  static Future<void> selectSource(String id) => _client.selectSource(id);
}
