import 'package:flutter/widgets.dart' show StringCharacters;

import '../../core/lyricsDocument.dart';



abstract final class LyricsSmokeLetters {
  static final _letter = RegExp(r'^(?=\p{L})\p{Script=Latin}', unicode: true);
  static final _attached = RegExp(r'^[\p{P}\p{N}\s]+$', unicode: true);

  
  static (int, int) letterRange(String unit) {
    var offset = 0;
    for (final cluster in unit.characters) {
      if (_letter.hasMatch(cluster)) return (offset, offset + cluster.length);
      offset += cluster.length;
    }
    return (0, unit.length);
  }

  static List<LyricWord> split(LyricWord word) {
    final duration = word.endMs - word.startMs;
    if (duration <= 1 || word.text.length < 2) return [word];

    final letters = <String>[];
    var prefix = '';
    for (final cluster in word.text.characters) {
      if (_letter.hasMatch(cluster)) {
        letters.add(prefix + cluster);
        prefix = '';
      } else if (_attached.hasMatch(cluster)) {
        
        
        if (letters.isEmpty) {
          prefix += cluster;
        } else {
          letters.last += cluster;
        }
      } else {
        
        return [word];
      }
    }
    final count = letters.length;
    if (count < 2 || duration < count) return [word];
    return [
      for (var i = 0; i < count; i++)
        LyricWord(
          word.startMs + duration * i ~/ count,
          word.startMs + duration * (i + 1) ~/ count,
          letters[i],
        ),
    ];
  }
}
