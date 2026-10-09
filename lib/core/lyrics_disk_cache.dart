import 'dart:convert';
import 'dart:typed_data';
import 'lyrics_document.dart';
import 'persistent_cache.dart';
import 'platform_provider.dart';

final class LyricsDiskCache {
  final PersistentCache store;
  LyricsDiskCache(this.store);
  String _key(PlatformTrack track, String source) => jsonEncode([
    source,
    track.title.trim().toLowerCase(),
    track.artist.trim().toLowerCase(),
  ]);

  Future<LyricsDocument?> get(PlatformTrack track, String source) async {
    final bytes = await store.get(_key(track, source));
    if (bytes == null) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map || json['version'] != 1 || json['lines'] is! List) {
        return null;
      }
      final duration = json['durationMs'];
      if (duration is num &&
          duration > 0 &&
          track.durationMs > 0 &&
          (duration - track.durationMs).abs() > 12000) {
        return null;
      }
      final lines = json['lines'] as List;
      if (lines.length > 10000) return null;
      final parsed = <LyricLine>[];
      for (final line in lines) {
        if (line is! List ||
            line.length != 2 ||
            line[0] is! int ||
            line[0] < 0 ||
            line[0] > 60000000 ||
            (parsed.isNotEmpty && line[0] < parsed.last.startMs) ||
            line[1] is! String) {
          return null;
        }
        parsed.add(LyricLine(line[0], line[1]));
      }
      final doc = LyricsDocument(
        lines: parsed,
        plainText: json['plainText'] as String? ?? '',
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        sourceProviderId: json['source'] as String? ?? source,
      );
      return doc.isEmpty ? null : doc;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(PlatformTrack track, String source, LyricsDocument doc) =>
      store.put(
        _key(track, source),
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'version': 1,
              'durationMs': track.durationMs.isFinite ? track.durationMs : 0,
              'lines': [
                for (final line in doc.lines) [line.startMs, line.text],
              ],
              'plainText': doc.plainText,
              'title': doc.title,
              'artist': doc.artist,
              'source': doc.sourceProviderId.isEmpty
                  ? source
                  : doc.sourceProviderId,
            }),
          ),
        ),
      );
}
