import 'package:flutter/material.dart';

import '../../core/appState.dart';
import 'mediaGeometry.dart';
import 'smoothRoundedClip.dart';

class SpectrumGlassSurface extends StatelessWidget {
  final Widget child;

  const SpectrumGlassSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = AppState.currentScheme;
    return ClipRect(
      child: SmoothRoundedClip.mediaStrip(
        side: BorderSide(
          width: RoundedRasterScale.hairline(context),
          color: scheme.outlineVariant.withValues(alpha: 0.28),
        ),
        child: BackdropFilter(
          filter: MediaStripGlass.frost,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: MediaStripGlass.tint(scheme)),
            child: child,
          ),
        ),
      ),
    );
  }
}
