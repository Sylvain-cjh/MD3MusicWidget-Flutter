import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/appState.dart';
import 'coverMotionFrame.dart';



class CoverContentTransition extends StatefulWidget {
  static const duration = CoverMotionGeometry.normalDuration;
  static const reducedDuration = CoverMotionGeometry.reducedDuration;

  final CoverTransitionStyle style;
  final CoverTransitionStyle Function()? exitStyleResolver;
  final Animation<double> animation;
  final int direction;
  final int Function()? exitDirectionResolver;
  final BorderRadius borderRadius;
  final bool reduceMotion;
  final Widget child;
  final CoverMotionFrame? frameOverride;
  final bool? exitingOverride;

  const CoverContentTransition({
    super.key,
    required this.style,
    this.exitStyleResolver,
    required this.animation,
    required this.direction,
    this.exitDirectionResolver,
    required this.borderRadius,
    required this.reduceMotion,
    required this.child,
    this.frameOverride,
    this.exitingOverride,
  });

  @override
  State<CoverContentTransition> createState() => _CoverContentTransitionState();
}

class _CoverContentTransitionState extends State<CoverContentTransition> {
  late bool _exiting;
  CoverTransitionStyle? _exitStyle;
  int? _exitDirection;
  double _exitStartValue = 1;
  ({Offset offset, double scale, double angle, double opacity})
  _lastIncomingFrame = (offset: Offset.zero, scale: 1, angle: 0, opacity: 1);
  ({Offset offset, double scale, double angle, double opacity})?
  _interruptedFrame;

  @override
  void initState() {
    super.initState();
    _exiting = widget.animation.status == AnimationStatus.reverse;
    if (_exiting) _captureExit();
    widget.animation.addStatusListener(_handleStatus);
  }

