import 'dart:convert';
import 'dart:typed_data';
import 'dart:isolate';
import 'lyrics_document.dart';
import 'persistent_cache.dart';
import 'platform_provider.dart';

final class LyricsDiskCache {
  final PersistentCache store;
  LyricsDiskCache(this.store);
  String _legacyKey(PlatformTrack track, String source) => jsonEncode([
    source,
    track.title.trim().toLowerCase(),
    track.artist.trim().toLowerCase(),
  ]);

  static String _text(String value) => value
      .toLowerCase()
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('［', '[')
      .replaceAll('］', ']')
      .replaceAll('：', ':')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _artist(String value) {
    final artists = value.split(RegExp(r'[/&、]')).map(_text).toList()..sort();
    return jsonEncode(artists);
  }

  
  
  
  static String keyFor(PlatformTrack track, String source) => jsonEncode([
    'lyrics-v2',
    source,
    _text(track.title),
    _artist(track.artist),
  ]);

  Future<LyricsDocument?> get(PlatformTrack track, String source) async {
    final key = keyFor(track, source);
    var bytes = await store.get(key);
    final legacy = bytes == null;
    bytes ??= await store.get(_legacyKey(track, source));
    if (bytes == null) return null;
    final payload = bytes;
    final doc = bytes.length > 16384
        ? await Isolate.run(() => _decodeCached(payload, track, source))
        : _decodeCached(payload, track, source);
    if (doc != null && legacy) await put(track, source, doc);
    return doc;
  }

  static LyricsDocument? _decodeCached(
    Uint8List bytes,
    PlatformTrack track,
    String source,
  ) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map ||
          !const [1, 2, 3].contains(json['version']) ||
          json['lines'] is! List) {
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
      var totalWords = 0;
      for (final line in lines) {
        if (line is! List ||
            (line.length != 2 && line.length != 4) ||
            line[0] is! int ||
            line[0] < 0 ||
            line[0] > 60000000 ||
            (parsed.isNotEmpty && line[0] < parsed.last.startMs) ||
            line[1] is! String) {
          return null;
        }
        int? end;
        final words = <LyricWord>[];
        if (line.length == 4) {
          end = line[2] is int ? line[2] as int : null;
          if (line[2] != null &&
              (end == null || end < line[0] || end > 60000000)) {
            return null;
          }
          if (line[3] is! List || (line[3] as List).length > 4000) return null;
          for (final word in line[3] as List) {
            if (word is! List ||
                word.length != 3 ||
                word[0] is! int ||
                word[1] is! int ||
                word[2] is! String ||
                word[0] < line[0] ||
                word[1] <= word[0] ||
                word[1] > 60000000 ||
                (end != null && word[1] > end) ||
                (words.isNotEmpty && word[0] < words.last.startMs)) {
              return null;
            }
            words.add(LyricWord(word[0], word[1], word[2]));
          }
          if (words.isNotEmpty &&
              words.map((word) => word.text).join() != line[1]) {
            return null;
          }
        }
        totalWords += words.length;
        if (totalWords > 50000) {
          return null;
        }
        parsed.add(
          LyricLine(
            line[0],
            line[1],
            endMs: end,
            words: List.unmodifiable(words),
          ),
        );
      }
      final doc = LyricsDocument(
        lines: parsed,
        plainText: json['plainText'] as String? ?? '',
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        sourceProviderId: json['source'] as String? ?? source,
        wordTimingChecked:
            parsed.any((line) => line.isWordTimed) ||
            (json['version'] == 3 && json['wordTimingChecked'] != false) ||
            (json['version'] == 2 &&
                !const ['qqMusic', 'neteaseCloud', 'amll'].contains(source) &&
                json['wordTimingChecked'] != false),
        wordTimingRetryAt: json['wordTimingRetryAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['wordTimingRetryAt'])
            : null,
      );
      if (doc.isEmpty) return null;
      return doc;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(
    PlatformTrack track,
    String source,
    LyricsDocument doc,
  ) async {
    if (doc.isEmpty) return;
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 3,
          'wordTimingChecked': doc.wordTimingChecked,
          'wordTimingRetryAt': doc.wordTimingRetryAt?.millisecondsSinceEpoch,
          'cacheKeyVersion': 2,
          'lookupTitle': track.title,
          'lookupArtist': track.artist,
          'durationMs': track.durationMs.isFinite ? track.durationMs : 0,
          'lines': [
            for (final line in doc.lines)
              [
                line.startMs,
                line.text,
                line.endMs,
                [
                  for (final word in line.words)
                    [word.startMs, word.endMs, word.text],
                ],
              ],
          ],
          'plainText': doc.plainText,
          'title': doc.title,
          'artist': doc.artist,
          'source': doc.sourceProviderId.isEmpty
              ? source
              : doc.sourceProviderId,
        }),
      ),
    );
    Future<bool> preserveWords(Uint8List existing) async {
      final previous = existing.length > 16384
          ? await Isolate.run(() => _decodeCached(existing, track, source))
          : _decodeCached(existing, track, source);
      return previous?.isWordTimed != true;
    }

    Future<void> write(String id) => store.put(
      keyFor(track, id),
      bytes,
      shouldReplace: doc.isWordTimed ? null : preserveWords,
    );
    final writes = [write(source)];
    final actual = doc.sourceProviderId;
    
    
    if (actual.isNotEmpty && actual != source) {
      writes.add(write(actual));
    }
    
    
    await Future.wait(writes);
  }
}
