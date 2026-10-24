part of 'lyricsDocument.dart';

const _maximumLyricTime = 60000000;

int? _lyricClock(String? value) {
  if (value == null) return null;
  final text = value.trim();
  final clock = RegExp(
    r'^(?:(\d+):)?(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?$',
  ).firstMatch(text);
  if (clock != null) {
    final seconds = int.parse(clock[3]!);
    final minutes = int.parse(clock[2]!);
    if (seconds >= 60 || (clock[1] != null && minutes >= 60)) return null;
    final result =
        (int.parse(clock[1] ?? '0') * 3600 + minutes * 60 + seconds) * 1000 +
        int.parse((clock[4] ?? '0').padRight(3, '0'));
    return result <= _maximumLyricTime ? result : null;
  }
  final offset = RegExp(r'^(\d+(?:\.\d+)?)(ms|s)$').firstMatch(text);
  if (offset == null) return null;
  final number = double.tryParse(offset[1]!);
  if (number == null || !number.isFinite) return null;
  final result = (number * (offset[2] == 's' ? 1000 : 1)).round();
  return result <= _maximumLyricTime ? result : null;
}

bool _validLyricWords(List<LyricWord> words, String text) {
  if (words.isEmpty ||
      words.length > 4000 ||
      words.map((word) => word.text).join() != text) {
    return false;
  }
  var previous = -1;
  for (final word in words) {
    if (word.startMs < 0 ||
        word.startMs < previous ||
        word.endMs <= word.startMs ||
        word.endMs > _maximumLyricTime) {
      return false;
    }
    previous = word.startMs;
  }
  return true;
}

