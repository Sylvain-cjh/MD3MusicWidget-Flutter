import 'dart:math' as math;

import 'package:flutter/animation.dart';



abstract final class MediaMotionTokens {
  static const replacement = Duration(milliseconds: 420);
  static const reduced = Duration(milliseconds: 160);
  static const curve = Curves.easeInOutCubic;
  static const parallaxResponse = 24.0;
  static const layerHandoff = Duration(milliseconds: 250);
  static const layerHandoffCurve = Cubic(.23, 1, .32, 1);
  static const settingsDisclosure = Duration(milliseconds: 280);
  static const settingsDisclosureCurve = Cubic(.32, .72, 0, 1);
  static const orientation = Duration(milliseconds: 300);
  static const orientationCurve = _OrientationSpringCurve();
}



final class _OrientationSpringCurve extends Curve {
  const _OrientationSpringCurve();

  static final _end = _response(2 * math.pi);
  static double _response(double x) => 1 - (1 + x) * math.exp(-x);

  @override
  double transformInternal(double t) => _response(2 * math.pi * t) / _end;
}
