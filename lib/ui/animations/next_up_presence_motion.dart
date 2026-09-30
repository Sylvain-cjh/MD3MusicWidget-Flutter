import 'package:flutter/material.dart';

import '../../core/app_state.dart';


class NextUpPresenceMotion {
  static const enterDuration = Duration(milliseconds: 250);
  static const exitDuration = Duration(milliseconds: 200);
  final AnimationController animation;
  final Future<void> Function(bool occupied) reserveSpace;
  int _serial = 0;
  bool _disposed = false;

  NextUpPresenceMotion({
    required TickerProvider vsync,
    required this.reserveSpace,
  }) : animation = AnimationController(vsync: vsync);

  Future<void> setVisible(bool visible, {required bool reduceMotion}) async {
    if (_disposed) return;
    final serial = ++_serial;
    animation.stop();
    if (visible) {
      await reserveSpace(true);
      if (_disposed || serial != _serial) return;
    }
    final target = visible ? 1.0 : 0.0;
    final base = reduceMotion
        ? const Duration(milliseconds: 160)
        : visible
        ? enterDuration
        : exitDuration;
    final duration = Duration(
      microseconds: (base.inMicroseconds * (target - animation.value).abs())
          .round(),
    );
    try {
      await animation
          .animateTo(
            target,
            duration: duration,
            curve: AppState.layoutSwitchCurve,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (_disposed || serial != _serial) return;
    if (!visible) await reserveSpace(false);
  }

  void cancel() {
    ++_serial;
    animation.stop();
  }

  void dispose() {
    _disposed = true;
    ++_serial;
    animation.dispose();
  }
}
