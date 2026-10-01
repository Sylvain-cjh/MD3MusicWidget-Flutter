import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';



class RightArtworkSurface extends StatelessWidget {
  final ImageProvider provider;
  final String coverKey;
  final bool isPlaying;

  const RightArtworkSurface({
    super.key,
    required this.provider,
    required this.coverKey,
    required this.isPlaying,
  });

  static LinearGradient _fadeGradient(double length, {required bool vertical}) {
    const samples = 16;
    final span = vertical ? length : 0.6 + length * 0.4;
    final start = vertical ? 1 - span : 0.0;
    final colors = <Color>[];
    final stops = <double>[];
    if (vertical) {
      colors.add(Colors.white);
      stops.add(0);
    }
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final smooth = t * t * (3 - 2 * t);
      colors.add(
        Color.fromARGB(
          ((vertical ? 1 - smooth : smooth) * 255).round(),
          255,
          255,
          255,
        ),
      );
      stops.add(start + span * t);
    }
    if (!vertical) {
      colors.add(Colors.white);
      stops.add(1);
    }
    return LinearGradient(
      begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
      end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
      colors: colors,
      stops: stops,
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: AppState.rightArtworkRevision,
    child: RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: Image(
          key: ValueKey('${coverKey}_clear'),
          image: provider,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
        ),
      ),
    ),
    builder: (context, _, image) => ClipRect(
      child: ShaderMask(
        key: const ValueKey('right_artwork_vertical_fade'),
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => _fadeGradient(
          AppState.rightCoverEffectiveFadeY,
          vertical: true,
        ).createShader(bounds),
        child: ShaderMask(
          key: const ValueKey('right_artwork_horizontal_fade'),
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => _fadeGradient(
            AppState.rightCoverEffectiveFadeX,
            vertical: false,
          ).createShader(bounds),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: isPlaying ? 1 : 0.2),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            child: ImageFiltered(
              key: const ValueKey('right_artwork_softening'),
              enabled: AppState.rightCoverBlur > 0,
              imageFilter: ImageFilter.blur(
                sigmaX: AppState.rightCoverBlur,
                sigmaY: AppState.rightCoverBlur,
                tileMode: TileMode.clamp,
              ),
              child: image,
            ),
            builder: (context, brightness, child) {
              final gain = (1 - AppState.rightCoverDarkening) * brightness;
              
              
              return ColorFiltered(
                key: const ValueKey('right_artwork_dimming'),
                colorFilter: ColorFilter.matrix([
                  gain,
                  0,
                  0,
                  0,
                  0,
                  0,
                  gain,
                  0,
                  0,
                  0,
                  0,
                  0,
                  gain,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: child,
              );
            },
          ),
        ),
      ),
    ),
  );
}
