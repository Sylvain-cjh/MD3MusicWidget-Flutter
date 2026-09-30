import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

final class ComponentSizeMotion {
  static const Duration _legacyFrameDuration = Duration(milliseconds: 260);
  static const Duration _legacyContentDelay = Duration(milliseconds: 300);
  static const Duration _legacyContentDuration = Duration(milliseconds: 260);
  static const Duration _legacyTotalDuration = Duration(milliseconds: 560);
  static const Curve _legacyFrameCurve = Cubic(0.77, 0.0, 0.175, 1.0);
  static const Curve _legacyContentCurve = Cubic(0.23, 1.0, 0.32, 1.0);

  static const Duration contentDelay = Duration(milliseconds: 150);
  static const Tolerance scaleTolerance = Tolerance(
    distance: 0.0005,
    velocity: 0.01,
  );
  static const SpringDescription frameSpring = SpringDescription(
    mass: 1.0,
    stiffness: 342.0,
    damping: 36.99,
  );
  static const SpringDescription contentSpring = SpringDescription(
    mass: 1.0,
    stiffness: 438.0,
    damping: 41.86,
  );

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

  static SpringSimulation frameSimulation({
    required double begin,
    required double end,
    double velocity = 0.0,
  }) {
    return SpringSimulation(frameSpring, begin, end, velocity)
      ..tolerance = scaleTolerance;
  }

  static SpringSimulation contentSimulation({
    required double begin,
    required double end,
    double velocity = 0.0,
  }) {
    return SpringSimulation(contentSpring, begin, end, velocity)
      ..tolerance = scaleTolerance;
  }

  @Deprecated('Use frameSimulation for interruptible physical motion.')
  static double frameProgress(double timelineValue) {
    final double interval =
        _legacyFrameDuration.inMicroseconds /
        _legacyTotalDuration.inMicroseconds;
    return _legacyFrameCurve.transform(
      (timelineValue / interval).clamp(0.0, 1.0),
    );
  }

  @Deprecated('Use contentSimulation for interruptible physical motion.')
  static double contentProgress(double timelineValue) {
    final double begin =
        _legacyContentDelay.inMicroseconds /
        _legacyTotalDuration.inMicroseconds;
    if (timelineValue <= begin) return 0.0;
    final double interval =
        _legacyContentDuration.inMicroseconds /
        _legacyTotalDuration.inMicroseconds;
    return _legacyContentCurve.transform(
      ((timelineValue - begin) / interval).clamp(0.0, 1.0),
    );
  }
}

class ComponentSizeStage extends StatelessWidget {
  final double frameWidth;
  final double frameHeight;
  final double designWidth;
  final double designHeight;
  final double frameScale;
  final double contentScale;
  final Alignment alignment;
  final BoxDecoration decoration;
  final Duration frameAnimationDuration;
  final Curve frameAnimationCurve;
  final bool transformOnly;
  final Widget? background;
  final Widget child;

  const ComponentSizeStage({
    super.key,
    required this.frameWidth,
    required this.frameHeight,
    required this.designWidth,
    required this.designHeight,
    this.frameScale = 1.0,
    required this.contentScale,
    required this.alignment,
    required this.decoration,
    required this.frameAnimationDuration,
    required this.frameAnimationCurve,
    this.transformOnly = false,
    this.background,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (transformOnly) {
      final double foregroundScale = frameScale <= 0
          ? 1.0
          : contentScale / frameScale;
      return SizedBox(
        width: frameWidth,
        height: frameHeight,
        child: OverflowBox(
          alignment: alignment,
          minWidth: designWidth,
          maxWidth: designWidth,
          minHeight: designHeight,
          maxHeight: designHeight,
          child: Transform.scale(
            scale: frameScale,
            alignment: alignment,
            child: SizedBox(
              width: designWidth,
              height: designHeight,
              child: DecoratedBox(
                decoration: decoration,
                position: DecorationPosition.foreground,
                child: ClipRRect(
                  borderRadius: decoration.borderRadius ?? BorderRadius.zero,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (background != null)
                        RepaintBoundary(child: background!),
                      Transform.scale(
                        scale: foregroundScale,
                        alignment: alignment,
                        child: SizedBox(
                          width: designWidth,
                          height: designHeight,
                          child: RepaintBoundary(child: child),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: frameAnimationDuration,
      curve: frameAnimationCurve,
      width: frameWidth,
      height: frameHeight,
      foregroundDecoration: decoration,
      child: ClipRRect(
        borderRadius: decoration.borderRadius ?? BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (background != null) RepaintBoundary(child: background!),
            OverflowBox(
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
          ],
        ),
      ),
    );
  }
}
