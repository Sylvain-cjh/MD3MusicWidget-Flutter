import 'package:flutter/material.dart';


abstract final class AppTypography {
  static bool isMiSans(String? family) =>
      family == 'MiSans' || family == 'MiSans VF';

  
  
  static double variableWeight(double weight, String? family) {
    final logical = weight.isFinite ? weight.clamp(100.0, 900.0) : 500.0;
    if (!isMiSans(family)) return logical;
    const anchors = [
      (100.0, 150.0),
      (200.0, 200.0),
      (300.0, 250.0),
      (350.0, 305.0),
      (400.0, 330.0),
      (500.0, 380.0),
      (550.0, 450.0),
      (600.0, 520.0),
      (700.0, 630.0),
      (900.0, 700.0),
    ];
    for (var i = 1; i < anchors.length; i++) {
      final left = anchors[i - 1], right = anchors[i];
      if (logical <= right.$1) {
        final t = (logical - left.$1) / (right.$1 - left.$1);
        return left.$2 + (right.$2 - left.$2) * t;
      }
    }
    return 700;
  }

  static final _segoeFamily = RegExp(
    r'^Segoe UI Variable(?: (?:Text|Small|Display))?$',
    caseSensitive: false,
  );
  static bool hasSegoeOpticalSize(String? family) =>
      family != null && _segoeFamily.hasMatch(family.trim());

  static double opticalSize(double fontSize, {double displayScale = 1}) {
    final size = fontSize.isFinite && fontSize > 0 ? fontSize : 14.0;
    final scale = displayScale.isFinite && displayScale > 0
        ? displayScale
        : 1.0;
    
    return (size * scale * .75).clamp(8.0, 36.0);
  }

  static List<FontVariation> variations({
    required double weight,
    required String? family,
    double? fontSize,
    double displayScale = 1,
  }) => [
    FontVariation('wght', variableWeight(weight, family)),
    if (fontSize != null && hasSegoeOpticalSize(family))
      FontVariation('opsz', opticalSize(fontSize, displayScale: displayScale)),
  ];

  static TextTheme refineTheme(
    TextTheme base, {
    required String family,
    required List<String> fallback,
    double displayScale = 1,
  }) {
    TextStyle? refine(TextStyle? style) {
      if (style == null) return null;
      return style.copyWith(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontVariations: isMiSans(family)
            ? [
                ...?style.fontVariations?.where(
                  (v) => v.axis != 'wght' && v.axis != 'opsz',
                ),
                FontVariation(
                  'wght',
                  variableWeight(
                    (style.fontWeight ?? FontWeight.w400).value.toDouble(),
                    family,
                  ),
                ),
              ]
            : hasSegoeOpticalSize(family)
            ? [
                ...?style.fontVariations?.where((v) => v.axis != 'opsz'),
                FontVariation(
                  'opsz',
                  opticalSize(style.fontSize ?? 14, displayScale: displayScale),
                ),
              ]
            : style.fontVariations,
      );
    }

    return TextTheme(
      displayLarge: refine(base.displayLarge),
      displayMedium: refine(base.displayMedium),
      displaySmall: refine(base.displaySmall),
      headlineLarge: refine(base.headlineLarge),
      headlineMedium: refine(base.headlineMedium),
      headlineSmall: refine(base.headlineSmall),
      titleLarge: refine(base.titleLarge),
      titleMedium: refine(base.titleMedium),
      titleSmall: refine(base.titleSmall),
      bodyLarge: refine(base.bodyLarge),
      bodyMedium: refine(base.bodyMedium),
      bodySmall: refine(base.bodySmall),
      labelLarge: refine(base.labelLarge),
      labelMedium: refine(base.labelMedium),
      labelSmall: refine(base.labelSmall),
    );
  }
}



class AppTypographyTheme extends StatelessWidget {
  final String family;
  final List<String> fallback;
  final double displayScale;
  final Widget child;
  const AppTypographyTheme({
    super.key,
    required this.family,
    required this.fallback,
    required this.displayScale,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: AppTypography.refineTheme(
          base.textTheme,
          family: family,
          fallback: fallback,
          displayScale: displayScale,
        ),
        primaryTextTheme: AppTypography.refineTheme(
          base.primaryTextTheme,
          family: family,
          fallback: fallback,
          displayScale: displayScale,
        ),
      ),
      child: child,
    );
  }
}
