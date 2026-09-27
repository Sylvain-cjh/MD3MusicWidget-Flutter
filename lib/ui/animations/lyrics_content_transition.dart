import 'package:flutter/material.dart';

import '../../core/app_state.dart';


class LyricsContentTransition extends StatelessWidget {
  final LyricsTransitionStyle style;
  final Animation<double> animation;
  final bool reduceMotion;
  final Widget child;

  const LyricsContentTransition({
    super.key,
    required this.style,
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
  Widget build(BuildContext context) {
    if (style == LyricsTransitionStyle.none) return child;

    Widget content = child;
    if (!reduceMotion) {
      content = switch (style) {
        LyricsTransitionStyle.rise => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.24),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
        LyricsTransitionStyle.descend => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.24),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
        LyricsTransitionStyle.sideways => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.12, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
        LyricsTransitionStyle.zoom => ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          alignment: Alignment.centerLeft,
          child: child,
        ),
        LyricsTransitionStyle.fade || LyricsTransitionStyle.none => child,
      };
    }

    return FadeTransition(opacity: animation, child: content);
  }
}