LyricsDocument _orderedLyrics(
  List<LyricLine> lines, {
  String title = '',
  String artist = '',
}) {
  if (lines.length > 10000 ||
      lines.fold<int>(0, (sum, line) => sum + line.words.length) > 50000) {
    throw const FormatException('Too many lyric segments');
  }
  final entries = lines.indexed.toList()
    ..sort((a, b) {
      final order = a.$2.startMs.compareTo(b.$2.startMs);
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
  return LyricsDocument(
    lines: [for (final entry in entries) entry.$2],
    title: title,
    artist: artist,
  );
}

LyricsDocument _parseEnhancedLrc(String source) {
  if (source.length > 2 * 1024 * 1024) {
    throw const FormatException('Lyrics are too large');
  }
  final time = RegExp(r'\[(\d{1,3}:\d{2}(?:[.:]\d{1,3})?)\]');
  final mark = RegExp(r'<(\d{1,3}:\d{2}(?:[.:]\d{1,3})?)>');
  final offset =
      int.tryParse(
        RegExp(
              r'^\[offset:([+-]?\d+)\]',
              multiLine: true,
              caseSensitive: false,
            ).firstMatch(source)?[1] ??
            '',
      ) ??
      0;
  final lines = <LyricLine>[];
  String title = '', artist = '';
  for (final raw in source.split(RegExp(r'\r?\n'))) {
    final metadata = RegExp(
      r'^\[(ti|ar):([^\]]*)\]$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (metadata != null) {
      if (metadata[1]!.toLowerCase() == 'ti') {
        title = metadata[2]!;
      } else {
        artist = metadata[2]!;
      }
      continue;
    }
    final stamps = time.allMatches(raw).toList();
    if (stamps.isEmpty) continue;
    final body = raw.substring(stamps.last.end);
    final marks = mark.allMatches(body).toList();
    if (marks.isEmpty) {
      for (final stamp in stamps) {
        final start = _lyricClock(stamp[1]);
        if (start != null) {
          lines.add(
            LyricLine(
              (start + offset).clamp(0, _maximumLyricTime),
              body.trim(),
            ),
          );
        }
      }
      continue;
    }
    final text = body.replaceAll(mark, '');
    final firstStart = _lyricClock(stamps.first[1]);
    if (firstStart == null) continue;
    for (final stamp in stamps) {
      final start = _lyricClock(stamp[1]);
      if (start == null) continue;
      final shift = start - firstStart + offset;
      final words = <LyricWord>[];
      final prefix = body.substring(0, marks.first.start);
      if (prefix.isNotEmpty) {
        final end = _lyricClock(marks.first[1]);
        if (end != null && end > firstStart) {
          words.add(
            LyricWord(
              (firstStart + shift).clamp(0, _maximumLyricTime),
              (end + shift).clamp(0, _maximumLyricTime),
              prefix,
            ),
          );
        }
      }
      
      
      for (var index = 0; index + 1 < marks.length; index++) {
        final wordStart = _lyricClock(marks[index][1]);
        final wordEnd = _lyricClock(marks[index + 1][1]);
        final wordText = body.substring(
          marks[index].end,
          marks[index + 1].start,
        );
        if (wordText.isNotEmpty && wordStart != null && wordEnd != null) {
          words.add(
            LyricWord(
              (wordStart + shift).clamp(0, _maximumLyricTime),
              (wordEnd + shift).clamp(0, _maximumLyricTime),
              wordText,
            ),
          );
        }
      }
      final valid = _validLyricWords(words, text);
      lines.add(
        LyricLine(
          (start + offset).clamp(0, _maximumLyricTime),
          text,
          endMs: valid ? words.last.endMs : null,
          words: valid ? List.unmodifiable(words) : const [],
        ),
      );
    }
  }
  return _orderedLyrics(lines, title: title, artist: artist);
}

LyricsDocument _parsePlatformWords(String source, {bool yrc = false}) {
  if (source.contains('LyricContent=')) {
    if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(source)) {
      throw const FormatException(
        'External XML declarations are not supported',
      );
    }
    try {
      final xml = XmlDocument.parse(source);
      final contents = xml.descendants
          .whereType<XmlElement>()
          .map((element) => element.getAttribute('LyricContent'))
          .whereType<String>();
      if (contents.isEmpty) return LyricsDocument(lines: []);
      source = contents.first;
    } on XmlParserException {
      
      
      
      final opening = RegExp(
        r'''<Lyric_\d+\b[^>]*\bLyricContent\s*=\s*(["'])''',
      ).firstMatch(source);
      final closing = RegExp(
        r'''(["'])\s*/?>\s*(?:</[\w:.-]+\s*>\s*)*$''',
      ).firstMatch(source);
      if (opening == null ||
          closing == null ||
          opening[1] != closing[1] ||
          closing.start < opening.end ||
          !source.contains('<QrcInfos')) {
        throw const FormatException('Invalid QRC lyric wrapper');
      }
      source = source.substring(opening.end, closing.start).replaceAllMapped(
        RegExp(r'&(?:amp|lt|gt|quot|apos|#\d+|#x[\da-fA-F]+);'),
        (match) {
          final entity = match[0]!;
          const named = {
            '&amp;': '&',
            '&lt;': '<',
            '&gt;': '>',
            '&quot;': '"',
            '&apos;': "'",
          };
          if (named.containsKey(entity)) return named[entity]!;
          final hex = entity.startsWith('&#x');
          final code = int.tryParse(
            entity.substring(hex ? 3 : 2, entity.length - 1),
            radix: hex ? 16 : 10,
          );
          return code != null &&
                  code > 0 &&
                  code <= 0x10ffff &&
                  !(code >= 0xd800 && code <= 0xdfff)
              ? String.fromCharCode(code)
              : entity;
        },
      );
    }
  }
  final header = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  final marker = yrc
      ? RegExp(r'\((\d+),(\d+),\d+\)')
      : RegExp(r'\((\d+),(\d+)\)');
  final lines = <LyricLine>[];
  for (final raw in source.split(RegExp(r'\r?\n'))) {
    final match = header.firstMatch(raw.trim());
    if (match == null) continue;
    final start = int.tryParse(match[1]!);
    final duration = int.tryParse(match[2]!);
    if (start == null ||
        duration == null ||
        start > _maximumLyricTime ||
        start + duration > _maximumLyricTime) {
      continue;
    }
    final body = match[3]!;
    final effectiveYrc = yrc || RegExp(r'^\(\d+,\d+,\d+\)').hasMatch(body);
    final activeMarker = effectiveYrc ? RegExp(r'\((\d+),(\d+),\d+\)') : marker;
    final marks = activeMarker.allMatches(body).toList();
    final words = <LyricWord>[];
    for (var index = 0; index < marks.length; index++) {
      final mark = marks[index];
      final text = effectiveYrc
          ? body.substring(
              mark.end,
              index + 1 < marks.length ? marks[index + 1].start : body.length,
            )
          : body.substring(index == 0 ? 0 : marks[index - 1].end, mark.start);
      final wordStart = int.tryParse(mark[1]!);
      final wordDuration = int.tryParse(mark[2]!);
      if (wordStart != null && wordDuration != null && text.isNotEmpty) {
        words.add(LyricWord(wordStart, wordStart + wordDuration, text));
      }
    }
    final text = body.replaceAll(activeMarker, '');
    final normalized = _normalizePlatformWords(words, start, start + duration);
    final valid = _validLyricWords(normalized, text);
    lines.add(
      LyricLine(
        start,
        text,
        endMs: start + duration,
        words: valid ? List.unmodifiable(normalized) : const [],
      ),
    );
  }
  return _orderedLyrics(lines);
}

List<LyricWord> _normalizePlatformWords(
  List<LyricWord> words,
  int start,
  int end,
) {
  const roundingToleranceMs = 20;
  final result = <LyricWord>[];
  var prefix = '';
  for (final word in words) {
    if (word.startMs < start - roundingToleranceMs ||
        word.endMs > end + roundingToleranceMs) {
      return const [];
    }
    if (word.endMs == word.startMs &&
        RegExp(r'^[^\p{L}\p{N}]+$', unicode: true).hasMatch(word.text)) {
      
      if (result.isEmpty) {
        prefix += word.text;
      } else {
        final previous = result.removeLast();
        result.add(
          LyricWord(
            previous.startMs,
            previous.endMs,
            previous.text + word.text,
          ),
        );
      }
      continue;
    }
    if (word.endMs <= word.startMs) return const [];
    final wordStart = word.startMs.clamp(start, end);
    final wordEnd = word.endMs.clamp(start, end);
    if (wordEnd <= wordStart) return const [];
    result.add(LyricWord(wordStart, wordEnd, prefix + word.text));
    prefix = '';
  }
  return prefix.isEmpty ? result : const [];
}

LyricsDocument _parseTtml(String source) {
  if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(source)) {
    throw const FormatException('External XML declarations are not supported');
  }
  final xml = XmlDocument.parse(source);
  final lines = <LyricLine>[];
  for (final paragraph in xml.descendants.whereType<XmlElement>().where(
    (element) => element.name.local == 'p',
  )) {
    final start = _lyricClock(paragraph.getAttribute('begin'));
    var end = _lyricClock(paragraph.getAttribute('end'));
    final duration = _lyricClock(paragraph.getAttribute('dur'));
    if (start == null) continue;
    end ??= duration == null ? null : start + duration;
    final words = <LyricWord>[];
    final buffer = StringBuffer();
    void read(XmlNode node) {
      if (node is XmlText) {
        if (node.value.trim().isEmpty &&
            node.value.contains(RegExp(r'[\r\n]'))) {
          return;
        }
        buffer.write(node.value);
        return;
      }
      if (node is! XmlElement) return;
      final role =
          node.attributes
              .where((attribute) => attribute.name.local == 'role')
              .firstOrNull
              ?.value ??
          '';
      if (role.contains('translation') || role.contains('x-roman')) return;
      final wordStart = _lyricClock(node.getAttribute('begin'));
      var wordEnd = _lyricClock(node.getAttribute('end'));
      final wordDuration = _lyricClock(node.getAttribute('dur'));
      wordEnd ??= wordStart != null && wordDuration != null
          ? wordStart + wordDuration
          : null;
      if (node.name.local == 'span' && wordStart != null && wordEnd != null) {
        final text = node.innerText;
        buffer.write(text);
        words.add(LyricWord(wordStart, wordEnd, text));
      } else {
        for (final child in node.children) {
          read(child);
        }
      }
    }

    for (final node in paragraph.children) {
      read(node);
    }
    final text = buffer.toString();
    if (text.trim().isEmpty) continue;
    final valid =
        _validLyricWords(words, text) &&
        words.every(
          (word) => word.startMs >= start && (end == null || word.endMs <= end),
        );
    lines.add(
      LyricLine(
        start,
        text,
        endMs: end,
        words: valid ? List.unmodifiable(words) : const [],
      ),
    );
  }
  return _orderedLyrics(lines);
}
