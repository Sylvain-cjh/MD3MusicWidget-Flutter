import 'package:flutter/material.dart';

import 'continuousSurfaceBorder.dart';



abstract final class SmoothSurfaceCorners {
  static const windowRadius = 40.0;
  static const settingsEdge = 16.0;
  static const settingsGroupInset = 8.0;
  static const settingsViewportRadius = windowRadius - settingsEdge;
  static const settingsViewport = BorderRadius.all(
    Radius.circular(settingsViewportRadius),
  );
  static const settingsCard = BorderRadius.all(
    Radius.circular(settingsViewportRadius - settingsGroupInset),
  );
  
  static const mediaStrip = BorderRadius.all(Radius.circular(18));
  
  
  
  static const portraitArtwork = mediaStrip;
  static const navigationInset = 3.0;
  static const menuRadius = 24.0;
  static const menuInset = 6.0;
  static const menu = BorderRadius.all(Radius.circular(menuRadius));
  static const menuItem = BorderRadius.all(
    Radius.circular(menuRadius - menuInset),
  );
  static const popoverRadius = 22.0;
  static const popoverRowInset = 6.0;
  static const popover = BorderRadius.all(Radius.circular(popoverRadius));
  static const popoverItem = BorderRadius.all(
    Radius.circular(popoverRadius - popoverRowInset),
  );
  static const control = BorderRadius.all(Radius.circular(14));
  static const small = BorderRadius.all(Radius.circular(12));
  static const dialog = ContinuousSurfaceBorder(borderRadius: popover);

  
  
  static BorderRadius artwork({required double inset, double? topInset}) =>
      BorderRadius.all(
        Radius.elliptical(
          (windowRadius - inset).clamp(8.0, windowRadius),
          (windowRadius - (topInset ?? inset)).clamp(8.0, windowRadius),
        ),
      );

  static ShapeBorder navigationTrack(ShapeBorder indicator) =>
      indicator is ContinuousSurfaceBorder
      ? shape(
          indicator.borderRadius.add(
            const BorderRadius.all(Radius.circular(navigationInset)),
          ),
        )
      : indicator;

  static ContinuousSurfaceBorder shape(
    BorderRadiusGeometry radius, {
    BorderSide side = BorderSide.none,
  }) => ContinuousSurfaceBorder(borderRadius: radius, side: side);

  static const controlInput = ShapedInputBorder(
    shape: ContinuousSurfaceBorder(borderRadius: control),
  );
  static const smallInput = ShapedInputBorder(
    shape: ContinuousSurfaceBorder(borderRadius: small),
  );
}


class RoundedRasterScale extends InheritedWidget {
  final double scale;
  const RoundedRasterScale({
    super.key,
    required this.scale,
    required super.child,
  });
  static double hairline(BuildContext context, {double? scale}) {
    final factor =
        scale ??
        context
            .dependOnInheritedWidgetOfExactType<RoundedRasterScale>()
            ?.scale ??
        1;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return 1 /
        ((factor.isFinite && factor > 0 ? factor : 1) * (dpr > 0 ? dpr : 1));
  }

  @override
  bool updateShouldNotify(RoundedRasterScale oldWidget) =>
      scale != oldWidget.scale;
}




class SmoothRoundedClip extends StatelessWidget {
  final BorderRadiusGeometry borderRadius;
  final Widget child;
  final bool composite;
  final BorderSide side;
  const SmoothRoundedClip({
    super.key,
    required this.borderRadius,
    required this.child,
    this.composite = true,
    this.side = BorderSide.none,
  });

  const SmoothRoundedClip.mediaStrip({
    super.key,
    required this.child,
    this.side = BorderSide.none,
  }) : borderRadius = SmoothSurfaceCorners.mediaStrip,
       composite = true;

  @override
  Widget build(BuildContext context) {
    final clip = composite ? Clip.antiAliasWithSaveLayer : Clip.antiAlias;
    final content = side.style == BorderStyle.none || side.width <= 0
        ? child
        : CustomPaint(
            foregroundPainter: _InnerRim(
              borderRadius.resolve(Directionality.maybeOf(context)),
              side,
            ),
            child: child,
          );
    return ContinuousCornerClip(
      borderRadius: borderRadius,
      clipBehavior: clip,
      child: content,
    );
  }
}



class _InnerRim extends CustomPainter {
  const _InnerRim(this.radius, this.side);

  final BorderRadius radius;
  final BorderSide side;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || side.color.a == 0) return;
    final bounds = Offset.zero & size;
    final width = side.strokeInset;
    if (width <= 0) return;
    
    
    canvas.drawPath(
      ContinuousSurfaceBorder.outline(bounds, radius),
      Paint()
        ..color = side.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2,
    );
  }

  @override
  bool shouldRepaint(_InnerRim oldDelegate) =>
      radius != oldDelegate.radius || side != oldDelegate.side;
}
