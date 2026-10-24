import 'dart:math' as math;

import 'package:flutter/widgets.dart';


abstract final class TransportTactileMotion {
  static const pressSpring = SpringDescription(
    mass: 1,
    stiffness: 1100,
    damping: 62,
  );
  static const releaseSpring = SpringDescription(
    mass: 1,
    stiffness: 650,
    damping: 40,
  );

  static Offset pointerTarget(Offset point, Size size) {
    if (size.isEmpty || !point.dx.isFinite || !point.dy.isFinite) {
      return Offset.zero;
    }
    final normalized = Offset(
      (point.dx - size.width / 2) / (size.width / 2),
      (point.dy - size.height / 2) / (size.height / 2),
    );
    
    final radius = normalized.distance;
    final decay = math.exp(-1.8 * radius);
    final edge = math.exp(-1.8);
    return radius == 0
        ? Offset.zero
        : normalized /
              radius *
              ((1 - decay) / (1 + decay)) /
              ((1 - edge) / (1 + edge));
  }

  static Offset inertialTilt(Offset position, Offset velocity) => Offset(
    (position.dx + velocity.dx * .009).clamp(-1.1, 1.1),
    (position.dy + velocity.dy * .009).clamp(-1.1, 1.1),
  );
}
