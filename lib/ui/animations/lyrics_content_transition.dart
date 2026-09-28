import 'package:flutter/material.dart';

import '../../core/app_state.dart';

class LyricsContentTransition extends StatefulWidget {
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
    return Duration(milliseconds: reduceMotion ? 160 : 200);
  }

  @override
  State<LyricsContentTransition> createState() =>
      _LyricsContentTransitionState();
}

class _LyricsContentTransitionState extends State<LyricsContentTransition> {
  late bool _exiting;

  @override
  void initState() {
    super.initState();
    _exiting = widget.animation.status == AnimationStatus.reverse;
    widget.animation.addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(covariant LyricsContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_handleStatus);
      widget.animation.addStatusListener(_handleStatus);
    }
    _exiting = widget.animation.status == AnimationStatus.reverse;
  }

  void _handleStatus(AnimationStatus status) {
    final exiting = status == AnimationStatus.reverse;
    if (exiting != _exiting && mounted) setState(() => _exiting = exiting);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _exiting
        ? (widget.exitStyleResolver?.call() ?? widget.exitStyle ?? widget.style)
        : widget.style;
    if (style == LyricsTransitionStyle.none) {
      return _exiting ? const SizedBox.shrink() : widget.child;
    }

    Widget content = widget.child;
    if (!widget.reduceMotion) {
      final offset = switch (style) {
        LyricsTransitionStyle.fade => Offset(0, _exiting ? -0.08 : 0.08),
        LyricsTransitionStyle.rise => Offset(0, _exiting ? -0.24 : 0.24),
        LyricsTransitionStyle.descend => Offset(0, _exiting ? 0.24 : -0.24),
        LyricsTransitionStyle.sideways => Offset(_exiting ? -0.12 : 0.12, 0),
        _ => Offset.zero,
      };
      if (offset != Offset.zero) {
        content = SlideTransition(
          position: Tween<Offset>(
            begin: offset,
            end: Offset.zero,
          ).animate(widget.animation),
          child: content,
        );
      } else if (style == LyricsTransitionStyle.zoom) {
        content = ScaleTransition(
          scale: Tween<double>(
            begin: _exiting ? 1.04 : 0.96,
            end: 1,
          ).animate(widget.animation),
          alignment: Alignment.centerLeft,
          child: content,
        );
      }
    }

    return FadeTransition(opacity: widget.animation, child: content);
  }
}
