import 'package:flutter/material.dart';
import '../../core/appState.dart';
import 'continuousSurfaceBorder.dart';


final class SettingsControlShape {
  static const referenceHeight = 50.0;
  static ContinuousSurfaceBorder borderFor(MD3Shape shape) => switch (shape) {
    
    
    MD3Shape.stadium || MD3Shape.circle => const ContinuousSurfaceBorder(
      borderRadius: BorderRadius.all(Radius.circular(referenceHeight / 2)),
    ),
    MD3Shape.roundedExtraSmall => const ContinuousSurfaceBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
    MD3Shape.roundedSmall => const ContinuousSurfaceBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
    MD3Shape.roundedMedium => const ContinuousSurfaceBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    MD3Shape.roundedLarge => const ContinuousSurfaceBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
    ),
    MD3Shape.roundedExtraLarge => const ContinuousSurfaceBorder(
      borderRadius: BorderRadius.all(Radius.circular(28)),
    ),
  };

  static ShapeBorder handleBorder(MD3Shape shape, double height) =>
      borderFor(shape).scale(height / referenceHeight);
}
