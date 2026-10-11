import 'dart:math' as math;
import 'package:flutter/physics.dart';


final class JellySliderMotion {
  static const pauseDelay = Duration(milliseconds: 60);
  static const pressWidth = 1.08;
  static const pressHeight = 1.16;
  static const maximumElongation = 0.16;
  static const maximumCompression = 0.07;
  static const maximumShear = 0.05;
  static const pressSpring = SpringDescription(
    mass: 1,
    stiffness: 760,
    damping: 55.2,
  );
  static const followSpring = SpringDescription(
    mass: 1,
    stiffness: 900,
    damping: 60,
  );
  static const returnSpring = SpringDescription(
    mass: 1,
    stiffness: 700,
    damping: 53,
  );

  
  static double filteredVelocity(
    double previous,
    double delta,
    double seconds,
  ) {
    if (!delta.isFinite || !seconds.isFinite) return 0;
    final dt = seconds > 0 ? seconds : 1 / 120;
    final speed = (delta / dt).clamp(-3000.0, 3000.0);
    final blend = 1 - math.exp(-dt / 0.022);
    return previous + (speed - previous) * blend;
  }

  
  static double stretchForVelocity(double velocity) => velocity.isFinite
      ? math.sqrt((velocity.abs() / 700).clamp(0.0, 1.0)) * velocity.sign
      : 0;

  static double leanForVelocity(double velocity) =>
      velocity.isFinite ? (velocity / 320).clamp(-1.0, 1.0) : 0;

  static SpringSimulation settle(
    double value,
    double target,
    double velocity, {
    SpringDescription spring = returnSpring,
  }) =>
      SpringSimulation(spring, value, target, velocity)
        ..tolerance = const Tolerance(distance: 0.002, velocity: 0.02);
}
