import 'dart:math' as math;

import 'package:flutter/material.dart';



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
  static const dialog = RoundedSuperellipseBorder(borderRadius: popover);

  
  
  static BorderRadius artwork({required double inset, double? topInset}) =>
      BorderRadius.all(
        Radius.elliptical(
          (windowRadius - inset).clamp(8.0, windowRadius),
          (windowRadius - (topInset ?? inset)).clamp(8.0, windowRadius),
        ),
      );

  static ShapeBorder navigationTrack(ShapeBorder indicator) =>
      indicator is RoundedSuperellipseBorder
      ? shape(
          indicator.borderRadius.add(
            const BorderRadius.all(Radius.circular(navigationInset)),
          ),
        )
      : indicator;

  static RoundedSuperellipseBorder shape(
    BorderRadiusGeometry radius, {
    BorderSide side = BorderSide.none,
  }) => RoundedSuperellipseBorder(borderRadius: radius, side: side);
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
  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: borderRadius,
    clipBehavior: composite ? Clip.antiAliasWithSaveLayer : Clip.antiAlias,
    child: side.style == BorderStyle.none || side.width <= 0
        ? child
        : CustomPaint(
            foregroundPainter: _InnerRim(
              borderRadius.resolve(Directionality.maybeOf(context)),
              side,
            ),
            child: child,
          ),
  );
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
    final rim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds.inflate(math.max(2.0, width)));
    if (width * 2 < size.shortestSide) {
      rim.addRSuperellipse(radius.toRSuperellipse(bounds).deflate(width));
    }
    canvas.drawPath(rim, Paint()..color = side.color);
  }

  @override
  bool shouldRepaint(_InnerRim oldDelegate) =>
      radius != oldDelegate.radius || side != oldDelegate.side;
}
