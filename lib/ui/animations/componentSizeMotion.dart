import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import '../widgets/smoothRoundedClip.dart';

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

  
  
  static double stableFitScale({
    required Size viewport,
    required Size design,
    required double referenceScale,
    required double devicePixelRatio,
    double maximumScale = double.infinity,
  }) {
    if (!viewport.width.isFinite ||
        !viewport.height.isFinite ||
        viewport.width <= 0 ||
        viewport.height <= 0 ||
        design.width <= 0 ||
        design.height <= 0) {
      return referenceScale.isFinite && referenceScale > 0
          ? referenceScale.clamp(0.0, maximumScale)
          : 1.0;
    }
    final tolerance = devicePixelRatio > 0 ? 1.0 / devicePixelRatio : 1.0;
    if (referenceScale.isFinite &&
        referenceScale > 0 &&
        viewport.width > 0 &&
        viewport.height > 0 &&
        (viewport.width - design.width * referenceScale).abs() <=
            tolerance + 0.000001 &&
        (viewport.height - design.height * referenceScale).abs() <=
            tolerance + 0.000001) {
      return referenceScale.clamp(0.0, maximumScale);
    }
    return fitScale(
      viewport: viewport,
      design: design,
      maximumScale: maximumScale,
    );
  }

  static double stableWidthScale({
    required double width,
    required double designWidth,
    required double referenceScale,
    required double devicePixelRatio,
    required double minimumScale,
    required double maximumScale,
  }) {
    if (designWidth <= 0 || !width.isFinite || width <= 0) {
      return referenceScale;
    }
    final tolerance = devicePixelRatio > 0 ? 1.0 / devicePixelRatio : 1.0;
    if ((width - designWidth * referenceScale).abs() <= tolerance + 0.000001) {
      return referenceScale.clamp(minimumScale, maximumScale);
    }
    return (width / designWidth).clamp(minimumScale, maximumScale);
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
  final double frameWidth, frameHeight, designWidth, designHeight;
  final double frameScale, contentScale;
  final Alignment alignment;
  final BoxDecoration decoration;
  final Duration frameAnimationDuration;
  final Curve frameAnimationCurve;
  final bool transformOnly;
  final Widget? background;
  final Widget child;
  final Animation<double>? visualCollapse;
  final double collapseExtent;
  final double? canvasWidth, canvasHeight;

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
    this.visualCollapse,
    this.collapseExtent = 0,
    this.canvasWidth,
    this.canvasHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (visualCollapse == null || collapseExtent <= 0) return _stage(0);
    return AnimatedBuilder(
      animation: visualCollapse!,
      builder: (context, _) =>
          _stage(collapseExtent * visualCollapse!.value.clamp(0.0, 1.0)),
    );
  }

  Widget _foreground() => RoundedRasterScale(
    scale: contentScale,
    child: SizedBox(width: designWidth, height: designHeight, child: child),
  );

  Widget _frame(Widget fullCanvas) => SmoothRoundedClip(
    borderRadius: decoration.borderRadius ?? BorderRadius.zero,
    child: DecoratedBox(
      decoration: decoration,
      position: DecorationPosition.foreground,
      child: fullCanvas,
    ),
  );

  Widget _stage(double inset) {
    if (transformOnly) {
      final visibleHeight = math.max(0.0, designHeight - inset);
      final ratio = frameScale <= 0 ? 1.0 : contentScale / frameScale;
      final canvas = SizedBox(
        width: designWidth,
        height: designHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (background != null) RepaintBoundary(child: background!),
            Transform.scale(
              scale: ratio,
              alignment: alignment,
              child: _foreground(),
            ),
          ],
        ),
      );
      return SizedBox(
        width: frameWidth,
        height: math.max(0.0, frameHeight - inset * frameScale),
        child: OverflowBox(
          alignment: alignment,
          minWidth: designWidth,
          maxWidth: designWidth,
          minHeight: visibleHeight,
          maxHeight: visibleHeight,
          child: Transform.scale(
            scale: frameScale,
            alignment: alignment,
            child: SizedBox(
              width: designWidth,
              height: visibleHeight,
              child: _frame(
                OverflowBox(
                  alignment: alignment,
                  minWidth: designWidth,
                  maxWidth: designWidth,
                  minHeight: designHeight,
                  maxHeight: designHeight,
                  child: canvas,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final paintWidth = canvasWidth ?? frameWidth;
    final paintHeight = canvasHeight ?? frameHeight;
    return AnimatedContainer(
      key: const ValueKey('visible_component_frame'),
      duration: frameAnimationDuration,
      curve: frameAnimationCurve,
      width: frameWidth,
      height: math.max(0.0, frameHeight - inset * contentScale),
      
      
      
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(paintWidth, constraints.maxWidth);
          final height = math.max(paintHeight, constraints.maxHeight);
          return _frame(
            OverflowBox(
              alignment: alignment,
              minWidth: width,
              maxWidth: width,
              minHeight: height,
              maxHeight: height,
              child: SizedBox(
                width: width,
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (background != null) RepaintBoundary(child: background!),
                    OverflowBox(
                      alignment: alignment,
                      minWidth: designWidth,
                      maxWidth: designWidth,
                      minHeight: designHeight,
                      maxHeight: designHeight,
                      child: Transform.scale(
                        scale: contentScale,
                        alignment: alignment,
                        child: _foreground(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
