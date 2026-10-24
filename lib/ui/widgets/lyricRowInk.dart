import 'dart:ui' as ui;

import 'package:flutter/painting.dart';



final class LyricRowInk {
  final List<ui.LineMetrics> lines;
  final List<TextPainter> paragraphs;
  final List<List<(Path, TextPainter)>> _words;
  final bool _ownsParagraphs;

  LyricRowInk._(this.lines, this.paragraphs, this._words, this._ownsParagraphs);

  factory LyricRowInk.create(
    TextPainter paragraph,
    List<List<ui.TextBox>> boxes,
    double maxWidth,
  ) {
    final lines = paragraph.computeLineMetrics();
    final rows = <TextPainter>[];
    final multiple = lines.length > 1;
    try {
      if (!multiple) {
        rows.add(paragraph);
      } else {
        for (final line in lines) {
          final position = paragraph.getPositionForOffset(
            Offset(line.left + line.width / 2, line.baseline - line.ascent / 2),
          );
          rows.add(
            _isolate(paragraph, paragraph.getLineBoundary(position), maxWidth),
          );
        }
      }
      final words = <List<(Path, TextPainter)>>[];
      for (final wordBoxes in boxes) {
        final paths = <int, Path>{};
        for (final box in wordBoxes) {
          final rect = box.toRect();
          if (rect.isEmpty) continue;
          final row = _rowForRect(lines, rect);
          (paths[row] ??= Path()).addRect(
            Rect.fromLTRB(rect.left, rect.top - 1, rect.right, rect.bottom + 1),
          );
        }
        words.add(
          paths.isEmpty
              ? const []
              : [
                  for (final entry in paths.entries)
                    (entry.value, rows[entry.key]),
                ],
        );
      }
      return LyricRowInk._(lines, rows, words, multiple);
    } catch (_) {
      if (multiple) {
        for (final row in rows) {
          row.dispose();
        }
      }
      rethrow;
    }
  }

  int rowForRect(Rect rect) => _rowForRect(lines, rect);

  static int _rowForRect(List<ui.LineMetrics> lines, Rect rect) {
    var row = 0;
    var nearest = double.infinity;
    for (var candidate = 0; candidate < lines.length; candidate++) {
      final line = lines[candidate];
      final distance =
          (rect.center.dy - (line.baseline + (line.descent - line.ascent) / 2))
              .abs();
      if (distance < nearest) {
        nearest = distance;
        row = candidate;
      }
    }
    return row;
  }

  void paintWord(Canvas canvas, int index) {
    for (final (path, paragraph) in _words[index]) {
      canvas.save();
      
      
      canvas.clipPath(path, doAntiAlias: false);
      paragraph.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  static TextPainter _isolate(
    TextPainter paragraph,
    TextRange visible,
    double maxWidth,
  ) {
    var offset = 0;
    final invisibleInk = Paint()..color = const Color(0x00000000);
    final invisibleStyle = TextStyle(
      foreground: invisibleInk,
      background: invisibleInk,
      shadows: const [],
      decoration: TextDecoration.none,
    );
    InlineSpan mask(InlineSpan span) {
      if (span is! TextSpan) {
        offset += span.toPlainText(includeSemanticsLabels: false).length;
        return span;
      }
      final text = span.text ?? '';
      final start = offset;
      offset += text.length;
      final from = (visible.start - start).clamp(0, text.length);
      final to = (visible.end - start).clamp(from, text.length);
      return TextSpan(
        style: span.style,
        children: [
          if (from > 0)
            TextSpan(text: text.substring(0, from), style: invisibleStyle),
          if (to > from) TextSpan(text: text.substring(from, to)),
          if (to < text.length)
            TextSpan(text: text.substring(to), style: invisibleStyle),
          for (final child in span.children ?? const <InlineSpan>[])
            mask(child),
        ],
      );
    }

    return TextPainter(
      text: mask(paragraph.text!),
      textAlign: paragraph.textAlign,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.ellipsis,
      locale: paragraph.locale,
      strutStyle: paragraph.strutStyle,
      textWidthBasis: paragraph.textWidthBasis,
      textHeightBehavior: paragraph.textHeightBehavior,
    )..layout(maxWidth: maxWidth);
  }

  void dispose() {
    if (_ownsParagraphs) {
      for (final paragraph in paragraphs) {
        paragraph.dispose();
      }
    }
  }
}
