import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../animations/layoutMorphMotion.dart';



class LayoutBackdropBlend extends StatelessWidget {
  final LayoutMorphMotion motion;
  final ui.Image? previous;
  final Size targetSize;
  final Widget child;
  const LayoutBackdropBlend({
    super.key,
    required this.motion,
    required this.previous,
    required this.targetSize,
    required this.child,
  });
  static const blurSigma = 6.0;
  
  
  static const _blurInputMargin = blurSigma * 4 + 2;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    child: FittedBox(
      
      fit: BoxFit.cover,
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        child: ClipRect(
          child: SizedBox(
            width: targetSize.width,
            height: targetSize.height,
            child: child,
          ),
        ),
      ),
    ),
    builder: (context, live) {
      final enabled =
          (motion.active || motion.holding) &&
          !MediaQuery.disableAnimationsOf(context);
      final p = enabled
          ? (motion.holding && motion.freshBackdrop ? 0.0 : motion.progress)
          : 1.0;
      final filterLive = enabled && p < .99999;
      final liveSigma = blurSigma * (1 - p);
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            enabled: filterLive,
            imageFilter: ui.ImageFilter.blur(
              sigmaX: liveSigma,
              sigmaY: liveSigma,
              tileMode: ui.TileMode.clamp,
            ),
            
            
            
            child: ClipRect(
              clipBehavior: filterLive ? Clip.hardEdge : Clip.none,
              clipper: const _BlurInputClip(),
              child: live,
            ),
          ),
          if (enabled && previous != null && p < 1)
            IgnorePointer(
              child: Opacity(
                opacity: 1 - p,
                child: ImageFiltered(
                  enabled: p > .00001,
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: blurSigma * p,
                    sigmaY: blurSigma * p,
                    tileMode: ui.TileMode.clamp,
                  ),
                  child: RawImage(
                    image: previous,
                    fit: BoxFit.cover,
                    alignment: Alignment.topLeft,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _BlurInputClip extends CustomClipper<Rect> {
  const _BlurInputClip();

  @override
  Rect getClip(Size size) =>
      (Offset.zero & size).inflate(LayoutBackdropBlend._blurInputMargin);

  @override
  bool shouldReclip(_BlurInputClip oldClipper) => false;
}
