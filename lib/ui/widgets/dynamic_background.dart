import 'dart:async';
import 'dart:collection';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../core/blurred_artwork_provider.dart';
import '../../core/widget_diagnostics.dart';
import 'right_artwork_surface.dart';
import 'stable_artwork_surface.dart';

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
  static final LinkedHashMap<(Size, Brightness), Picture> _pictures =
      LinkedHashMap();
  static const maximumRetainedBytes = 2 * 1024 * 1024;
  static int debugBuilds = 0;
  static int get retainedBytes => _pictures.values.fold(
    0,
    (total, picture) => total + picture.approximateBytesUsed,
  );
  static int get cachedPictures => _pictures.length;
  static void clearCache() {
    for (final picture in _pictures.values) {
      picture.dispose();
    }
    _pictures.clear();
  }

  DitherNoisePainter(this.brightness);

  @override
  void paint(Canvas canvas, Size size) {
    if (WidgetDiagnostics.enabled && WidgetDiagnostics.suppressDither) return;
    final key = (size, brightness);
    final cached = _pictures.remove(key);
    if (cached != null) {
      _pictures[key] = cached;
      canvas.drawPicture(cached);
      return;
    }
    debugBuilds++;

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
    canvas.drawPicture(picture);
    if (picture.approximateBytesUsed > maximumRetainedBytes) {
      picture.dispose();
      return;
    }
    _pictures[key] = picture;
    while (_pictures.length > 6 || retainedBytes > maximumRetainedBytes) {
      _pictures.remove(_pictures.keys.first)!.dispose();
    }
  }

  @override
  bool shouldRepaint(DitherNoisePainter oldDelegate) =>
      oldDelegate.brightness != brightness;
}



class _AnchoredBackgroundCanvas extends StatelessWidget {
  final double width;
  final double height;
  final double anchorHeight;
  final double? anchorWidth;
  final double anchorLeft;
  final Widget child;

  const _AnchoredBackgroundCanvas({
    required this.width,
    required this.height,
    required this.anchorHeight,
    this.anchorWidth,
    this.anchorLeft = 0,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => OverflowBox(
    alignment: anchorWidth == null ? Alignment.topCenter : Alignment.topLeft,
    minWidth: width,
    maxWidth: width,
    minHeight: height,
    maxHeight: height,
    child: Transform.translate(
      offset: Offset(
        anchorWidth == null ? 0 : anchorLeft + (anchorWidth! - width) / 2,
        (anchorHeight - height) / 2,
      ),
      child: child,
    ),
  );
}

class DynamicBackground extends StatefulWidget {
  final double? anchorHeight;
  final double? anchorWidth;
  final double anchorLeft;
  final bool? verticalLayout;
  final bool animateArtworkReplacement;
  const DynamicBackground({
    super.key,
    this.anchorHeight,
    this.anchorWidth,
    this.anchorLeft = 0,
    this.verticalLayout,
    this.animateArtworkReplacement = true,
  });

  
  
  static Future<void> prepareLayout(
    BuildContext context,
    WidgetLayout layout,
  ) async {
    final source = AppState.bgBlurProvider ?? AppState.coverProvider;
    if (!AppState.enableGlow || source == null) return;
    await precacheImage(
      BlurredArtworkProvider(
        source: source,
        identity: AppState.currentCoverVersion.isEmpty
            ? 'fallback'
            : AppState.currentCoverVersion,
        waterfall: AppState.glowMode == GlowMode.waterfall,
        headerHeight: AppState.glowMode == GlowMode.waterfall
            ? AppState.glowHeaderHeightOf(layout)
            : 0,
        pixelScale:
            MediaQuery.devicePixelRatioOf(context) *
            AppState.componentScale *
            1.25,
      ),
      context,
      onError: (error, stack) {
        debugPrint('目标布局背景预备失败，保留已有背景: $error');
      },
    );
  }

  @override
  State<DynamicBackground> createState() => _DynamicBackgroundState();
}

class _DynamicBackgroundState extends State<DynamicBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _revealController;
  late CurvedAnimation _revealAnimation;
  late bool _glowLayerVisible;
  ImageProvider? _heldBackgroundProvider;
  ImageProvider? _heldCoverProvider;
  String _heldCoverKey = 'fallback';
  Timer? _heldArtworkReleaseTimer;
  bool _artworkAbsent = false;
  Object? _visualState;
  Object? _blurredArtworkKey;
  Widget? _blurredArtwork;
  WidgetLayout get _layout => widget.verticalLayout == null
      ? AppState.widgetLayout
      : widget.verticalLayout!
      ? WidgetLayout.vertical
      : WidgetLayout.horizontal;

  Object _readVisualState() => (
    AppState.coverProvider,
    AppState.bgBlurProvider,
    AppState.currentCoverVersion,
    AppState.currentScheme,
    AppState.themeBrightness,
    AppState.enableGlow,
    AppState.glowMode,
    AppState.enableOledTheme,
    _layout,
    AppState.isPlaying,
    AppState.corePlayerHeightOf(WidgetLayout.horizontal),
    AppState.glowHeaderHeightOf(_layout),
    AppState.componentScale,
  );

  void _releaseHeldArtwork() {
    if (!mounted ||
        !_artworkAbsent ||
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
      _blurredArtworkKey = null;
      _blurredArtwork = null;
    });
  }

