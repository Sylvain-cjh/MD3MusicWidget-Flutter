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
}
