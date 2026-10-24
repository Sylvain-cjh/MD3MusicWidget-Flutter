import 'package:xml/xml.dart';
import 'dart:isolate';

part 'lyricsFormats.dart';

final class LyricWord {
  final int startMs;
  final int endMs;
  final String text;
  const LyricWord(this.startMs, this.endMs, this.text);

  double progressAt(num positionMs) => !positionMs.isFinite || endMs <= startMs
      ? 0
      : ((positionMs - startMs) / (endMs - startMs)).clamp(0.0, 1.0);
}

final class LyricLine {
  final int startMs;
  final String text;
  final int? endMs;
  final List<LyricWord> words;

  const LyricLine(this.startMs, this.text, {this.endMs, this.words = const []});
  bool get isWordTimed => words.isNotEmpty;
}

final class LyricsDocument {
  final List<LyricLine> lines;
  final String plainText;
  final String title;
  final String artist;
  final String sourceProviderId;
  final bool wordTimingChecked;
  final DateTime? wordTimingRetryAt;

  LyricsDocument({
    required List<LyricLine> lines,
    this.plainText = '',
    this.title = '',
    this.artist = '',
    this.sourceProviderId = '',
    this.wordTimingChecked = true,
    this.wordTimingRetryAt,
  }) : lines = List.unmodifiable(lines);

  LyricsDocument withSourceProviderId(String id) => LyricsDocument(
    lines: lines,
    plainText: plainText,
    title: title,
    artist: artist,
    sourceProviderId: id,
    wordTimingChecked: wordTimingChecked,
    wordTimingRetryAt: wordTimingRetryAt,
  );

  LyricsDocument withWordTimingChecked() => LyricsDocument(
    lines: lines,
    plainText: plainText,
    title: title,
    artist: artist,
    sourceProviderId: sourceProviderId,
    wordTimingChecked: true,
  );

  LyricsDocument withWordTimingRetryAt(DateTime? retryAt) => LyricsDocument(
    lines: lines,
    plainText: plainText,
    title: title,
    artist: artist,
    sourceProviderId: sourceProviderId,
    wordTimingChecked: false,
    wordTimingRetryAt: retryAt,
  );

  bool get isTimed => lines.isNotEmpty;
  bool get isWordTimed => lines.any((line) => line.isWordTimed);
  bool get isEmpty => lines.isEmpty && plainText.isEmpty;

  int lineIndexAt(num positionMs) {
    if (lines.isEmpty ||
        !positionMs.isFinite ||
        positionMs < lines.first.startMs) {
      return -1;
    }
    int low = 0;
    int high = lines.length;
    while (low < high) {
      final middle = low + ((high - low) ~/ 2);
      if (lines[middle].startMs <= positionMs) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }

  LyricLine? lineAt(num positionMs) {
    final index = lineIndexAt(positionMs);
    return index < 0 ? null : lines[index];
  }

  static LyricsDocument parseLrc(String source) {
    if (RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>').hasMatch(source)) {
      return _parseEnhancedLrc(source);
    }
    if (source.length > 2 * 1024 * 1024) {
      throw const FormatException('Lyrics are too large');
    }
    final timestamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final offsetTag = RegExp(r'^\[offset:([+-]?\d+)\]$', caseSensitive: false);
    final metadataTag = RegExp(r'^\[(ti|ar):([^\]]*)\]$', caseSensitive: false);
    final timed = <(int, int, String)>[];
    final plain = <String>[];
    int offsetMs = 0;
    int order = 0;
    String title = '';
    String artist = '';

    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final offsetMatch = offsetTag.firstMatch(line);
      if (offsetMatch != null) {
        offsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
        continue;
      }
      final metadataMatch = metadataTag.firstMatch(line);
      if (metadataMatch != null) {
        if (metadataMatch.group(1)!.toLowerCase() == 'ti') {
          title = metadataMatch.group(2)!.trim();
        } else {
          artist = metadataMatch.group(2)!.trim();
        }
        continue;
      }
      final matches = timestamp.allMatches(line).toList();
      if (matches.isEmpty) {
        if (!line.startsWith('[')) plain.add(line);
        continue;
      }
      final text = line.substring(matches.last.end).trim();
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        if (seconds >= 60) continue;
        final fraction = (match.group(3) ?? '').padRight(3, '0');
        final millis = fraction.isEmpty ? 0 : int.parse(fraction);
        timed.add((minutes * 60000 + seconds * 1000 + millis, order++, text));
        if (timed.length > 10000) {
          throw const FormatException('Too many lyric lines');
        }
      }
    }
    timed.sort((a, b) {
      final byTime = a.$1.compareTo(b.$1);
      return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
    });
    return LyricsDocument(
      lines: [
        for (final entry in timed)
          LyricLine((entry.$1 + offsetMs).clamp(0, 60000000), entry.$3),
      ],
      plainText: plain.join('\n'),
      title: title,
      artist: artist,
    );
  }

  
  
  static LyricsDocument parse(String source, {String format = ''}) {
    if (source.length > 2 * 1024 * 1024) {
      throw const FormatException('Lyrics are too large');
    }
    final text = source.replaceFirst('\ufeff', '').trim();
    final kind = format.toLowerCase().replaceFirst('.', '');
    if (kind == 'ttml' || RegExp(r'<(?:\w+:)?tt[\s>]').hasMatch(text)) {
      try {
        return _parseTtml(text);
      } on XmlParserException {
        throw const FormatException('Invalid TTML XML');
      }
    }
    if (kind == 'qrc' ||
        kind == 'yrc' ||
        RegExp(r'^\[\d+,\d+\]', multiLine: true).hasMatch(text) ||
        text.contains('LyricContent=')) {
      return _parsePlatformWords(text, yrc: kind == 'yrc');
    }
    return parseLrc(text);
  }

  static Future<LyricsDocument> parseAsync(
    String source, {
    String format = '',
  }) => source.length > 16384
      ? Isolate.run(() => parse(source, format: format))
      : Future.value(parse(source, format: format));
}
