import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/appState.dart';
import 'stableArtworkSurface.dart';



class RightArtworkSurface extends StatefulWidget {
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
  State<RightArtworkSurface> createState() => _RightArtworkSurfaceState();

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
}

final class _CachedFadeShader {
  final double length;
  final LinearGradient gradient;
  Rect? _bounds;
  Shader? _shader;

  _CachedFadeShader(this.length, {required bool vertical})
    : gradient = RightArtworkSurface._fadeGradient(length, vertical: vertical);

  Shader call(Rect bounds) {
    if (_bounds != bounds || _shader == null) {
      _bounds = bounds;
      _shader = gradient.createShader(bounds);
    }
    return _shader!;
  }
}

class _RightArtworkSurfaceState extends State<RightArtworkSurface> {
  _CachedFadeShader? _fadeX;
  _CachedFadeShader? _fadeY;
  double? _blurSigma;
  ImageFilter? _blur;
  Object? _imageKey;
  Widget? _imageChild;

  @override
  Widget build(BuildContext context) {
    final imageKey = (widget.provider, widget.coverKey);
    if (_imageKey != imageKey) {
      _imageKey = imageKey;
      _imageChild = RepaintBoundary(
        child: StableArtworkSurface(provider: widget.provider),
      );
    }
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: AppState.rightArtworkRevision,
        child: _imageChild,
        builder: (context, _, image) {
          final x = AppState.rightCoverEffectiveFadeX;
          final y = AppState.rightCoverEffectiveFadeY;
          if (_fadeX?.length != x) {
            _fadeX = _CachedFadeShader(x, vertical: false);
          }
          if (_fadeY?.length != y) {
            _fadeY = _CachedFadeShader(y, vertical: true);
          }
          if (_blurSigma != AppState.rightCoverBlur) {
            _blurSigma = AppState.rightCoverBlur;
            _blur = ImageFilter.blur(
              sigmaX: _blurSigma!,
              sigmaY: _blurSigma!,
              tileMode: TileMode.clamp,
            );
          }
          return ClipRect(
            child: ShaderMask(
              key: const ValueKey('right_artwork_vertical_fade'),
              blendMode: BlendMode.dstIn,
              shaderCallback: _fadeY!.call,
              child: ShaderMask(
                key: const ValueKey('right_artwork_horizontal_fade'),
                blendMode: BlendMode.dstIn,
                shaderCallback: _fadeX!.call,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: widget.isPlaying ? 1 : 0.2),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  child: ImageFiltered(
                    key: const ValueKey('right_artwork_softening'),
                    enabled: AppState.rightCoverBlur > 0,
                    imageFilter: _blur!,
                    child: image,
                  ),
                  builder: (context, brightness, child) {
                    final gain =
                        (1 - AppState.rightCoverDarkening) * brightness;
                    
                    
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
          );
        },
      ),
    );
  }
}
