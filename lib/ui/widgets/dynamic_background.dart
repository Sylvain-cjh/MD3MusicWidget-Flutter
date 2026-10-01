import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import 'right_artwork_surface.dart';

class CircularRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Offset center;
  CircularRevealClipper({required this.fraction, required this.center});

  @override
  Path getClip(Size size) {
    final double maxRadius = 1500.0;
    final double safeFraction = fraction < 0.0 ? 0.0 : fraction;
    return Path()..addOval(
      Rect.fromCircle(center: center, radius: maxRadius * safeFraction),
    );
  }

  @override
  bool shouldReclip(CircularRevealClipper oldClipper) =>
      oldClipper.fraction != fraction || oldClipper.center != center;
}

class DitherNoisePainter extends CustomPainter {
  final Brightness brightness;
  static Picture? _cachedDark;
  static Picture? _cachedLight;
  static Size? _cachedSize;

  DitherNoisePainter(this.brightness);

  @override
  void paint(Canvas canvas, Size size) {
    if (_cachedSize != size) {
      _cachedDark?.dispose();
      _cachedLight?.dispose();
      _cachedDark = null;
      _cachedLight = null;
      _cachedSize = size;
    }
    if (brightness == Brightness.dark && _cachedDark != null) {
      canvas.drawPicture(_cachedDark!);
      return;
    }
    if (brightness == Brightness.light && _cachedLight != null) {
      canvas.drawPicture(_cachedLight!);
      return;
    }

    final recorder = PictureRecorder();
    final c = Canvas(recorder);
    final random = math.Random(42);

    
    
    
    final double baseAlpha = brightness == Brightness.dark ? 2.0 : 1.0;
    const double noiseDensity = 0.12;
    final int columns = (size.width.ceil() + 1) ~/ 2;
    final int rows = (size.height.ceil() + 1) ~/ 2;
    final int maxPoints = columns * rows;
    final Float32List lightPoints = Float32List(maxPoints * 2);
    final Float32List darkPoints = Float32List(maxPoints * 2);
    int lightIndex = 0;
    int darkIndex = 0;

    for (double y = 0; y < size.height; y += 2) {
      for (double x = 0; x < size.width; x += 2) {
        if (random.nextDouble() < noiseDensity) {
          final Float32List points = random.nextBool()
              ? lightPoints
              : darkPoints;
          final double pointX = x + random.nextDouble() * 2.0;
          final double pointY = y + random.nextDouble() * 2.0;
          if (identical(points, lightPoints)) {
            lightPoints[lightIndex++] = pointX;
            lightPoints[lightIndex++] = pointY;
          } else {
            darkPoints[darkIndex++] = pointX;
            darkPoints[darkIndex++] = pointY;
          }
        }
      }
    }

    final lightPaint = Paint()
      ..isAntiAlias = false
      ..color = Colors.white.withValues(alpha: baseAlpha / 255.0)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.square;
    final darkPaint = Paint()
      ..isAntiAlias = false
      ..color = Colors.black.withValues(alpha: baseAlpha / 255.0)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.square;

    if (brightness == Brightness.light) {
      lightPaint.blendMode = BlendMode.overlay;
      darkPaint.blendMode = BlendMode.overlay;
    }

    if (lightIndex > 0) {
      c.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(lightPoints, 0, lightIndex),
        lightPaint,
      );
    }
    if (darkIndex > 0) {
      c.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(darkPoints, 0, darkIndex),
        darkPaint,
      );
    }

    final picture = recorder.endRecording();
    if (brightness == Brightness.dark) _cachedDark = picture;
    if (brightness == Brightness.light) _cachedLight = picture;
    canvas.drawPicture(picture);
  }

  @override
  bool shouldRepaint(DitherNoisePainter oldDelegate) =>
      oldDelegate.brightness != brightness;
}



class _AnchoredBackgroundCanvas extends StatelessWidget {
  final double width;
  final double height;
  final double anchorHeight;
  final Widget child;

