import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/appState.dart';
import 'smoothRoundedClip.dart';

class SpectrumGlassSurface extends StatelessWidget {
  final Widget child;

  const SpectrumGlassSurface({super.key, required this.child});

  static final ImageFilter _blur = ImageFilter.blur(sigmaX: 13, sigmaY: 13);

  @override
  Widget build(BuildContext context) {
    final scheme = AppState.currentScheme;
    final radius = BorderRadius.circular(24);
    return ClipRect(
      child: SmoothRoundedClip(
        borderRadius: radius,
        child: BackdropFilter(
          filter: _blur,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surfaceContainerHigh.withValues(alpha: 0.58),
                  scheme.primaryContainer.withValues(alpha: 0.22),
                  scheme.surface.withValues(alpha: 0.48),
                ],
              ),
              borderRadius: radius,
              border: Border.all(
                width: RoundedRasterScale.hairline(context),
                color: scheme.outlineVariant.withValues(alpha: 0.42),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
