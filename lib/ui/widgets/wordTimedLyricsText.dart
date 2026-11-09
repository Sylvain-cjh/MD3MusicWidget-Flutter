import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';

import '../../core/lyricsDocument.dart';
import '../../core/lyricsHighlight.dart';
import '../animations/lyricsSmokeLetters.dart';
import '../animations/lyricsSmokeMotion.dart';
import 'lyricRowInk.dart';
import 'wordLyricsSmoke.dart';


class WordTimedLyricsText extends StatefulWidget {
  final LyricLine line;
  final TextStyle style;
  final Color highlight;
  final double inactiveOpacity;
  final LyricsHighlightStyle effect;
  final bool smokeEnabled;
  final double Function() positionMs;
  final bool Function() isPlaying;
  final Listenable playbackChanges;
  final bool active;
  const WordTimedLyricsText({
    super.key,
    required this.line,
    required this.style,
    required this.highlight,
    required this.positionMs,
    required this.isPlaying,
    required this.playbackChanges,
    this.inactiveOpacity = .46,
    this.effect = LyricsHighlightStyle.sweep,
    this.smokeEnabled = false,
    this.active = true,
  });

  @override
  State<WordTimedLyricsText> createState() => _WordTimedLyricsTextState();
}

class _WordTimedLyricsTextState extends State<WordTimedLyricsText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _paintRevision = ValueNotifier<int>(0);
  TextPainter? _base, _bright;
  LyricRowInk? _rowInk;
  List<List<TextBox>> _boxes = const [];
  List<List<TextBox>>? _smokeBoxes;
  LyricLine? _smokeLine;
  LyricLine? _smokeSource;
  Object? _layoutKey;
  double _position = 0;
  bool _tickerMode = true;
  bool _reduced = false;
  bool _smokeLoading = false;
  Timer? _smokeRetry;
  ui.FragmentProgram? _smokeProgram;
  WordLyricsSmoke? _smoke;
  Object? _smokeAttemptKey;
  Size _paragraphSize = Size.zero;
  double _pixelRatio = 1;
  int debugLayoutPasses = 0;
  bool get debugTickerActive => _ticker.isActive;
  int get debugPaintRevisions => _paintRevision.value;
  bool get debugSmokeReady => _smoke != null;
  int get debugSmokeBytes => _smoke?.approximateBytes ?? 0;
  Object? _animationEndKey;
  double _cachedAnimationEnd = 0;
  double get _animationEnd {
    final line = widget.smokeEnabled && _smokeSource == widget.line
        ? _smokeLine ?? widget.line
        : widget.line;
    final key = (line, widget.smokeEnabled, _reduced);
    if (_animationEndKey != key) {
      _animationEndKey = key;
      _cachedAnimationEnd = widget.line.words.isEmpty
          ? 0
          : widget.smokeEnabled
          ? LyricsSmokeMotion.endAt(line, reduced: _reduced)
          : widget.line.words.last.endMs.toDouble();
    }
    return _cachedAnimationEnd;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _advance());
    widget.playbackChanges.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerMode = TickerMode.valuesOf(context).enabled;
    _reduced = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(WordTimedLyricsText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackChanges != widget.playbackChanges) {
      oldWidget.playbackChanges.removeListener(_sync);
      widget.playbackChanges.addListener(_sync);
    }
    _sync();
  }

  void _advance() {
    final next = widget.positionMs();
    if (next.isFinite && next != _position) {
      _position = next;
      _paintRevision.value++;
    }
    if (!widget.isPlaying() ||
        !widget.active ||
        !_tickerMode ||
        _position >= _animationEnd) {
      _ticker.stop();
    }
  }

  void _sync() {
    _advance();
    if (widget.active &&
        _tickerMode &&
        widget.isPlaying() &&
        widget.line.words.isNotEmpty &&
        _position < _animationEnd &&
        !_ticker.isActive) {
      _ticker.start();
    }
  }

  void _layout(
    double width,
    TextDirection direction,
    TextScaler scaler,
    Locale? locale,
    double pixelRatio,
  ) {
    final key = (
      width,
      direction,
      scaler,
      locale,
      widget.line,
      widget.style,
      widget.highlight,
      widget.inactiveOpacity,
      pixelRatio,
    );
    if (key == _layoutKey) return;
    _layoutKey = key;
    _rowInk?.dispose();
    _rowInk = null;
    _smokeLine = null;
    _smokeBoxes = null;
    _smokeSource = null;
    _base?.dispose();
    _bright?.dispose();
    _smoke?.dispose();
    _smoke = null;
    _smokeAttemptKey = null;
    _pixelRatio = pixelRatio;
    final color = widget.style.color ?? widget.highlight;
    TextPainter paragraph(Color value) => TextPainter(
      text: TextSpan(
        text: widget.line.text,
        style: widget.style.copyWith(color: value),
      ),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      maxLines: 2,
      ellipsis: '…',
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout(maxWidth: width);
    _base = paragraph(
      color.withValues(alpha: color.a * widget.inactiveOpacity.clamp(.15, 1.0)),
    );
    _bright = paragraph(widget.highlight);
    var offset = 0;
    _boxes = [
      for (final word in widget.line.words) ...[
        _base!.getBoxesForSelection(
          TextSelection(
            baseOffset: offset,
            extentOffset: offset += word.text.length,
          ),
        ),
      ],
    ];
    _paragraphSize = Size(width, _base!.height);
    debugLayoutPasses++;
  }

  void _layoutSmokeUnits() {
    if (_smokeLine != null) return;
    final words = <LyricWord>[];
    final boxes = <List<TextBox>>[];
    var offset = 0;
    List<TextBox> selection(int start, int end) =>
        _bright!.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        );
    for (var i = 0; i < widget.line.words.length; i++) {
      final word = widget.line.words[i];
      final wordStart = offset;
      final end = offset + word.text.length;
      final original = _boxes[i];
      if (!original.any((box) => !box.toRect().isEmpty)) {
        offset = end;
        continue;
      }
      final units = LyricsSmokeLetters.split(word);
      if (units.length == 1) {
        words.add(word);
        boxes.add(original);
        offset = end;
        continue;
      }
      
      
      var first = 0;
      var start = offset;
      int? inkStart;
      for (var j = 0; j < units.length; j++) {
        final (letterStart, letterEnd) = LyricsSmokeLetters.letterRange(
          units[j].text,
        );
        inkStart ??= offset + letterStart;
        final inkEnd = offset + letterEnd;
        offset += units[j].text.length;
        if (j + 1 < units.length &&
            !selection(inkStart, inkEnd).any((box) => !box.toRect().isEmpty)) {
          continue;
        }
        final visible = selection(start, offset);
        if (!visible.any((box) => !box.toRect().isEmpty)) break;
        words.add(
          first == j
              ? units[j]
              : LyricWord(
                  units[first].startMs,
                  units[j].endMs,
                  word.text.substring(start - wordStart, offset - wordStart),
                ),
        );
        boxes.add(visible);
        first = j + 1;
        start = offset;
        inkStart = null;
      }
    }
    _smokeLine = LyricLine(
      widget.line.startMs,
      widget.line.text,
      endMs: widget.line.endMs,
      words: words,
    );
    _smokeBoxes = boxes;
    _smokeSource = widget.line;
  }

  void _ensureSmoke() {
    if (widget.smokeEnabled) {
      _layoutSmokeUnits();
      _rowInk ??= LyricRowInk.create(
        _bright!,
        _smokeBoxes!,
        _paragraphSize.width,
      );
    } else {
      _rowInk?.dispose();
      _rowInk = null;
    }
    if (!widget.smokeEnabled || _reduced) {
      _smoke?.dispose();
      _smoke = null;
      _smokeAttemptKey = null;
      return;
    }
    final program = _smokeProgram;
    if (program != null && _smoke == null && _smokeAttemptKey != _layoutKey) {
      _smokeAttemptKey = _layoutKey;
      _smoke ??= WordLyricsSmoke.create(
        program,
        _bright!,
        _smokeBoxes!,
        _paragraphSize,
        _pixelRatio,
        rowInk: _rowInk,
      );
    } else if (program == null && !_smokeLoading && WordLyricsSmoke.canRetry) {
      _smokeLoading = true;
      WordLyricsSmoke.program().then((value) {
        _smokeLoading = false;
        if (!mounted) return;
        if (value == null) {
          if (WordLyricsSmoke.canRetry && _smokeRetry == null) {
            final remaining = WordLyricsSmoke.retryAt?.difference(
              DateTime.now(),
            );
            _smokeRetry = Timer(
              remaining != null && remaining > Duration.zero
                  ? remaining
                  : const Duration(seconds: 1),
              () {
                _smokeRetry = null;
                if (mounted && widget.active && _tickerMode) _ensureSmoke();
              },
            );
          }
          return;
        }
        _smokeProgram = value;
        if (_bright != null) _ensureSmoke();
        _paintRevision.value++;
      });
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _layout(
        constraints.maxWidth,
        Directionality.of(context),
        MediaQuery.textScalerOf(context),
        Localizations.maybeLocaleOf(context),
        MediaQuery.devicePixelRatioOf(context),
      );
      _ensureSmoke();
      return Semantics(
        label: widget.line.text,
        child: ExcludeSemantics(
          child: _LyricBaseline(
            baseline: _base!.computeDistanceToActualBaseline(
              TextBaseline.alphabetic,
            ),
            child: RepaintBoundary(
              child: SizedBox(
                width: constraints.maxWidth,
                height: _base!.height,
                child: CustomPaint(
                  painter: _WordLyricsPainter(
                    base: _base!,
                    bright: _bright!,
                    line: widget.smokeEnabled ? _smokeLine! : widget.line,
                    boxes: widget.smokeEnabled ? _smokeBoxes! : _boxes,
                    rowInk: _rowInk,
                    position: () => _position,
                    effect: MediaQuery.disableAnimationsOf(context)
                        ? LyricsHighlightStyle.sweep
                        : widget.effect,
                    smokeEnabled: widget.smokeEnabled,
                    reduced: _reduced,
                    smoke: () => _smoke,
                    repaint: _paintRevision,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  void dispose() {
    _smokeRetry?.cancel();
    widget.playbackChanges.removeListener(_sync);
    _ticker.dispose();
    _paintRevision.dispose();
    _rowInk?.dispose();
    _base?.dispose();
    _bright?.dispose();
    _smoke?.dispose();
    super.dispose();
  }
}

class _LyricBaseline extends SingleChildRenderObjectWidget {
  final double baseline;
  const _LyricBaseline({required this.baseline, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _LyricBaselineBox(baseline);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _LyricBaselineBox renderObject,
  ) {
    renderObject.baseline = baseline;
  }
}

class _LyricBaselineBox extends RenderProxyBox {
  double _baseline;
  _LyricBaselineBox(this._baseline);
  set baseline(double value) {
    if (_baseline != value) {
      _baseline = value;
      markNeedsLayout();
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;
  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => _baseline;
}

class _WordLyricsPainter extends CustomPainter {
  final TextPainter base, bright;
  final LyricLine line;
  final List<List<TextBox>> boxes;
  final LyricRowInk? rowInk;
  final double Function() position;
  final LyricsHighlightStyle effect;
  final bool smokeEnabled, reduced;
  final WordLyricsSmoke? Function() smoke;
  _WordLyricsPainter({
    required this.base,
    required this.bright,
    required this.line,
    required this.boxes,
    required this.rowInk,
    required this.position,
    required this.effect,
    required this.smokeEnabled,
    required this.reduced,
    required this.smoke,
    required Listenable repaint,
  }) : super(repaint: repaint);

  Path _pathFor(int index, double progress) {
    final path = Path();
    final wordBoxes = boxes[index];
    var remaining =
        wordBoxes.fold<double>(0, (sum, box) => sum + box.right - box.left) *
        progress;
    for (final box in wordBoxes) {
      final width = (box.right - box.left).clamp(0.0, double.infinity);
      final amount = remaining.clamp(0.0, width);
      if (amount > 0) {
        path.addRect(
          Rect.fromLTRB(
            box.direction == TextDirection.rtl ? box.right - amount : box.left,
            box.top - 1,
            box.direction == TextDirection.rtl ? box.right : box.left + amount,
            box.bottom + 1,
          ),
        );
      }
      remaining -= width;
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final now = position();
    final complete = Path();
    final disappearing = Path();
    final smokeWords = <int>[];
    int? current;
    for (var i = 0; i < line.words.length; i++) {
      
      
      if (boxes[i].isEmpty) continue;
      final word = line.words[i];
      if (now >= word.endMs) {
        if (smokeEnabled) {
          disappearing.addPath(_pathFor(i, 1), Offset.zero);
          if (LyricsSmokeMotion.phaseAt(word, now, reduced: reduced) < 1) {
            smokeWords.add(i);
          }
        } else {
          complete.addPath(_pathFor(i, 1), Offset.zero);
        }
      } else if (smokeEnabled) {
        
        
        continue;
      } else if (now >= word.startMs) {
        current = i;
        break;
      } else {
        break;
      }
    }
    final emphasize =
        !smokeEnabled &&
        current != null &&
        effect == LyricsHighlightStyle.emphasis;
    if (emphasize || smokeEnabled) {
      final hole = disappearing;
      if (emphasize) hole.addPath(_pathFor(current, 1), Offset.zero);
      final rest = Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        hole,
      );
      canvas.save();
      
      
      canvas.clipPath(rest, doAntiAlias: !smokeEnabled);
      (smokeEnabled ? bright : base).paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      base.paint(canvas, Offset.zero);
    }
    if (!smokeEnabled) {
      canvas.save();
      canvas.clipPath(complete);
      bright.paint(canvas, Offset.zero);
      canvas.restore();
    }
    for (final index in smokeWords) {
      final phase = LyricsSmokeMotion.phaseAt(
        line.words[index],
        now,
        reduced: reduced,
      );
      if (phase > 0 &&
          !reduced &&
          smoke()?.paintWord(canvas, index, phase) == true) {
        continue;
      }
      
      final path = _pathFor(index, 1);
      if (phase > 0) {
        canvas.saveLayer(
          path.getBounds(),
          Paint()..color = Color.fromRGBO(255, 255, 255, 1 - phase),
        );
      }
      rowInk!.paintWord(canvas, index);
      if (phase > 0) canvas.restore();
    }
    
    
    if (current == null || smokeEnabled) return;
    final progress = line.words[current].progressAt(now);
    if (effect == LyricsHighlightStyle.soft) {
      final path = _pathFor(current, 1);
      canvas.save();
      canvas.clipPath(path);
      canvas.saveLayer(
        path.getBounds(),
        Paint()..color = Color.fromRGBO(255, 255, 255, progress),
      );
      bright.paint(canvas, Offset.zero);
      canvas.restore();
      canvas.restore();
    } else {
      canvas.save();
      if (emphasize) {
        final bounds = _pathFor(current, 1).getBounds();
        final lift = math.sin(progress * math.pi);
        canvas.translate(bounds.center.dx, bounds.center.dy - 1.2 * lift);
        canvas.scale(1 + .035 * lift);
        canvas.translate(-bounds.center.dx, -bounds.center.dy);
        canvas.save();
        canvas.clipPath(_pathFor(current, 1));
        base.paint(canvas, Offset.zero);
        canvas.restore();
      }
      canvas.clipPath(_pathFor(current, progress));
      bright.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WordLyricsPainter old) =>
      base != old.base ||
      line != old.line ||
      effect != old.effect ||
      smokeEnabled != old.smokeEnabled ||
      reduced != old.reduced;
}
