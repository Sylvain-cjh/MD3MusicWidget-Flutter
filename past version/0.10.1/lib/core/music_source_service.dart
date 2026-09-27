import 'dart:convert';
import 'dart:io';

import 'platform_provider.dart';

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

final class MusicSourceService {
  MusicSourceService._();

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 500);

  static Future<MusicSourceSnapshot> fetchSources() async {
    final request = await _client
        .getUrl(Uri.parse('http://127.0.0.1:12580/sources'))
        .timeout(const Duration(milliseconds: 700));
    final response = await request.close().timeout(
      const Duration(milliseconds: 700),
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Music sources unavailable', uri: request.uri);
    }
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(milliseconds: 700));
    return MusicSourceSnapshot.fromJson(jsonDecode(body));
  }

  static Future<void> selectSource(String id) async {
    final uri = Uri.http('127.0.0.1:12580', '/source', {'appId': id});
    final request = await _client
        .postUrl(uri)
        .timeout(const Duration(milliseconds: 700));
    final response = await request.close().timeout(
      const Duration(milliseconds: 700),
    );
    await response.drain<void>().timeout(const Duration(milliseconds: 700));
    if (response.statusCode != HttpStatus.noContent) {
      throw HttpException('Music source selection failed', uri: uri);
    }
  }
}
