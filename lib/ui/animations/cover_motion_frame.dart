import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import 'media_motion_tokens.dart';

class CoverMotionFrame {
  final Offset offset;
  final double scale;
  final double angle;
  final double opacity;

  const CoverMotionFrame({
    this.offset = Offset.zero,
    this.scale = 1,
    this.angle = 0,
    this.opacity = 1,
  });

  CoverMotionFrame towards(
    CoverMotionFrame target,
    double progress, {
    double? opacity,
  }) => CoverMotionFrame(
    offset: Offset.lerp(offset, target.offset, progress)!,
    scale: scale + (target.scale - scale) * progress,
    angle: angle + (target.angle - angle) * progress,
    opacity:
        opacity ?? this.opacity + (target.opacity - this.opacity) * progress,
  );
}

abstract final class CoverMotionGeometry {
  static const frontLiftProgress = 0.5;
  static const deckDistance = 0.36;
  static const previousPullDistance = deckDistance;
  static const nextEntryOffset = Offset(1, -0.72);
  static const normalDuration = MediaMotionTokens.replacement;
  static const previousDuration = normalDuration;
  static const reducedDuration = MediaMotionTokens.reduced;

  static Duration durationFor(
    CoverTransitionStyle style,
    int direction,
    bool reduced,
  ) => style == CoverTransitionStyle.none
      ? Duration.zero
      : reduced
      ? reducedDuration
      : normalDuration;

  static double progressFor(
    CoverTransitionStyle style,
    int direction,
    double time,
  ) => MediaMotionTokens.curve.transform(time.clamp(0.0, 1.0));

  
  
  static CoverMotionFrame softSlideIncoming(int direction, double progress) {
    final p = progress.clamp(0.0, 1.0);
    if (direction >= 0) {
      return CoverMotionFrame(
        offset: nextEntryOffset * (1 - p),
        scale: 0.92 + 0.08 * p,
      );
    }
    if (p < frontLiftProgress) {
      final lift = p / frontLiftProgress;
      return CoverMotionFrame(
        offset: Offset.lerp(
          const Offset(-0.04, 0.055),
          const Offset(-deckDistance, -0.035),
          lift,
        )!,
        scale: 0.90 + 0.06 * lift,
        angle: -0.05 * lift,
      );
    }
    final settle = (p - frontLiftProgress) / (1 - frontLiftProgress);
    return CoverMotionFrame(
      offset: const Offset(-deckDistance, -0.035) * (1 - settle),
      scale: 0.96 + 0.04 * settle,
      angle: -0.05 * (1 - settle),
    );
  }

  static CoverMotionFrame frameFor(
    CoverTransitionStyle style,
    int direction,
    double visibility, {
    required bool exiting,
  }) {
    final remaining = 1 - visibility;
    final sign = direction < 0 ? -1.0 : 1.0;
    var offset = Offset.zero;
    var scale = 1.0;
    var angle = 0.0;
    var opacity = visibility;
    switch (style) {
      case CoverTransitionStyle.softSlide:
        if (!exiting) return softSlideIncoming(direction, visibility);
        opacity = softSlideOldOpacity(direction, remaining);
        offset = Offset(-sign * 0.18 * remaining, 0.035 * remaining);
        scale = 1 - 0.09 * remaining;
        angle = sign < 0 ? 0.045 * remaining : 0;
      case CoverTransitionStyle.filmVertical:
        offset = Offset(0, sign * (exiting ? -1 : 1) * remaining);
        opacity = 1;
      case CoverTransitionStyle.filmHorizontal:
        offset = Offset(sign * (exiting ? -1 : 1) * remaining, 0);
        opacity = 1;
      case CoverTransitionStyle.flipHorizontal:
      case CoverTransitionStyle.flipVertical:
        final phase = exiting
            ? (remaining * 2).clamp(0.0, 1.0)
            : ((visibility - 0.5) * 2).clamp(0.0, 1.0);
        angle = sign * (exiting ? phase : -(1 - phase)) * math.pi / 2;
        opacity = exiting ? (phase < 1 ? 1 : 0) : (phase > 0 ? 1 : 0);
      case CoverTransitionStyle.stack:
        offset = Offset(
          sign * (exiting ? -0.18 : 0.24) * remaining,
          (exiting ? 0.06 : 0.10) * remaining,
        );
        scale = 1 - (exiting ? 0.08 : 0.10) * remaining;
        angle = sign * (exiting ? -0.04 : 0.06) * remaining;
      case CoverTransitionStyle.none:
        opacity = exiting ? 0 : 1;
      case CoverTransitionStyle.fade:
        break;
    }
    return CoverMotionFrame(
      offset: offset,
      scale: scale,
      angle: angle,
      opacity: opacity,
    );
  }

  static double softSlideOldOpacity(int direction, double progress) {
    if (direction >= 0) {
      final incoming = softSlideIncoming(direction, progress);
      final overlapX = (1 - incoming.offset.dx.abs()).clamp(0.0, 1.0);
      final overlapY = (1 - incoming.offset.dy.abs()).clamp(0.0, 1.0);
      return 1 - overlapX * overlapY;
    }
    if (progress <= frontLiftProgress) return 1;
    final incoming = softSlideIncoming(-1, progress);
    return (incoming.offset.dx.abs() / deckDistance).clamp(0.0, 1.0);
  }

  static double previousOldOpacity(double progress) =>
      softSlideOldOpacity(-1, progress);
}

class CoverFrameView extends StatelessWidget {
  final CoverMotionFrame frame;
  final CoverTransitionStyle style;
  final BorderRadius borderRadius;
  final bool exiting;
  final Widget child;

  const CoverFrameView({
    super.key,
    required this.frame,
    required this.style,
    required this.borderRadius,
    required this.exiting,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final flip =
        style == CoverTransitionStyle.flipHorizontal ||
        style == CoverTransitionStyle.flipVertical;
    final matrix = Matrix4.identity();
    if (flip && frame.angle.abs() > 0.00001) {
      matrix.setEntry(3, 2, 0.0011);
      if (style == CoverTransitionStyle.flipHorizontal) {
        matrix.rotateY(frame.angle);
      } else {
        matrix.rotateX(frame.angle);
      }
    } else if (frame.angle != 0) {
      matrix.rotateZ(frame.angle);
    }
    matrix.scaleByDouble(frame.scale, frame.scale, 1, 1);
    final film =
        style == CoverTransitionStyle.filmVertical ||
        style == CoverTransitionStyle.filmHorizontal;
    return IgnorePointer(
      ignoring: exiting,
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: film && frame.offset != Offset.zero
            ? Clip.antiAlias
            : Clip.none,
        child: Opacity(
          opacity: frame.opacity.clamp(0.0, 1.0),
          child: FractionalTranslation(
            translation: frame.offset,
            child: Transform(
              key: const ValueKey('cover_switch_transform'),
              alignment: Alignment.center,
              transform: matrix,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
