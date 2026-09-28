import 'dart:math' as math;

final class SettingsNavigationMotion {
  static const double pressScale = 1.14;
  static const double pressVerticalScale = 1.32;
  static const double maximumEdgeTravel = 16;
  static const double dampingAmplitude = 0.035;
  static const double maximumStretch = 0.22;
  static const double slowVelocity = 350;
  static const double fastVelocity = 1000;

  static double fastFraction(double velocityPixelsPerSecond) {
    final t =
        ((velocityPixelsPerSecond.abs() - slowVelocity) /
                (fastVelocity - slowVelocity))
            .clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double dampedIndex(double rawIndex, double velocityPixelsPerSecond) {
    final resistance = 1 - fastFraction(velocityPixelsPerSecond);
    return rawIndex -
        dampingAmplitude * math.sin(rawIndex * 2 * math.pi) * resistance;
  }

  static double signedStretch(double rawIndex, double velocityPixelsPerSecond) {
    final travel = math.sin(rawIndex * math.pi).abs();
    final movement = (velocityPixelsPerSecond.abs() / slowVelocity).clamp(
      0.0,
      1.0,
    );
    return maximumStretch *
        travel *
        movement *
        velocityPixelsPerSecond.sign *
        (1 - fastFraction(velocityPixelsPerSecond));
  }

  static double releaseImpulse(
    double velocityPixelsPerSecond,
    double slotWidth,
  ) {
    if (slotWidth <= 0) return 0;
    return (velocityPixelsPerSecond / slotWidth * 0.13).clamp(-3.0, 3.0);
  }

  static double elasticCenter(
    double requestedCenter,
    double slotWidth,
    double totalWidth, {
    bool reduceMotion = false,
  }) {
    final minimum = slotWidth / 2;
    final maximum = totalWidth - minimum;
    if (reduceMotion ||
        requestedCenter >= minimum && requestedCenter <= maximum) {
      return requestedCenter.clamp(minimum, maximum);
    }
    final boundary = requestedCenter < minimum ? minimum : maximum;
    final excess = requestedCenter - boundary;
    final limit = math.min(maximumEdgeTravel, slotWidth * 0.24);
    return boundary + excess / (1 + excess.abs() / limit);
  }
}