  void _captureExit() {
    _exitStyle = widget.exitStyleResolver?.call() ?? widget.style;
    _exitDirection = widget.exitDirectionResolver?.call() ?? widget.direction;
    _exitStartValue = widget.animation.value;
    _interruptedFrame = _exitStartValue < 0.99999 ? _lastIncomingFrame : null;
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) return;
    final exiting = status == AnimationStatus.reverse;
    if (exiting == _exiting || !mounted) return;
    setState(() {
      _exiting = exiting;
      if (exiting) _captureExit();
    });
  }

  @override
  void didUpdateWidget(covariant CoverContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation == oldWidget.animation) return;
    oldWidget.animation.removeStatusListener(_handleStatus);
    widget.animation.addStatusListener(_handleStatus);
    _exiting = widget.animation.status == AnimationStatus.reverse;
    if (_exiting) _captureExit();
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.frameOverride case final frame?) {
      return CoverFrameView(
        frame: frame,
        style: widget.reduceMotion ? CoverTransitionStyle.fade : widget.style,
        borderRadius: widget.borderRadius,
        exiting: widget.exitingOverride ?? false,
        child: widget.child,
      );
    }
    final style = _exiting ? (_exitStyle ?? widget.style) : widget.style;
    final direction = (_exiting ? _exitDirection : widget.direction) ?? 1;
    return AnimatedBuilder(
      animation: widget.animation,
      child: widget.child,
      builder: (context, child) {
        final visibility = widget.animation.value.clamp(0.0, 1.0);
        final remaining = 1 - visibility;
        final sign = direction < 0 ? -1.0 : 1.0;
        var offset = Offset.zero;
        var scale = 1.0;
        var angle = 0.0;
        var opacity = visibility;
        final film =
            style == CoverTransitionStyle.filmVertical ||
            style == CoverTransitionStyle.filmHorizontal;
        final flip =
            style == CoverTransitionStyle.flipHorizontal ||
            style == CoverTransitionStyle.flipVertical;

        final effectiveStyle =
            widget.reduceMotion && style != CoverTransitionStyle.none
            ? CoverTransitionStyle.fade
            : style;
        switch (effectiveStyle) {
          case CoverTransitionStyle.softSlide:
            final frame = CoverMotionGeometry.frameFor(
              effectiveStyle,
              direction,
              visibility,
              exiting: _exiting,
            );
            offset = frame.offset;
            scale = frame.scale;
            angle = frame.angle;
            opacity = frame.opacity;
          case CoverTransitionStyle.filmVertical:
            offset = Offset(0, sign * (_exiting ? -1 : 1) * remaining);
            opacity = 1;
          case CoverTransitionStyle.filmHorizontal:
            offset = Offset(sign * (_exiting ? -1 : 1) * remaining, 0);
            opacity = 1;
          case CoverTransitionStyle.flipHorizontal:
          case CoverTransitionStyle.flipVertical:
            
            
            final phase = _exiting
                ? (remaining * 2).clamp(0.0, 1.0)
                : ((visibility - 0.5) * 2).clamp(0.0, 1.0);
            angle = sign * (_exiting ? phase : -(1 - phase)) * math.pi / 2;
            opacity = _exiting ? (phase < 1 ? 1 : 0) : (phase > 0 ? 1 : 0);
          case CoverTransitionStyle.stack:
            offset = Offset(
              sign * (_exiting ? -0.18 : 0.24) * remaining,
              (_exiting ? 0.06 : 0.10) * remaining,
            );
            scale = 1 - (_exiting ? 0.08 : 0.10) * remaining;
            angle = sign * (_exiting ? -0.04 : 0.06) * remaining;
          case CoverTransitionStyle.none:
            opacity = _exiting ? 0 : 1;
          case CoverTransitionStyle.fade:
            break;
        }

        final start = _interruptedFrame;
        if (_exiting &&
            start != null &&
            !widget.reduceMotion &&
            effectiveStyle != CoverTransitionStyle.none) {
          final progress = _exitStartValue > 0.00001
              ? (1 - visibility / _exitStartValue).clamp(0.0, 1.0)
              : 1.0;
          final targetOffset = switch (effectiveStyle) {
            CoverTransitionStyle.softSlide => Offset(-sign * 0.18, 0.035),
            CoverTransitionStyle.filmVertical => Offset(0, -sign),
            CoverTransitionStyle.filmHorizontal => Offset(-sign, 0),
            CoverTransitionStyle.stack => Offset(-sign * 0.18, 0.06),
            _ => Offset.zero,
          };
          final targetScale = switch (effectiveStyle) {
            CoverTransitionStyle.softSlide => 0.91,
            CoverTransitionStyle.stack => 0.92,
            _ => 1.0,
          };
          final targetAngle = flip
              ? sign * math.pi / 2
              : effectiveStyle == CoverTransitionStyle.softSlide
              ? (sign < 0 ? 0.045 : 0)
              : effectiveStyle == CoverTransitionStyle.stack
              ? -sign * 0.04
              : 0.0;
          offset = Offset.lerp(start.offset, targetOffset, progress)!;
          scale = start.scale + (targetScale - start.scale) * progress;
          angle = start.angle + (targetAngle - start.angle) * progress;
          opacity = start.opacity * (1 - progress);
        }
        if (!_exiting) {
          _lastIncomingFrame = (
            offset: offset,
            scale: scale,
            angle: angle,
            opacity: opacity,
          );
        }

        final transform = Matrix4.identity();
        if (flip && !widget.reduceMotion && angle.abs() > 0.00001) {
          transform.setEntry(3, 2, 0.0011);
          if (style == CoverTransitionStyle.flipHorizontal) {
            transform.rotateY(angle);
          } else {
            transform.rotateX(angle);
          }
        } else if (angle != 0) {
          transform.rotateZ(angle);
        }
        transform.scaleByDouble(scale, scale, 1, 1);

        return IgnorePointer(
          ignoring: _exiting,
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            clipBehavior: film && !widget.reduceMotion && remaining > 0.00001
                ? Clip.antiAlias
                : Clip.none,
            child: Opacity(
              opacity: opacity,
              child: FractionalTranslation(
                translation: offset,
                child: Transform(
                  key: const ValueKey('cover_switch_transform'),
                  alignment: Alignment.center,
                  transform: transform,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}



class CoverTransitionStack extends StatelessWidget {
  static const frontLiftProgress = 0.5;
  final Animation<double> animation;
  final CoverTransitionStyle style;
  final int direction;
  final bool reduceMotion;
  final BorderRadius borderRadius;
  final Widget currentChild;
  final List<Widget> previousChildren;

  const CoverTransitionStack({
    super.key,
    required this.animation,
    required this.style,
    required this.direction,
    required this.reduceMotion,
    required this.borderRadius,
    required this.currentChild,
    required this.previousChildren,
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final softSlide =
          style == CoverTransitionStyle.softSlide && !reduceMotion;
      final behind = softSlide && direction < 0 && animation.value < 1;
      return ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: softSlide && animation.value < 0.99999
            ? Clip.antiAliasWithSaveLayer
            : Clip.none,
        child: Stack(
          key: const ValueKey('cover_layer_stack'),
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: behind
              ? [currentChild, ...previousChildren]
              : [...previousChildren, currentChild],
        ),
      );
    },
  );
}
