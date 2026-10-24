import 'package:flutter/material.dart';
import '../../core/appState.dart';


class LyricsVisualMotion {
  static const duration = Duration(milliseconds: 200);
  static const reservedExtent = 64.0;
  final AnimationController animation;
  bool collapsed;
  LyricsVisualMotion({required TickerProvider vsync, required this.collapsed})
    : animation = AnimationController(
        vsync: vsync,
        duration: duration,
        value: collapsed ? 1 : 0,
      );

  void update(bool target, {required bool reduceMotion}) {
    final changed = target != collapsed;
    collapsed = target;
    final value = target ? 1.0 : 0.0;
    if (reduceMotion) {
      animation.stop();
      animation.value = value;
      return;
    }
    if (!changed && animation.isAnimating) return;
    if (!animation.isAnimating && animation.value == value) return;
    animation.animateTo(
      value,
      duration: Duration(
        microseconds:
            (duration.inMicroseconds * (value - animation.value).abs()).round(),
      ),
      curve: AppState.layoutSwitchCurve,
    );
  }

  void dispose() => animation.dispose();
}
