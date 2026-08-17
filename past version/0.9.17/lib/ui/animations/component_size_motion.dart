import 'dart:math' as math;

import 'package:flutter/material.dart';

final class ComponentSizeMotion {
  static const Duration frameDuration = Duration(milliseconds: 260);
  static const Duration contentDelay = Duration(milliseconds: 300);
  static const Duration contentDuration = Duration(milliseconds: 260);
  static const Curve frameCurve = Cubic(0.77, 0.0, 0.175, 1.0);
  static const Curve contentCurve = Cubic(0.23, 1.0, 0.32, 1.0);

  static const Duration totalDuration = Duration(milliseconds: 560);

  static double fitScale({
    required Size viewport,
    required Size design,
    double maximumScale = double.infinity,
  }) {
    if (viewport.width <= 0 ||
        viewport.height <= 0 ||
        design.width <= 0 ||
        design.height <= 0) {
      return 1.0;
    }

    return math
        .min(viewport.width / design.width, viewport.height / design.height)
        .clamp(0.0, maximumScale)
        .toDouble();
  }

  static double frameProgress(double timelineValue) {
    final double interval =
        frameDuration.inMicroseconds / totalDuration.inMicroseconds;
    return frameCurve.transform((timelineValue / interval).clamp(0.0, 1.0));
  }

  static double contentProgress(double timelineValue) {
    final double begin =
        contentDelay.inMicroseconds / totalDuration.inMicroseconds;
    if (timelineValue <= begin) return 0.0;
    final double interval =
        contentDuration.inMicroseconds / totalDuration.inMicroseconds;
    return contentCurve.transform(
      ((timelineValue - begin) / interval).clamp(0.0, 1.0),
    );
  }
}

class ComponentSizeStage extends StatelessWidget {
  final double frameWidth;
  final double frameHeight;
  final double designWidth;
  final double designHeight;
  final double contentScale;
  final Alignment alignment;
  final BoxDecoration decoration;
  final Duration frameAnimationDuration;
  final Curve frameAnimationCurve;
  final Widget child;

  const ComponentSizeStage({
    super.key,
    required this.frameWidth,
    required this.frameHeight,
    required this.designWidth,
    required this.designHeight,
    required this.contentScale,
    required this.alignment,
    required this.decoration,
    required this.frameAnimationDuration,
    required this.frameAnimationCurve,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: frameAnimationDuration,
      curve: frameAnimationCurve,
      width: frameWidth,
      height: frameHeight,
      decoration: decoration,
      child: ClipRRect(
        borderRadius: decoration.borderRadius ?? BorderRadius.zero,
        child: OverflowBox(
          minWidth: designWidth,
          maxWidth: designWidth,
          minHeight: designHeight,
          maxHeight: designHeight,
          alignment: alignment,
          child: Transform.scale(
            scale: contentScale,
            alignment: alignment,
            child: SizedBox(
              width: designWidth,
              height: designHeight,
              child: RepaintBoundary(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
