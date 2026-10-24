import 'package:flutter/material.dart';
import '../../core/appState.dart';


final class SettingsControlShape {
  static const referenceHeight = 50.0;
  static ShapeBorder borderFor(MD3Shape shape) => switch (shape) {
    MD3Shape.stadium || MD3Shape.circle => const StadiumBorder(),
    MD3Shape.roundedExtraSmall => const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
    MD3Shape.roundedSmall => const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
    MD3Shape.roundedMedium => const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    MD3Shape.roundedLarge => const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(20)),
    ),
    MD3Shape.roundedExtraLarge => const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(28)),
    ),
  };

  static ShapeBorder handleBorder(MD3Shape shape, double height) =>
      borderFor(shape).scale(height / referenceHeight);
}
