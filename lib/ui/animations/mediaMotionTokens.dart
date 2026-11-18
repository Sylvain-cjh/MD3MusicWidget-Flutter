import 'dart:math' as math;

import 'package:flutter/animation.dart';



abstract final class MediaMotionTokens {
  static const replacement = Duration(milliseconds: 420);
  static const reduced = Duration(milliseconds: 160);
  static const curve = Curves.easeInOutCubic;
  static const parallaxResponse = 24.0;
  static const layerHandoff = Duration(milliseconds: 250);
  static const settleCurve = Cubic(.23, 1, .32, 1);
  static const layerHandoffCurve = settleCurve;
  static const settingsDisclosure = Duration(milliseconds: 360);
  static const settingsDismissal = Duration(milliseconds: 270);
  static const settingsSection = Duration(milliseconds: 280);
  static const menuOpen = Duration(milliseconds: 220);
  static const menuClose = Duration(milliseconds: 170);
  static const outputMenuOpen = Duration(milliseconds: 340);
  static const outputMenuClose = Duration(milliseconds: 245);
  static const orientation = Duration(milliseconds: 440);

  static final Curve orientationCurve = _SmoothSpringCurve(3.8);
  static final Curve settingsSurfaceCurve = _SmoothSpringCurve(4.2);
  static final Curve compactSurfaceCurve = _SmoothSpringCurve(4.6);
  static final Curve outputMenuWidthCurve = _SmoothSpringCurve(5);
  static final Curve outputMenuHeightCurve = _SmoothSpringCurve(3.4);
  static const surfaceOpacityCurve = Curves.easeInOutSine;

  static Duration settingsDuration(bool open) =>
      open ? settingsDisclosure : settingsDismissal;
}





final class _SmoothSpringCurve extends Curve {
  final double _rate, _halfEndTangent, _end;

  factory _SmoothSpringCurve(double rate) {
    final halfEndTangent = rate * rate * math.exp(-rate) / 2;
    return _SmoothSpringCurve._(
      rate,
      halfEndTangent,
      _response(rate) - halfEndTangent,
    );
  }
  const _SmoothSpringCurve._(this._rate, this._halfEndTangent, this._end);
  static double _response(double x) => 1 - (1 + x) * math.exp(-x);

  @override
  double transformInternal(double t) =>
      (_response(_rate * t) - _halfEndTangent * t * t) / _end;
}