  void _beginArtworkRelease() {
    _heldArtworkReleaseTimer = null;
    if (!mounted ||
        AppState.coverProvider != null ||
        AppState.bgBlurProvider != null) {
      return;
    }
    setState(() => _artworkAbsent = true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppState.backgroundRevision.addListener(_handleBackgroundChanged);
    _glowLayerVisible = AppState.enableGlow;
    _visualState = _readVisualState();
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
      setState(() {
        _glowLayerVisible = false;
        _blurredArtwork = null;
        _blurredArtworkKey = null;
      });
    }
  }

  void _handleBackgroundChanged() {
    if (!mounted) return;
    final visualState = _readVisualState();
    if (_visualState == visualState) return;
    _visualState = visualState;
    _heldArtworkReleaseTimer?.cancel();
    if (AppState.coverProvider == null && AppState.bgBlurProvider == null) {
      _heldArtworkReleaseTimer = Timer(
        const Duration(milliseconds: 500),
        _beginArtworkRelease,
      );
    } else {
      _artworkAbsent = false;
    }
    if (AppState.enableGlow) {
      _glowLayerVisible = true;
      if (_revealController.status != AnimationStatus.completed &&
          _revealController.status != AnimationStatus.forward) {
        _revealController.forward();
      }
    } else {
      if (_revealController.status != AnimationStatus.dismissed &&
          _revealController.status != AnimationStatus.reverse) {
        _revealController.reverse();
      }
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(DynamicBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verticalLayout != widget.verticalLayout) {
      _visualState = _readVisualState();
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _heldArtworkReleaseTimer?.cancel();
    AppState.backgroundRevision.removeListener(_handleBackgroundChanged);
    _revealAnimation.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  void didHaveMemoryPressure() => DitherNoisePainter.clearCache();

  Widget _preparedGlow(
    ImageProvider source,
    String identity,
    double headerH,
    bool waterfall,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      const zoom = 1.25;
      final width = widget.anchorWidth ?? constraints.maxWidth;
      final height = widget.anchorHeight ?? constraints.maxHeight;
      final rect = Rect.fromCenter(
        center: Offset(widget.anchorLeft + width / 2, height / 2),
        width: AppState.canvasWidth * zoom,
        height: AppState.canvasHeight * zoom,
      );
      return StableArtworkSurface(
        fit: BoxFit.fill,
        animateReplacement: widget.animateArtworkReplacement,
        clampedImageRect: rect,
        provider: BlurredArtworkProvider(
          source: source,
          identity: identity,
          waterfall: waterfall,
          headerHeight: waterfall ? headerH : 0,
          pixelScale:
              MediaQuery.devicePixelRatioOf(context) *
              AppState.componentScale *
              zoom,
        ),
      );
    },
  );

  Widget _buildBlurredArtwork(
    ImageProvider provider,
    String coverKey,
    double headerHeight,
  ) {
    final key = (
      provider,
      coverKey,
      AppState.glowMode,
      headerHeight,
      MediaQuery.devicePixelRatioOf(context),
      AppState.componentScale,
      widget.anchorWidth,
      widget.anchorHeight,
      widget.anchorLeft,
      widget.animateArtworkReplacement,
    );
    if (_blurredArtworkKey != key) {
      _blurredArtworkKey = key;
      _blurredArtwork = RepaintBoundary(
        child: _preparedGlow(
          provider,
          coverKey,
          headerHeight,
          AppState.glowMode == GlowMode.waterfall,
        ),
      );
    }
    return _blurredArtwork!;
  }

  @override
  Widget build(BuildContext context) {
    _visualState = _readVisualState();
    final bool isDark = AppState.themeBrightness == Brightness.dark;

    const double canvasW = AppState.canvasWidth;
    const double canvasH = AppState.canvasHeight;
    final double headerH = AppState.glowHeaderHeightOf(_layout);

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
            (widget.anchorWidth ?? constraints.maxWidth) /
            AppState.innerPlayerWidthOf(WidgetLayout.horizontal);
        final rightCoverHeight =
            AppState.corePlayerHeightOf(WidgetLayout.horizontal) * headerScale;
        return Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutQuart,
                color: isDark
                    ? (AppState.enableGlow
                          ? AppState.currentScheme.surfaceContainerLow
                          : (AppState.enableOledTheme
                                ? Colors.black
                                : AppState.currentScheme.surfaceContainerHigh))
                    : (AppState.enableGlow
                          ? AppState.currentScheme.surface
                          : AppState.currentScheme.surfaceContainerHighest),
              ),
            ),

            if (bgProvider != null && _glowLayerVisible)
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: AppState.layoutSwitchDuration,
                  curve: Curves.easeOutCubic,
                  opacity: _artworkAbsent ? 0.0 : 1.0,
                  onEnd: _releaseHeldArtwork,
                  child: AnimatedBuilder(
                    animation: _revealAnimation,
                    builder: (context, child) {
                      return ClipPath(
                        clipBehavior: _revealAnimation.value >= 0.99999
                            ? Clip.none
                            : Clip.antiAliasWithSaveLayer,
                        clipper: CircularRevealClipper(
                          fraction: _revealAnimation.value,
                          center:
                              AppState.revealCenterOf(_layout) +
                              Offset(
                                widget.anchorLeft +
                                    ((widget.anchorWidth ??
                                                constraints.maxWidth) -
                                            canvasW) /
                                        2,
                                ((widget.anchorHeight ??
                                            constraints.maxHeight) -
                                        canvasH) /
                                    2,
                              ),
                        ),
                        child: child,
                      );
                    },
                    child: _buildBlurredArtwork(bgProvider, coverKey, headerH),
                  ),
                ),
              ),

            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    color: overlayColor.withValues(alpha: universalDimOpacity),
                  ),
                  FadeTransition(
                    opacity: _revealAnimation,
                    child: _AnchoredBackgroundCanvas(
                      width: canvasW,
                      height: canvasH,
                      anchorWidth: widget.anchorWidth,
                      anchorLeft: widget.anchorLeft,
                      anchorHeight:
                          widget.anchorHeight ?? constraints.maxHeight,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: DitherNoisePainter(AppState.themeBrightness),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_heldCoverProvider != null)
              Positioned(
                top: 0,
                right: 0,
                height: rightCoverHeight,
                width: math.min(rightCoverHeight, constraints.maxWidth),
                child: AnimatedOpacity(
                  opacity:
                      (widget.verticalLayout ?? AppState.isVertical) ||
                          _artworkAbsent
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
