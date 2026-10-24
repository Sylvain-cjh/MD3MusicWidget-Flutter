import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/appState.dart';

class LyricsContentTransition extends StatefulWidget {
  
  
  static const lifecycleDuration = Duration(milliseconds: 200);
  final LyricsTransitionStyle style;
  final LyricsTransitionStyle? exitStyle;
  final LyricsTransitionStyle Function()? exitStyleResolver;
  final Animation<double> animation;
  final bool reduceMotion;
  final Widget child;

  const LyricsContentTransition({
    super.key,
    required this.style,
    this.exitStyle,
    this.exitStyleResolver,
    required this.animation,
    required this.reduceMotion,
    required this.child,
  });

  static Duration durationFor(
    LyricsTransitionStyle style, {
    required bool reduceMotion,
  }) {
    if (style == LyricsTransitionStyle.none) return Duration.zero;
    return reduceMotion ? const Duration(milliseconds: 160) : lifecycleDuration;
  }

  @override
  State<LyricsContentTransition> createState() =>
      _LyricsContentTransitionState();
}

class _LyricsContentTransitionState extends State<LyricsContentTransition> {
  late bool _exiting;
  LyricsTransitionStyle? _exitStyle;
  double _exitStartValue = 1;
  ({Offset offset, double scale, double angle, double reveal})?
  _interruptedFrame;

  static ({Offset offset, double scale, double angle, double reveal}) _frameFor(
    LyricsTransitionStyle style,
    double value, {
    required bool exiting,
  }) {
    final remaining = 1 - value;
    final offset =
        switch (style) {
          LyricsTransitionStyle.fade => Offset(0, exiting ? -0.08 : 0.08),
          LyricsTransitionStyle.rise => Offset(0, exiting ? -0.24 : 0.24),
          LyricsTransitionStyle.descend => Offset(0, exiting ? 0.24 : -0.24),
          LyricsTransitionStyle.sideways => Offset(exiting ? -0.12 : 0.12, 0),
          LyricsTransitionStyle.film => Offset(0, exiting ? -0.85 : 0.85),
          _ => Offset.zero,
        } *
        remaining;
    final endpoint = switch (style) {
      LyricsTransitionStyle.zoom => exiting ? 1.18 : 0.90,
      LyricsTransitionStyle.settle => exiting ? 0.90 : 1.18,
      _ => 1.0,
    };
    return (
      offset: offset,
      scale: 1 + (endpoint - 1) * remaining,
      angle: style == LyricsTransitionStyle.flip
          ? (exiting ? 1 : -1) * remaining * math.pi / 3
          : 0.0,
      reveal: style == LyricsTransitionStyle.wipe ? value : 1.0,
    );
  }

  void _captureExit() {
    _exitStyle =
        widget.exitStyleResolver?.call() ?? widget.exitStyle ?? widget.style;
    _exitStartValue = widget.animation.value;
    _interruptedFrame = _exitStartValue < 0.99999
        ? _frameFor(widget.style, _exitStartValue, exiting: false)
        : null;
  }

  @override
  void initState() {
    super.initState();
    _exiting = widget.animation.status == AnimationStatus.reverse;
    if (_exiting) _captureExit();
    widget.animation.addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(covariant LyricsContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_handleStatus);
      widget.animation.addStatusListener(_handleStatus);
      _exiting = widget.animation.status == AnimationStatus.reverse;
      if (_exiting) _captureExit();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) return;
    final exiting = status == AnimationStatus.reverse;
    if (exiting != _exiting && mounted) {
      setState(() {
        _exiting = exiting;
        if (exiting) _captureExit();
      });
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _exiting
        ? (_exitStyle ?? widget.exitStyle ?? widget.style)
        : widget.style;
    if (style == LyricsTransitionStyle.none) {
      return _exiting ? const SizedBox.shrink() : widget.child;
    }

    Widget content = widget.child;
    final start = _interruptedFrame;
    if (_exiting && start != null && !widget.reduceMotion) {
      final target = _frameFor(style, 0, exiting: true);
      return FadeTransition(
        opacity: widget.animation,
        child: AnimatedBuilder(
          animation: widget.animation,
          child: content,
          builder: (context, child) {
            final progress = _exitStartValue > 0.00001
                ? (1 - widget.animation.value / _exitStartValue).clamp(0.0, 1.0)
                : 1.0;
            final offset = Offset.lerp(start.offset, target.offset, progress)!;
            final scale = start.scale + (target.scale - start.scale) * progress;
            final angle = start.angle + (target.angle - start.angle) * progress;
            final matrix = Matrix4.identity();
            if (angle.abs() > 0.00001) {
              matrix
                ..setEntry(3, 2, 0.002)
                ..rotateX(angle);
            }
            matrix.scaleByDouble(scale, scale, 1, 1);
            Widget transformed = FractionalTranslation(
              translation: offset,
              child: Transform(
                alignment: Alignment.centerLeft,
                transform: matrix,
                child: child,
              ),
            );
            if (start.reveal < 1 || style == LyricsTransitionStyle.wipe) {
              transformed = ClipRect(
                clipper: _LyricWipeClipper(
                  widget.animation,
                  startValue: _exitStartValue,
                  startReveal: start.reveal,
                  endReveal: target.reveal,
                ),
                child: transformed,
              );
            }
            return transformed;
          },
        ),
      );
    }
    if (!widget.reduceMotion) {
      final endpoint = _frameFor(style, 0, exiting: _exiting);
      final offset = endpoint.offset;
      if (offset != Offset.zero) {
        content = SlideTransition(
          position: Tween<Offset>(
            begin: offset,
            end: Offset.zero,
          ).animate(widget.animation),
          child: content,
        );
      } else if (style == LyricsTransitionStyle.zoom ||
          style == LyricsTransitionStyle.settle) {
        content = ScaleTransition(
          scale: Tween<double>(
            begin: endpoint.scale,
            end: 1,
          ).animate(widget.animation),
          alignment: Alignment.centerLeft,
          child: content,
        );
      } else if (style == LyricsTransitionStyle.flip) {
        content = AnimatedBuilder(
          animation: widget.animation,
          child: content,
          builder: (context, child) {
            final angle = (1 - widget.animation.value) * endpoint.angle;
            return Transform(
              alignment: Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateX(angle),
              child: child,
            );
          },
        );
      } else if (style == LyricsTransitionStyle.wipe) {
        content = ClipRect(
          clipper: _LyricWipeClipper(widget.animation),
          child: content,
        );
      }
    }

    return FadeTransition(opacity: widget.animation, child: content);
  }
}

class _LyricWipeClipper extends CustomClipper<Rect> {
  final Animation<double> progress;
  final double? startValue;
  final double? startReveal;
  final double? endReveal;

  _LyricWipeClipper(
    this.progress, {
    this.startValue,
    this.startReveal,
    this.endReveal,
  }) : super(reclip: progress);

  @override
  Rect getClip(Size size) {
    var reveal = progress.value;
    if (startValue != null && startReveal != null && endReveal != null) {
      final fraction = startValue! > 0.00001
          ? (1 - progress.value / startValue!).clamp(0.0, 1.0)
          : 1.0;
      reveal = startReveal! + (endReveal! - startReveal!) * fraction;
    }
    return Rect.fromLTWH(0, 0, size.width * reveal, size.height);
  }

  @override
  bool shouldReclip(covariant _LyricWipeClipper oldClipper) =>
      oldClipper.progress != progress ||
      oldClipper.startValue != startValue ||
      oldClipper.startReveal != startReveal ||
      oldClipper.endReveal != endReveal;
}
