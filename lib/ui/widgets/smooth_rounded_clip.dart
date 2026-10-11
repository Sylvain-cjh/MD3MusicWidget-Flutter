import 'package:flutter/material.dart';


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
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius,
    clipBehavior: composite ? Clip.antiAliasWithSaveLayer : Clip.antiAlias,
    child: child,
  );
}
