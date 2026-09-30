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
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.white, Colors.white, Colors.transparent],
          stops: [0, 1 - AppState.rightCoverFadeLength, 1],
        ).createShader(bounds),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [Colors.transparent, Colors.white],
            stops: [0, 0.6 + AppState.rightCoverFadeLength * 0.4],
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
            builder: (context, brightness, child) => DecoratedBox(
              key: const ValueKey('right_artwork_dimming'),
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: 1 - (1 - AppState.rightCoverDarkening) * brightness,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