  const _AnchoredBackgroundCanvas({
    required this.width,
    required this.height,
    required this.anchorHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => OverflowBox(
    alignment: Alignment.topCenter,
    minWidth: width,
    maxWidth: width,
    minHeight: height,
    maxHeight: height,
    child: Transform.translate(
      offset: Offset(0, (anchorHeight - height) / 2),
      child: child,
    ),
  );
}

class DynamicBackground extends StatefulWidget {
  final double? anchorHeight;
  const DynamicBackground({super.key, this.anchorHeight});
  @override
  State<DynamicBackground> createState() => _DynamicBackgroundState();
}

class _DynamicBackgroundState extends State<DynamicBackground>
    with SingleTickerProviderStateMixin {
  static final ImageFilter _glowBlur = ImageFilter.blur(
    sigmaX: 80,
    sigmaY: 80,
    tileMode: TileMode.clamp,
  );
  late AnimationController _revealController;
  late CurvedAnimation _revealAnimation;
  late bool _glowLayerVisible;
  ImageProvider? _heldBackgroundProvider;
  ImageProvider? _heldCoverProvider;
  String _heldCoverKey = 'fallback';
  Timer? _heldArtworkReleaseTimer;

  void _releaseHeldArtwork() {
    if (!mounted ||
        AppState.coverProvider != null ||
        AppState.bgBlurProvider != null) {
      return;
    }
    _heldArtworkReleaseTimer?.cancel();
    _heldArtworkReleaseTimer = null;
    if (_heldBackgroundProvider == null && _heldCoverProvider == null) return;
    setState(() {
      _heldBackgroundProvider = null;
      _heldCoverProvider = null;
      _heldCoverKey = 'fallback';
    });
  }

  @override
  void initState() {
    super.initState();
    AppState.backgroundRevision.addListener(_handleBackgroundChanged);
    _glowLayerVisible = AppState.enableGlow;
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addStatusListener(_handleRevealStatus);
    _revealAnimation = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );
    if (AppState.enableGlow) {
      _revealController.value = 1.0;
    }
  }

  void _handleRevealStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed &&
        !AppState.enableGlow &&
        _glowLayerVisible &&
        mounted) {
      setState(() => _glowLayerVisible = false);
    }
  }

  void _handleBackgroundChanged() {
    if (!mounted) return;
    _heldArtworkReleaseTimer?.cancel();
    if (AppState.coverProvider == null && AppState.bgBlurProvider == null) {
      _heldArtworkReleaseTimer = Timer(
        const Duration(milliseconds: 500),
        _releaseHeldArtwork,
      );
    }
    if (AppState.enableGlow) {
      _glowLayerVisible = true;
      _revealController.forward();
    } else {
      _revealController.reverse();
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(DynamicBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (AppState.enableGlow &&
        _revealController.status != AnimationStatus.completed &&
        _revealController.status != AnimationStatus.forward) {
      _revealController.forward();
    } else if (!AppState.enableGlow &&
        _revealController.status != AnimationStatus.dismissed &&
        _revealController.status != AnimationStatus.reverse) {
      _revealController.reverse();
    }
  }

  @override
  void dispose() {
    _heldArtworkReleaseTimer?.cancel();
    AppState.backgroundRevision.removeListener(_handleBackgroundChanged);
    _revealAnimation.dispose();
    _revealController.dispose();
    super.dispose();
  }

  Widget _buildWaterfallGlow(
    ImageProvider bgProvider,
    String coverKey,
    double canvasW,
    double canvasH,
    double headerH,
  ) {
    final double seamOverlap = (headerH * 0.16).clamp(24.0, 48.0);
    final double headerBottom = (canvasH / 2) + (headerH / 2);
    return Stack(
      key: const ValueKey('waterfall-glow'),
      fit: StackFit.expand,
      children: [
        Positioned(
          
          
          
          top: headerBottom - seamOverlap,
          left: 0,
          right: 0,
          bottom: 0,
          child: FittedBox(
            fit: BoxFit.fill,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: canvasW,
              height: 1,
              child: OverflowBox(
                maxHeight: headerH,
                minHeight: headerH,
                alignment: Alignment.bottomCenter,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  child: Image(
                    key: ValueKey('${coverKey}_stretch'),
                    image: bgProvider,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    width: canvasW,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: (canvasH / 2) - (headerH / 2),
          left: 0,
          right: 0,
          height: headerH,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0.0, 0.85, 1.0],
            ).createShader(bounds),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              child: Image(
                key: ValueKey('${coverKey}_glow'),
                image: bgProvider,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWallpaperGlow(ImageProvider bgProvider, String coverKey) {
    return AnimatedSwitcher(
      key: const ValueKey('wallpaper-glow'),
      duration: const Duration(milliseconds: 800),
      child: Image(
        key: ValueKey('${coverKey}_wallpaper'),
        image: bgProvider,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = AppState.themeBrightness == Brightness.dark;

    const double canvasW = AppState.canvasWidth;
    const double canvasH = AppState.canvasHeight;
    final double headerH = AppState.glowHeaderHeight;

    final double luminance = AppState.currentScheme.surface.computeLuminance();

    final double dynamicDarkOverlay = (0.25 + (luminance * 0.50)).clamp(
      0.25,
      0.75,
    );
    final double dynamicLightOverlay = (0.25 + ((1.0 - luminance) * 0.40))
        .clamp(0.25, 0.65);

    final double universalDimOpacity = isDark
        ? dynamicDarkOverlay
        : dynamicLightOverlay;
    final Color overlayColor = isDark ? Colors.black : Colors.white;

    
    final activeBackground = AppState.bgBlurProvider ?? AppState.coverProvider;
    if (activeBackground != null) {
      _heldBackgroundProvider = activeBackground;
      _heldCoverKey = AppState.currentCoverVersion.isEmpty
          ? 'fallback'
          : AppState.currentCoverVersion;
    }
    if (AppState.coverProvider != null) {
      _heldCoverProvider = AppState.coverProvider;
    }
    final bgProvider = activeBackground ?? _heldBackgroundProvider;
    final coverKey = _heldCoverKey;

    
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final headerScale =
            constraints.maxWidth /
            AppState.innerPlayerWidthOf(WidgetLayout.horizontal);
        final rightCoverHeight =
            AppState.corePlayerHeightOf(WidgetLayout.horizontal) * headerScale;
        return Stack(
          children: [
            Positioned.fill(
              child: _AnchoredBackgroundCanvas(
                width: canvasW,
                height: canvasH,
                anchorHeight: widget.anchorHeight ?? constraints.maxHeight,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutQuart,
                  color: isDark
                      ? (AppState.enableGlow
                            ? AppState.currentScheme.surfaceContainerLow
                            : (AppState.enableOledTheme
                                  ? Colors.black
                                  : AppState
                                        .currentScheme
                                        .surfaceContainerHigh))
                      : (AppState.enableGlow
                            ? AppState.currentScheme.surface
                            : AppState.currentScheme.surfaceContainerHighest),
                ),
              ),
            ),

            if (bgProvider != null && _glowLayerVisible)
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: AppState.layoutSwitchDuration,
                  curve: Curves.easeOutCubic,
                  opacity: activeBackground == null ? 0.0 : 1.0,
                  onEnd: _releaseHeldArtwork,
                  child: _AnchoredBackgroundCanvas(
                    width: canvasW,
                    height: canvasH,
                    anchorHeight: widget.anchorHeight ?? constraints.maxHeight,
                    child: AnimatedBuilder(
                      animation: _revealAnimation,
                      builder: (context, child) {
                        return ClipPath(
                          clipper: CircularRevealClipper(
                            fraction: _revealAnimation.value,
                            center: AppState.revealCenter,
                          ),
                          child: child,
                        );
                      },
                      child: RepaintBoundary(
                        child: Transform.scale(
                          scale: 1.25,
                          child: ImageFiltered(
                            imageFilter: _glowBlur,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 600),
                              switchInCurve: Curves.easeInOutCubic,
                              switchOutCurve: Curves.easeInOutCubic,
                              layoutBuilder: (currentChild, previousChildren) =>
                                  Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ...previousChildren,
                                      ?currentChild,
                                    ],
                                  ),
                              child: AppState.glowMode == GlowMode.waterfall
                                  ? _buildWaterfallGlow(
                                      bgProvider,
                                      coverKey,
                                      canvasW,
                                      canvasH,
                                      headerH,
                                    )
                                  : _buildWallpaperGlow(bgProvider, coverKey),
                               













































































































                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            Positioned.fill(
              child: _AnchoredBackgroundCanvas(
                width: canvasW,
                height: canvasH,
                anchorHeight: widget.anchorHeight ?? constraints.maxHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      color: overlayColor.withValues(
                        alpha: universalDimOpacity,
                      ),
                    ),
                    FadeTransition(
                      opacity: _revealAnimation,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: DitherNoisePainter(AppState.themeBrightness),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_heldCoverProvider != null)
              Positioned(
                top: 0,
                right: 0,
                height: rightCoverHeight,
                width: math.min(rightCoverHeight, constraints.maxWidth),
                child: AnimatedOpacity(
                  opacity: AppState.isVertical || AppState.coverProvider == null
                      ? 0.0
                      : 1.0,
                  duration: AppState.layoutSwitchDuration,
                  curve: AppState.layoutSwitchCurve,
                  onEnd: _releaseHeldArtwork,
                  child: SizedBox.expand(
                    key: const ValueKey('background_right_artwork'),
                    child: RightArtworkSurface(
                      provider: _heldCoverProvider!,
                      coverKey: coverKey,
                      isPlaying: AppState.isPlaying,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
