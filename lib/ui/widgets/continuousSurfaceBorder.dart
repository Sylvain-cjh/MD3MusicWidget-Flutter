import 'dart:math' as math;

import 'package:flutter/material.dart';



class ContinuousSurfaceBorder extends OutlinedBorder {
  const ContinuousSurfaceBorder({required this.borderRadius, super.side});

  final BorderRadiusGeometry borderRadius;

  static const _shoulder = 1.52;
  static const _midpoint = .1927;

  static double _midpointAt(double scale) =>
      _midpoint +
      (.244 - _midpoint) * ((1 - scale) / (1 - 1 / _shoulder)).clamp(0.0, 1.0);

  
  static (double, double) uniformProfile(Size size, double radius) {
    final requested = radius * _shoulder;
    final extent = math.min(requested, size.shortestSide / 2);
    return (extent, _midpointAt(requested > 0 ? extent / requested : 1));
  }

  static Path outline(Rect bounds, BorderRadius radius) {
    if (bounds.isEmpty) return Path();
    final corners = [
      radius.topRight,
      radius.bottomRight,
      radius.bottomLeft,
      radius.topLeft,
    ];
    double span(double value) => math.max(0, value) * _shoulder;
    double fit(double extent, double needed) =>
        needed > extent ? extent / needed : 1;
    final scale = [
      fit(bounds.width, span(corners[3].x) + span(corners[0].x)),
      fit(bounds.height, span(corners[0].y) + span(corners[1].y)),
      fit(bounds.width, span(corners[1].x) + span(corners[2].x)),
      fit(bounds.height, span(corners[2].y) + span(corners[3].y)),
    ].reduce(math.min);
    final m = _midpointAt(scale);
    final tips = [
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
      bounds.topLeft,
    ];
    const along = [Offset(-1, 0), Offset(0, -1), Offset(1, 0), Offset(0, 1)];
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final horizontal = i.isEven;
      final from =
          along[i] * (span(horizontal ? corners[i].x : corners[i].y) * scale);
      final to =
          along[(i + 1) % 4] *
          (span(horizontal ? corners[i].y : corners[i].x) * -scale);
      final tip = tips[i];
      final start = tip + from;
      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      if (from == Offset.zero || to == Offset.zero) {
        path
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(tip.dx + to.dx, tip.dy + to.dy);
        continue;
      }
      
      
      final middle = tip + (from + to) * m;
      final a = tip + from * (4 * m);
      final b = tip + from * (2 * m);
      final c = tip + to * (2 * m);
      final d = tip + to * (4 * m);
      final end = tip + to;
      path
        ..cubicTo(a.dx, a.dy, b.dx, b.dy, middle.dx, middle.dy)
        ..cubicTo(c.dx, c.dy, d.dx, d.dy, end.dx, end.dy);
    }
    return path..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      outline(rect, borderRadius.resolve(textDirection));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final inset = side.strokeInset;
    return outline(
      rect.deflate(inset),
      (borderRadius.resolve(textDirection) - BorderRadius.circular(inset))
          .resolve(textDirection),
    );
  }

  @override
  ContinuousSurfaceBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => ContinuousSurfaceBorder(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  ContinuousSurfaceBorder scale(double t) =>
      copyWith(side: side.scale(t), borderRadius: borderRadius * t);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) =>
      a is ContinuousSurfaceBorder ? a.lerpTo(this, t) : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is ContinuousSurfaceBorder
      ? ContinuousSurfaceBorder(
          side: BorderSide.lerp(side, b.side, t),
          borderRadius: BorderRadiusGeometry.lerp(
            borderRadius,
            b.borderRadius,
            t,
          )!,
        )
      : super.lerpTo(b, t);

  @override
  bool get preferPaintInterior => true;

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) =>
      canvas.drawPath(getOuterPath(rect, textDirection: textDirection), paint);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final resolved = borderRadius.resolve(textDirection);
    final offset = side.strokeOffset / 2;
    canvas.drawPath(
      outline(
        rect.inflate(offset),
        (resolved + BorderRadius.circular(offset)).resolve(textDirection),
      ),
      side.toPaint(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ContinuousSurfaceBorder &&
      other.side == side &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(side, borderRadius);
}

class ContinuousCornerClipper extends CustomClipper<Path> {
  const ContinuousCornerClipper(this.radius);

  final BorderRadius radius;

  @override
  Path getClip(Size size) =>
      ContinuousSurfaceBorder.outline(Offset.zero & size, radius);

  @override
  bool shouldReclip(ContinuousCornerClipper oldClipper) =>
      radius != oldClipper.radius;
}

class ContinuousCornerClip extends StatelessWidget {
  const ContinuousCornerClip({
    super.key,
    required this.borderRadius,
    required this.child,
    this.clipBehavior = Clip.antiAlias,
  });

  final BorderRadiusGeometry borderRadius;
  final Widget child;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) => clipBehavior == Clip.none
      ? child
      : ClipPath(
          clipBehavior: clipBehavior,
          clipper: ContinuousCornerClipper(
            borderRadius.resolve(Directionality.maybeOf(context)),
          ),
          child: child,
        );
}
