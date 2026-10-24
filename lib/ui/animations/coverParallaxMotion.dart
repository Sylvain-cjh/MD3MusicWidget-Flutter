import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'mediaMotionTokens.dart';


class CoverParallaxMotion extends ChangeNotifier {
  late final Ticker _ticker;
  Offset position = Offset.zero;
  Offset velocity = Offset.zero;
  Offset _target = Offset.zero;
  double hover = 0;
  double _hoverVelocity = 0;
  double _targetHover = 0;
  bool _reduced = false;
  Duration? _lastTick;
  int notifications = 0;

  CoverParallaxMotion(TickerProvider vsync) {
    _ticker = vsync.createTicker(_advance);
  }

  bool get isAnimating => _ticker.isActive;

  void setTarget(Offset point, {required bool hovered}) {
    _target = point.distance > 1 ? point / point.distance : point;
    _targetHover = hovered ? 1 : 0;
    if (_reduced) return;
    if ((position - _target).distanceSquared < 0.000001 &&
        (hover - _targetHover).abs() < 0.0005 &&
        velocity.distanceSquared < 0.00001) {
      return;
    }
    if (!_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
  }

  void reduceMotion(bool value) {
    if (_reduced == value) return;
    _reduced = value;
    if (value) {
      _ticker.stop();
      position = velocity = _target = Offset.zero;
      hover = _hoverVelocity = _targetHover = 0;
      invalidate();
    }
  }

  void invalidate() {
    notifications++;
    notifyListeners();
  }

  static (double, double) _step(
    double value,
    double velocity,
    double target,
    double omega,
    double dt,
  ) {
    final error = value - target;
    final c = velocity + omega * error;
    final decay = math.exp(-omega * dt);
    return (
      target + (error + c * dt) * decay,
      (velocity - omega * c * dt) * decay,
    );
  }

  void _advance(Duration elapsed) {
    final last = _lastTick;
    final dt = last == null
        ? 1 / 120
        : ((elapsed - last).inMicroseconds / 1000000).clamp(0.001, 0.25);
    _lastTick = elapsed;
    const omega = MediaMotionTokens.parallaxResponse;
    final x = _step(position.dx, velocity.dx, _target.dx, omega, dt);
    final y = _step(position.dy, velocity.dy, _target.dy, omega, dt);
    final h = _step(hover, _hoverVelocity, _targetHover, omega, dt);
    position = Offset(x.$1, y.$1);
    if (position.distance > 1.05) {
      position = position / position.distance * 1.05;
    }
    velocity = Offset(x.$2, y.$2);
    hover = h.$1.clamp(0.0, 1.0);
    _hoverVelocity = h.$2;
    if ((position - _target).distanceSquared < 0.000016 &&
        velocity.distanceSquared < 0.0025 &&
        (hover - _targetHover).abs() < 0.003 &&
        _hoverVelocity.abs() < 0.05) {
      position = _target;
      hover = _targetHover;
      velocity = Offset.zero;
      _hoverVelocity = 0;
      _ticker.stop();
      _lastTick = null;
    }
    invalidate();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
