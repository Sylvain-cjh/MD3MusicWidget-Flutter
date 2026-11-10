import 'package:flutter/material.dart';



abstract final class SmoothSurfaceCorners {
  static const windowRadius = 40.0;
  static const settingsEdge = 16.0;
  static const settingsGroupInset = 8.0;
  static const settingsViewportRadius = windowRadius - settingsEdge;
  static const settingsCard = BorderRadius.all(
    Radius.circular(settingsViewportRadius - settingsGroupInset),
  );
  
  static const mediaStrip = BorderRadius.all(Radius.circular(18));
  static const navigation = BorderRadius.all(Radius.circular(22));
  static const menuRadius = 24.0;
  static const menuInset = 6.0;
  static const menu = BorderRadius.all(Radius.circular(menuRadius));
  static const menuItem = BorderRadius.all(
    Radius.circular(menuRadius - menuInset),
  );
  static const popoverRadius = 22.0;
  static const popoverRowInset = 4.0;
  static const popover = BorderRadius.all(Radius.circular(popoverRadius));
  static const popoverItem = BorderRadius.all(
    Radius.circular(popoverRadius - popoverRowInset),
  );
  static const control = BorderRadius.all(Radius.circular(14));
  static const small = BorderRadius.all(Radius.circular(12));

  
  
  static BorderRadius artwork({required double inset}) =>
      BorderRadius.circular((windowRadius - inset).clamp(18.0, windowRadius));

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
  const SmoothRoundedClip({
    super.key,
    required this.borderRadius,
    required this.child,
    this.composite = true,
  });
  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
    borderRadius: borderRadius,
    clipBehavior: composite ? Clip.antiAliasWithSaveLayer : Clip.antiAlias,
    child: child,
  );
}
