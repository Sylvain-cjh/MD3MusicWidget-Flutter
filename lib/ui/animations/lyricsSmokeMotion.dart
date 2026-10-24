import '../../core/lyricsDocument.dart';
import 'mediaMotionTokens.dart';



abstract final class LyricsSmokeMotion {
  static const hold = Duration(milliseconds: 80);
  static const referenceWordMs = 500;

  static Duration durationFor(LyricWord word, {bool reduced = false}) {
    if (reduced) return MediaMotionTokens.reduced;
    final sungMs = word.endMs - word.startMs;
    if (sungMs <= 0) return MediaMotionTokens.replacement;
    final boundedMs = sungMs.clamp(referenceWordMs ~/ 2, referenceWordMs * 2);
    return Duration(
      microseconds:
          (MediaMotionTokens.replacement.inMicroseconds *
                  boundedMs /
                  referenceWordMs)
              .round(),
    );
  }

  static Duration tailFor(LyricLine? line, {bool reduced = false}) {
    if (reduced) return MediaMotionTokens.reduced;
    var longest = MediaMotionTokens.replacement;
    if (line != null && line.words.isNotEmpty) {
      longest = Duration.zero;
      for (final word in line.words) {
        final duration = durationFor(word);
        if (duration > longest) longest = duration;
      }
    }
    return hold + longest;
  }

  static double phaseAt(
    LyricWord word,
    double positionMs, {
    bool reduced = false,
  }) {
    final delay = reduced ? 0 : hold.inMilliseconds;
    if (positionMs.isNaN) return 0;
    final length = durationFor(word, reduced: reduced).inMicroseconds / 1000;
    return ((positionMs - word.endMs - delay) / length).clamp(0.0, 1.0);
  }

  static double endAt(LyricLine line, {bool reduced = false}) {
    if (line.words.isEmpty) {
      return (line.endMs ?? line.startMs) +
          tailFor(line, reduced: reduced).inMicroseconds / 1000;
    }
    var end = double.negativeInfinity;
    for (final word in line.words) {
      final value =
          word.endMs +
          (reduced ? 0 : hold.inMilliseconds) +
          durationFor(word, reduced: reduced).inMicroseconds / 1000;
      if (value > end) end = value;
    }
    return end;
  }
}
