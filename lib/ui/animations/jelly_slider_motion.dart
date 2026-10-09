import 'package:flutter/physics.dart';


final class JellySliderMotion {
  static const pauseDelay = Duration(milliseconds: 80);
  static const spring = SpringDescription(mass: 1, stiffness: 420, damping: 27);
  static double stretchForVelocity(double velocity) =>
      (velocity / 1100).clamp(-1.0, 1.0);
  static SpringSimulation settle(
    double value,
    double target,
    double velocity,
  ) =>
      SpringSimulation(spring, value, target, velocity)
        ..tolerance = const Tolerance(distance: 0.001, velocity: 0.01);
}
