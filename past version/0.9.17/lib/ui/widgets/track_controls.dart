import 'dart:math' as math; 
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter, PointMode;
import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../widgets/parallax_button.dart';

int _globalSlideDirection = 1;
String _lastMeasureKey = "";
double _cachedTitleTargetWidth = 0.0;
double _cachedTitleTargetHeight = 0.0;
double _cachedArtistTargetWidth = 0.0;
double _cachedArtistTargetHeight = 0.0;

class ContinuousTrackControls extends StatefulWidget {
  final bool isVertical;
  const ContinuousTrackControls({super.key, required this.isVertical});

  @override
  State<ContinuousTrackControls> createState() =>
      _ContinuousTrackControlsState();
}

class _ContinuousTrackControlsState extends State<ContinuousTrackControls> {
  late bool _hasTimeline;
  Timer? _timelineHideTimer;

  @override
  void initState() {
    super.initState();
    _hasTimeline = AppState.playbackDurationMs > 0;
    AppState.playbackRevision.addListener(_handleTimelineAvailability);
  }

  void _handleTimelineAvailability() {
    final bool nextHasTimeline = AppState.playbackDurationMs > 0;
    if (!mounted) return;
    if (nextHasTimeline) {
      _timelineHideTimer?.cancel();
      if (!_hasTimeline) setState(() => _hasTimeline = true);
      return;
    }
    if (!_hasTimeline || _timelineHideTimer?.isActive == true) return;
    
    
    _timelineHideTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && AppState.playbackDurationMs <= 0 && _hasTimeline) {
        setState(() => _hasTimeline = false);
      }
    });
  }

  @override
  void dispose() {
    _timelineHideTimer?.cancel();
    AppState.playbackRevision.removeListener(_handleTimelineAvailability);
    super.dispose();
  }

  Duration _textTransitionDuration(double measuredWidth) {
    final int milliseconds = (430 + measuredWidth * 0.75).round().clamp(
      460,
      760,
    );
    return Duration(milliseconds: milliseconds);
  }

  void _measureTexts(
    double w,
    Color textColor,
    double titleFontSize,
    double artistFontSize,
  ) {
    final String key =
        "${AppState.trackTitle}|${AppState.artistName}|$w|$titleFontSize|$artistFontSize|${AppState.titleWeightIndex}|${AppState.artistWeightIndex}|${AppState.currentFontFamily}";
    if (key == _lastMeasureKey) return;
    _lastMeasureKey = key;

    final titleStyle = TextStyle(
      fontSize: titleFontSize,
      fontWeight: AppState.titleWeight,
      color: textColor,
      fontFamilyFallback: AppState.textFontFallback,
      letterSpacing: 0.0,
      height: 1.2,
    );
    final artistStyle = TextStyle(
      fontSize: artistFontSize,
      fontWeight: AppState.artistWeight,
      color: textColor.withValues(alpha: 0.7),
      fontFamilyFallback: AppState.textFontFallback,
      height: 1.2,
    );

    final titlePainter = TextPainter(
      text: TextSpan(text: AppState.trackTitle, style: titleStyle),
      textDirection: TextDirection.ltr,
      textHeightBehavior: AppState.crispTextHeightBehavior,
    )..layout(maxWidth: w);
    final artistPainter = TextPainter(
      text: TextSpan(text: AppState.artistName, style: artistStyle),
      textDirection: TextDirection.ltr,
      textHeightBehavior: AppState.crispTextHeightBehavior,
    )..layout(maxWidth: w);

    _cachedTitleTargetWidth = titlePainter.width;
    _cachedTitleTargetHeight = titlePainter.height;
    _cachedArtistTargetWidth = artistPainter.width;
    _cachedArtistTargetHeight = artistPainter.height;
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppState.currentScheme.onSurface;
    final subTextColor = AppState.currentScheme.onSurfaceVariant;
    final bool isV = widget.isVertical;
    final double uiOpacity = AppState.isPlaying ? 1.0 : 0.5;
    final bool hasProgress = _hasTimeline;

    return Builder(
      builder: (context) {
        final WidgetLayout targetLayout = isV
            ? WidgetLayout.vertical
            : WidgetLayout.horizontal;
        final double availableW = AppState.innerPlayerWidthOf(targetLayout);
        final double availableH = AppState.corePlayerHeightOf(targetLayout);
        final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final double md3ProgressHeight = switch (AppState.progressStyle) {
          MD3ProgressStyle.linear => isV ? 5.0 : 4.0,
          MD3ProgressStyle.pill => isV ? 9.0 : 8.0,
          MD3ProgressStyle.segmented => isV ? 7.0 : 6.0,
        };

        late double coverSize;
        late double coverL;
        late double coverT;
        late double infoW;
        late double titleL;
        late double titleT;
        late double titleH;
        late double artistL;
        late double artistT;
        late double artistH;
        late double progressT;
        late double progressH;
        late double progressW;
        late double playT;
        late double btnT;
        late double playH;
        late double btnH;
        late double titleFontSize;
        late double artistFontSize;

        if (isV) {
          final double padding = (availableW * 0.07).clamp(16.0, 24.0);
          infoW = math.max(1.0, availableW - padding * 2.0);
          titleL = padding;
          artistL = padding;
          coverL = padding;
          titleFontSize = (infoW * 0.068).clamp(18.0, 21.0);
          artistFontSize = (titleFontSize * 0.66).clamp(12.0, 14.0);
          titleH = titleFontSize * 1.34;
          artistH = artistFontSize * 1.38;
          progressH = hasProgress ? md3ProgressHeight : 0.0;
          progressW = (infoW * 0.78).clamp(180.0, 228.0);
          playH = (availableH * 0.116).clamp(52.0, 60.0);
          btnH = playH * 0.83;

          final int gapCount = hasProgress ? 4 : 3;
          final double desiredGap = (availableH * 0.024).clamp(8.0, 14.0);
          final double nonCoverHeight = titleH + artistH + progressH + playH;
          final double coverSpace =
              availableH -
              padding * 2.0 -
              nonCoverHeight -
              desiredGap * gapCount;
          coverSize = math.min(infoW, math.max(96.0, coverSpace));
          final double freeHeight =
              availableH - padding * 2.0 - coverSize - nonCoverHeight;
          final double gap = (freeHeight / gapCount).clamp(6.0, 24.0);
          final double groupHeight =
              coverSize + nonCoverHeight + gap * gapCount;
          coverT = math.max(padding, (availableH - groupHeight) / 2.0);
          titleT = coverT + coverSize + gap;
          artistT = titleT + titleH + gap;
          progressT = artistT + artistH + (hasProgress ? gap : 0.0);
          playT = hasProgress
              ? progressT + progressH + gap
              : artistT + artistH + gap;
          btnT = playT + (playH - btnH) / 2.0;
        } else {
          final double padding = (availableH * 0.10).clamp(12.0, 16.0);
          coverSize = math.min(
            math.max(72.0, availableH - padding * 2.0),
            math.max(72.0, availableW * 0.30),
          );
          coverL = padding;
          coverT = (availableH - coverSize) / 2.0;
          final double columnGap = (availableW * 0.033).clamp(12.0, 18.0);
          titleL = coverL + coverSize + columnGap;
          artistL = titleL;
          infoW = math.max(120.0, availableW - titleL - padding);
          titleFontSize = (infoW * 0.072).clamp(19.0, 22.0);
          artistFontSize = (titleFontSize * 0.64).clamp(12.5, 14.0);
          titleH = titleFontSize * 1.28;
          artistH = artistFontSize * 1.32;
          progressH = hasProgress ? md3ProgressHeight : 0.0;
          progressW = (infoW * 0.72).clamp(180.0, 218.0);
          final double contentHeight = math.max(
            80.0,
            availableH - padding * 2.0,
          );
          playH = (contentHeight * 0.44).clamp(48.0, 58.0);
          btnH = playH * 0.83;

          final int gapCount = hasProgress ? 3 : 2;
          final double fixedHeight = titleH + artistH + progressH + playH;
          final double gap = ((contentHeight - fixedHeight) / gapCount).clamp(
            2.0,
            16.0,
          );
          final double groupHeight = fixedHeight + gap * gapCount;
          titleT = (availableH - groupHeight) / 2.0;
          artistT = titleT + titleH + gap;
          progressT = artistT + artistH + (hasProgress ? gap : 0.0);
          playT = hasProgress
              ? progressT + progressH + gap
              : artistT + artistH + gap;
          btnT = playT + (playH - btnH) / 2.0;
        }

        double shapedWidth(MD3Shape shape, double height, double extra) =>
            height + (shape == MD3Shape.stadium ? height * extra : 0.0);

        final double prevW = shapedWidth(AppState.prevButtonShape, btnH, 0.34);
        final double playW = shapedWidth(AppState.playButtonShape, playH, 0.31);
        final double nextW = shapedWidth(AppState.nextButtonShape, btnH, 0.34);
        final double buttonGap = (infoW * 0.052).clamp(8.0, 16.0);
        final double buttonGroupWidth = prevW + playW + nextW + buttonGap * 2.0;
        final double prevL = isV
            ? (availableW - buttonGroupWidth) / 2.0
            : titleL;
        final double playL = prevL + prevW + buttonGap;
        final double nextL = playL + playW + buttonGap;

        
        
        
        
        
        final double snappedTitleL = AppState.snapToDevicePixel(
          titleL,
          devicePixelRatio,
        );
        final double snappedArtistL = AppState.snapToDevicePixel(
          artistL,
          devicePixelRatio,
        );
        final double snappedTitleT = AppState.snapToDevicePixel(
          titleT,
          devicePixelRatio,
        );
        final double snappedArtistT = AppState.snapToDevicePixel(
          artistT,
          devicePixelRatio,
        );
        final double snappedInfoW = AppState.snapToDevicePixel(
          infoW,
          devicePixelRatio,
        );
        final double snappedTitleH = AppState.snapToDevicePixel(
          titleH,
          devicePixelRatio,
        );
        final double snappedArtistH = AppState.snapToDevicePixel(
          artistH,
          devicePixelRatio,
        );

        _measureTexts(snappedInfoW, textColor, titleFontSize, artistFontSize);
        final Duration titleTransitionDuration = _textTransitionDuration(
          _cachedTitleTargetWidth,
        );
        final Duration artistTransitionDuration = _textTransitionDuration(
          _cachedArtistTargetWidth,
        );
        final Duration coverTransitionDuration = _textTransitionDuration(
          math.max(_cachedTitleTargetWidth, _cachedArtistTargetWidth),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedPositioned(
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: coverL,
              top: coverT,
              width: coverSize,
              height: coverSize,
              child: _buildCover(coverSize, coverTransitionDuration),
            ),

            AnimatedPositioned(
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: snappedTitleL,
              top: snappedTitleT,
              width: snappedInfoW,
              height: snappedTitleH,
              child: RepaintBoundary(
                child: AnimatedSwitcher(
                  duration: titleTransitionDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: <Widget>[...previousChildren, ?currentChild],
                  ),
                  transitionBuilder: (child, anim) {
                    final info = child as _TextInfoWidget;
                    return _PixelDissolveTransition(
                      animation: anim,
                      isIncoming:
                          child.key ==
                          ValueKey(
                            "${AppState.trackTitle}|${AppState.trackVersion}_title",
                          ),
                      direction: _globalSlideDirection,
                      text: info.text,
                      targetWidth: info.measuredWidth,
                      targetHeight: info.measuredHeight,
                      child: child,
                    );
                  },
                  child: _TextInfoWidget(
                    key: ValueKey(
                      "${AppState.trackTitle}|${AppState.trackVersion}_title",
                    ),
                    text: AppState.trackTitle,
                    measuredWidth: _cachedTitleTargetWidth,
                    measuredHeight: _cachedTitleTargetHeight,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: AppState.titleWeight,
                      color: textColor.withValues(alpha: uiOpacity),
                      fontFamilyFallback: AppState.textFontFallback,
                      letterSpacing: 0.0,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),

            AnimatedPositioned(
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: snappedArtistL,
              top: snappedArtistT,
              width: snappedInfoW,
              height: snappedArtistH,
              child: RepaintBoundary(
                child: AnimatedSwitcher(
                  duration: artistTransitionDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: <Widget>[...previousChildren, ?currentChild],
                  ),
                  transitionBuilder: (child, anim) {
                    final info = child as _TextInfoWidget;
                    return _PixelDissolveTransition(
                      animation: anim,
                      isIncoming:
                          child.key ==
                          ValueKey(
                            "${AppState.artistName}|${AppState.trackVersion}_artist",
                          ),
                      direction: _globalSlideDirection,
                      text: info.text,
                      targetWidth: info.measuredWidth,
                      targetHeight: info.measuredHeight,
                      child: child,
                    );
                  },
                  child: _TextInfoWidget(
                    key: ValueKey(
                      "${AppState.artistName}|${AppState.trackVersion}_artist",
                    ),
                    text: AppState.artistName,
                    measuredWidth: _cachedArtistTargetWidth,
                    measuredHeight: _cachedArtistTargetHeight,
                    style: TextStyle(
                      fontSize: artistFontSize,
                      fontWeight: AppState.artistWeight,
                      color: subTextColor.withValues(alpha: uiOpacity),
                      fontFamilyFallback: AppState.textFontFallback,
                      letterSpacing: 0.0,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),

            AnimatedPositioned(
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: titleL,
              top: progressT,
              width: progressW,
              height: progressH,
              child: const RepaintBoundary(child: _PlaybackProgress()),
            ),

            AnimatedPositioned(
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: prevL,
              top: btnT,
              width: prevW,
              height: btnH,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                opacity: uiOpacity,
                child: WpfParallaxItem(
                  width: prevW,
                  height: btnH,
                  borderRadius: AppState.getShapeRadius(
                    AppState.prevButtonShape,
                    btnH,
                  ),
                  bgColor: AppState.currentScheme.primaryContainer,
                  foreground: Icon(
                    Icons.skip_previous_rounded,
                    size: btnH * 0.54,
                    color: AppState.currentScheme.onPrimaryContainer,
                  ),
                  onTap: () {
                    _globalSlideDirection = -1;
                    AppState.sendCommand("PREV");
                  },
                ),
              ),
            ),

            AnimatedPositioned(
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: playL,
              top: playT,
              width: playW,
              height: playH,
              child: WpfParallaxItem(
                width: playW,
                height: playH,
                borderRadius: AppState.getShapeRadius(
                  AppState.playButtonShape,
                  playH,
                ),
                bgColor: AppState.currentScheme.primary,
                foreground: Icon(
                  AppState.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: playH * 0.59,
                  color: AppState.currentScheme.onPrimary,
                ),
                onTap: () {
                  AppState.sendCommand("TOGGLE");
                  setState(() => AppState.isPlaying = !AppState.isPlaying);
                  AppState.notifyBackgroundChanged();
                },
              ),
            ),

            AnimatedPositioned(
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: nextL,
              top: btnT,
              width: nextW,
              height: btnH,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                opacity: uiOpacity,
                child: WpfParallaxItem(
                  width: nextW,
                  height: btnH,
                  borderRadius: AppState.getShapeRadius(
                    AppState.nextButtonShape,
                    btnH,
                  ),
                  bgColor: AppState.currentScheme.primaryContainer,
                  foreground: Icon(
                    Icons.skip_next_rounded,
                    size: btnH * 0.54,
                    color: AppState.currentScheme.onPrimaryContainer,
                  ),
                  onTap: () {
                    _globalSlideDirection = 1;
                    AppState.sendCommand("NEXT");
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCover(double size, Duration transitionDuration) {
    return AnimatedSwitcher(
      duration: transitionDuration < const Duration(milliseconds: 520)
          ? const Duration(milliseconds: 520)
          : transitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, anim) {
        final isIncoming = child.key == ValueKey(_coverIdentity);
        final offset = isIncoming
            ? Tween<Offset>(
                begin: Offset(_globalSlideDirection * 0.08, 0.0),
                end: Offset.zero,
              ).animate(anim)
            : Tween<Offset>(
                begin: Offset(_globalSlideDirection * -0.06, 0.0),
                end: Offset.zero,
              ).animate(anim);
        final scale = isIncoming
            ? Tween<double>(begin: 0.96, end: 1.0).animate(anim)
            : Tween<double>(begin: 0.985, end: 1.0).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: offset,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
      child: IgnorePointer(
        key: ValueKey(_coverIdentity),
        ignoring: !AppState.isPlaying,
        child: RepaintBoundary(
          child: WpfParallaxItem(
            width: size,
            height: size,
            borderRadius: BorderRadius.circular(
              (size * 0.055).clamp(14.0, 20.0),
            ),
            bgColor: AppState.currentScheme.surface,
            bgImage: AppState.coverProvider,
            showOverlay: false,
            enableHover: true,
            enable3D: AppState.enable3DCover,
            hoverScale: AppState.enable3DCover ? 1.06 : 1.04,
            bgParallaxMultiplier: AppState.enable3DCover ? 5.0 : 3.0,
            tiltMultiplier: AppState.enable3DCover ? 0.22 : 0.0,
            customBgOverlay: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              color: Colors.black.withValues(
                alpha: AppState.isPlaying ? 0.0 : 0.45,
              ),
            ),
            foreground: AppState.coverProvider == null
                ? Icon(
                    Icons.music_note_rounded,
                    size: (size * 0.25).clamp(42.0, 72.0),
                    color: AppState.currentScheme.primary.withValues(
                      alpha: 0.5,
                    ),
                  )
                : null,
            onTap: () {},
          ),
        ),
      ),
    );
  }

  String get _coverIdentity => AppState.currentCoverVersion.isNotEmpty
      ? AppState.currentCoverVersion
      : 'fallback|${AppState.trackTitle}|${AppState.artistName}';
}

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress();

  @override
  State<_PlaybackProgress> createState() => _PlaybackProgressState();
}

class _PlaybackProgressState extends State<_PlaybackProgress>
    with SingleTickerProviderStateMixin {
  static const double _returnDurationMs = 720.0;
  static const double _catchUpDurationMs = 240.0;
  late final AnimationController _frameController;
  final Stopwatch _clock = Stopwatch()..start();
  String _trackVersion = '';
  String _trackTitle = '';
  String _trackArtist = '';
  double _displayProgress = 0.0;
  double _transitionFrom = 0.0;
  int _transitionStartedAtMs = 0;
  double _catchUpFrom = 0.0;
  int _catchUpStartedAtMs = 0;
  bool _hasExplicitTrackSignal = false;
  MD3ProgressStyle _lastProgressStyle = MD3ProgressStyle.linear;
  bool _lastPlaying = false;
  bool _lastAutoContrast = true;
  bool _lastReturning = false;
  Color _lastSchemeColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _frameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_onFrame);
    _trackVersion = AppState.trackVersion;
    _trackTitle = AppState.trackTitle;
    _trackArtist = AppState.artistName;
    _displayProgress = _currentTargetProgress;
    AppState.playbackRevision.addListener(_handlePlaybackSignal);
    AppState.trackTransitionRevision.addListener(_handleTrackTransition);
    if (AppState.isPlaying) _frameController.repeat();
  }

  @override
  void dispose() {
    AppState.playbackRevision.removeListener(_handlePlaybackSignal);
    AppState.trackTransitionRevision.removeListener(_handleTrackTransition);
    _frameController.dispose();
    super.dispose();
  }

  double get _currentTargetProgress {
    final double duration = AppState.playbackDurationMs;
    if (duration <= 0) return 0.0;
    return (AppState.estimatedPlaybackPositionMs / duration).clamp(0.0, 1.0);
  }

  void _ensureFrameTicker() {
    if (!_frameController.isAnimating) _frameController.repeat();
  }

  void _handlePlaybackSignal() {
    if (!mounted) return;
    _onFrame();
    if (AppState.isPlaying ||
        _transitionStartedAtMs > 0 ||
        _catchUpStartedAtMs > 0) {
      _ensureFrameTicker();
    }
  }

  void _handleTrackTransition() {
    if (!mounted) return;
    _hasExplicitTrackSignal = true;
    if (_transitionStartedAtMs <= 0) {
      _transitionFrom = _displayProgress;
      _transitionStartedAtMs = _clock.elapsedMilliseconds + 1;
      _catchUpStartedAtMs = 0;
    }
    _ensureFrameTicker();
    setState(() => _lastReturning = true);
  }

  void _onFrame() {
    final double target = _currentTargetProgress;
    final int now = _clock.elapsedMilliseconds + 1;

    final bool trackChanged =
        _trackVersion != AppState.trackVersion ||
        _trackTitle != AppState.trackTitle ||
        _trackArtist != AppState.artistName;
    if (trackChanged) {
      final bool hasPreviousTrack =
          _trackVersion.isNotEmpty || _trackTitle.isNotEmpty;
      _trackVersion = AppState.trackVersion;
      _trackTitle = AppState.trackTitle;
      _trackArtist = AppState.artistName;
      if (hasPreviousTrack && !_hasExplicitTrackSignal) {
        _transitionFrom = _displayProgress;
        _transitionStartedAtMs = now;
        _catchUpStartedAtMs = 0;
      } else {
        _hasExplicitTrackSignal = false;
      }
    }

    double nextProgress = target;
    if (_transitionStartedAtMs > 0) {
      final double t = ((now - _transitionStartedAtMs) / _returnDurationMs)
          .clamp(0.0, 1.0);
      final double eased = Curves.easeInOutCubicEmphasized.transform(t);
      nextProgress = _transitionFrom * (1.0 - eased);
      if (t >= 1.0) {
        _transitionStartedAtMs = 0;
        _catchUpFrom = 0.0;
        _catchUpStartedAtMs = now;
        nextProgress = 0.0;
      }
    } else if (_catchUpStartedAtMs > 0) {
      final double t = ((now - _catchUpStartedAtMs) / _catchUpDurationMs).clamp(
        0.0,
        1.0,
      );
      final double eased = Curves.easeOutCubic.transform(t);
      nextProgress = _catchUpFrom + (target - _catchUpFrom) * eased;
      if (t >= 1.0) {
        _catchUpStartedAtMs = 0;
        nextProgress = target;
      }
    }

    final bool isReturning = _transitionStartedAtMs > 0;

    final bool shouldRebuild =
        (nextProgress - _displayProgress).abs() > 0.00005 ||
        _lastProgressStyle != AppState.progressStyle ||
        _lastPlaying != AppState.isPlaying ||
        _lastAutoContrast != AppState.enableProgressAutoContrast ||
        _lastReturning != isReturning ||
        _lastSchemeColor != AppState.currentScheme.primary;
    if (!shouldRebuild || !mounted) {
      if (!AppState.isPlaying &&
          _transitionStartedAtMs <= 0 &&
          _catchUpStartedAtMs <= 0) {
        _frameController.stop();
      }
      return;
    }

    setState(() {
      _displayProgress = nextProgress;
      _lastProgressStyle = AppState.progressStyle;
      _lastPlaying = AppState.isPlaying;
      _lastAutoContrast = AppState.enableProgressAutoContrast;
      _lastReturning = isReturning;
      _lastSchemeColor = AppState.currentScheme.primary;
    });
    if (!AppState.isPlaying &&
        _transitionStartedAtMs <= 0 &&
        _catchUpStartedAtMs <= 0) {
      _frameController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double duration = AppState.playbackDurationMs;
    final bool isReturning = _transitionStartedAtMs > 0;
    if (duration <= 0 && !isReturning && _displayProgress <= 0.001) {
      return const SizedBox.shrink();
    }

    final Color primary = AppState.currentScheme.primary;
    final Color trackColor = AppState.currentScheme.surfaceContainerHighest;
    final bool autoContrast = AppState.enableProgressAutoContrast;
    return SizedBox.expand(
      child: CustomPaint(
        painter: _ProgressBarPainter(
          progress: _displayProgress,
          activeColor: primary,
          trackColor: trackColor,
          autoContrast: autoContrast,
          style: AppState.progressStyle,
          returning: isReturning,
        ),
      ),
    );
  }
}

class MusicSpectrumPanel extends StatefulWidget {
  final SpectrumMode mode;
  final bool isPlaying;

  const MusicSpectrumPanel({
    super.key,
    required this.mode,
    required this.isPlaying,
  });

  @override
  State<MusicSpectrumPanel> createState() => _MusicSpectrumPanelState();
}

class _MusicSpectrumPanelState extends State<MusicSpectrumPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Float32List _displayLevels = Float32List(AppState.spectrumBandCount);
  final Float32List _startLevels = Float32List(AppState.spectrumBandCount);
  final Float32List _targetLevels = Float32List(AppState.spectrumBandCount);

  @override
  void initState() {
    super.initState();
    AppState.spectrumRevision.addListener(_handleSpectrumChanged);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    )..addListener(_updateDisplayLevels);
    _handleSpectrumChanged();
  }

  @override
  void didUpdateWidget(covariant MusicSpectrumPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.isPlaying != widget.isPlaying) {
      _handleSpectrumChanged();
    }
  }

  void _handleSpectrumChanged() {
    if (widget.mode == SpectrumMode.off) {
      _controller.stop();
      _displayLevels.fillRange(0, _displayLevels.length, 0.0);
      _startLevels.fillRange(0, _startLevels.length, 0.0);
      _targetLevels.fillRange(0, _targetLevels.length, 0.0);
      return;
    }

    for (int i = 0; i < _displayLevels.length; i++) {
      _startLevels[i] = _displayLevels[i];
      _targetLevels[i] = AppState.spectrumLevels[i];
    }
    _controller.forward(from: 0.0);
  }

  void _updateDisplayLevels() {
    final double progress = Curves.easeOutCubic.transform(_controller.value);
    for (int i = 0; i < _displayLevels.length; i++) {
      _displayLevels[i] =
          _startLevels[i] + (_targetLevels[i] - _startLevels[i]) * progress;
      if (_displayLevels[i] < 0.002) _displayLevels[i] = 0;
    }
  }

  @override
  void dispose() {
    AppState.spectrumRevision.removeListener(_handleSpectrumChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = AppState.currentScheme;

    final BorderRadius radius = BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
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
              color: scheme.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SpectrumPainter(
                        mode: widget.mode,
                        levels: _displayLevels,
                        color: scheme.primary,
                        autoContrast: AppState.enableProgressAutoContrast,
                        repaint: _controller,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final SpectrumMode mode;
  final Float32List levels;
  final Color color;
  final bool autoContrast;

  _SpectrumPainter({
    required this.mode,
    required this.levels,
    required this.color,
    required this.autoContrast,
    required Listenable repaint,
  }) : super(repaint: repaint);

  double _levelAt(double position) {
    if (levels.isEmpty) return 0;
    final double index = position.clamp(0.0, 1.0) * (levels.length - 1);
    final int lower = index.floor();
    final int upper = math.min(levels.length - 1, lower + 1);
    final double fraction = index - lower;
    return levels[lower] + (levels[upper] - levels[lower]) * fraction;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final int count = levels.length;
    if (count == 0) return;
    bool hasSignal = false;
    for (final level in levels) {
      if (level > 0.005) {
        hasSignal = true;
        break;
      }
    }
    final Paint paint = Paint()
      ..color = (autoContrast ? Colors.white : color).withValues(
        alpha: hasSignal ? 0.82 : 0.26,
      )
      ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver
      ..isAntiAlias = true;
    final double slot = size.width / count;
    final double barWidth = math.max(1.4, slot - 2.0);

    if (mode == SpectrumMode.waveform) {
      if (!hasSignal) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round;
        final double baselineY =
            size.height - math.max(1.0, size.height * 0.06);
        canvas.drawLine(
          Offset(0, baselineY),
          Offset(size.width, baselineY),
          paint,
        );
        return;
      }
      final Path path = Path();
      const int points = 64;
      const double tension = 0.68;
      double xAt(int index) => size.width * index / (points - 1);
      double yAt(int index) {
        final int safeIndex = index.clamp(0, points - 1);
        final double level = _levelAt(safeIndex / (points - 1));
        return size.height - size.height * 0.9 * level;
      }

      path.moveTo(xAt(0), yAt(0));
      for (int i = 0; i < points - 1; i++) {
        final double x1 = xAt(i);
        final double y0 = yAt(i - 1);
        final double y1 = yAt(i);
        final double x2 = xAt(i + 1);
        final double y2 = yAt(i + 1);
        final double y3 = yAt(i + 2);
        final double control1X = x1 + (x2 - x1) / 3.0;
        final double control2X = x2 - (x2 - x1) / 3.0;
        final double control1Y = (y1 + (y2 - y0) * tension / 6.0).clamp(
          0.0,
          size.height,
        );
        final double control2Y = (y2 - (y3 - y1) * tension / 6.0).clamp(
          0.0,
          size.height,
        );
        path.cubicTo(control1X, control1Y, control2X, control2Y, x2, y2);
      }
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, paint);
      return;
    }

    paint.style = PaintingStyle.fill;
    for (int i = 0; i < count; i++) {
      final double x = i * slot + (slot - barWidth) / 2.0;
      final double level = hasSignal ? levels[i].clamp(0.0, 1.0) : 0.075;
      if (hasSignal && level <= 0.005) continue;
      if (mode == SpectrumMode.mirror) {
        final double halfHeight = size.height * 0.46 * level;
        final double center = size.height / 2.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, center - halfHeight - 0.5, barWidth, halfHeight),
            Radius.circular(barWidth / 2.0),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, center + 0.5, barWidth, halfHeight),
            Radius.circular(barWidth / 2.0),
          ),
          paint,
        );
      } else {
        final double height = size.height * level;
        final Rect rect = Rect.fromLTWH(
          x,
          size.height - height,
          barWidth,
          height,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2.0)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.mode != mode ||
      oldDelegate.color != color ||
      oldDelegate.autoContrast != autoContrast;
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color trackColor;
  final bool autoContrast;
  final MD3ProgressStyle style;
  final bool returning;

  const _ProgressBarPainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
    required this.autoContrast,
    required this.style,
    required this.returning,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Radius radius = Radius.circular(size.height / 2.0);
    final Paint trackPaint = Paint()
      ..isAntiAlias = true
      ..color = (autoContrast ? Colors.white : trackColor).withValues(
        alpha: autoContrast ? 0.34 : 0.72,
      )
      ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver;
    final Paint activePaint = Paint()
      ..isAntiAlias = true
      ..color = autoContrast ? Colors.white : activeColor
      ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver;

    final double normalized = progress.clamp(0.0, 1.0);
    if (style == MD3ProgressStyle.segmented) {
      final int segmentCount = (size.width / 12.0).round().clamp(12, 32);
      const double segmentGap = 2.0;
      final double segmentWidth =
          (size.width - segmentGap * (segmentCount - 1)) / segmentCount;
      final double activePosition = normalized * segmentCount;
      for (int i = 0; i < segmentCount; i++) {
        final double x = i * (segmentWidth + segmentGap);
        final RRect segment = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, segmentWidth, size.height),
          radius,
        );
        canvas.drawRRect(segment, trackPaint);
        final double fraction = (activePosition - i).clamp(0.0, 1.0);
        if (fraction > 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, 0, segmentWidth * fraction, size.height),
              radius,
            ),
            activePaint,
          );
        }
      }
      return;
    }

    final RRect track = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(track, trackPaint);
    final double activeWidth = size.width * normalized;
    if (activeWidth > 0) {
      final RRect active = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, activeWidth, size.height),
        radius,
      );
      canvas.drawRRect(active, activePaint);
      if (returning) {
        final Paint returnHighlight = Paint()
          ..isAntiAlias = true
          ..color = (autoContrast ? Colors.white : activeColor).withValues(
            alpha: 0.24,
          )
          ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver;
        canvas.drawCircle(
          Offset(
            activeWidth.clamp(size.height / 2.0, size.width),
            size.height / 2.0,
          ),
          size.height * 0.42,
          returnHighlight,
        );
      }
    }

    if (style == MD3ProgressStyle.linear) {
      final Paint stopPaint = Paint()
        ..isAntiAlias = true
        ..color = (autoContrast ? Colors.white : activeColor).withValues(
          alpha: 0.86,
        )
        ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver;
      canvas.drawCircle(
        Offset(size.width - size.height / 2.0, size.height / 2.0),
        size.height * 0.34,
        stopPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.autoContrast != autoContrast ||
      oldDelegate.style != style ||
      oldDelegate.returning != returning;
}

class _TextInfoWidget extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double measuredWidth;
  final double measuredHeight;
  const _TextInfoWidget({
    required super.key,
    required this.text,
    required this.style,
    required this.measuredWidth,
    required this.measuredHeight,
  });
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    textHeightBehavior: AppState.crispTextHeightBehavior,
    style: style,
  );
}

class _PixelDissolveTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;
  final bool isIncoming;
  final int direction;
  final String text;
  final double targetWidth;
  final double targetHeight;

  const _PixelDissolveTransition({
    required this.child,
    required this.animation,
    required this.isIncoming,
    required this.direction,
    required this.text,
    required this.targetWidth,
    required this.targetHeight,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final double t = animation.value;
        final double progress = isIncoming ? (1.0 - t) : t;
        final double textOpacity = isIncoming
            ? ((0.38 - progress) / 0.38).clamp(0.0, 1.0)
            : (1.0 - progress / 0.22).clamp(0.0, 1.0);
        return CustomPaint(
          foregroundPainter: _PixelParticlePainter(
            progress: progress,
            isIncoming: isIncoming,
            direction: direction,
            text: text,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            primaryColor: AppState.currentScheme.primary,
            onSurfaceColor: AppState.currentScheme.onSurface,
          ),
          child: Opacity(opacity: textOpacity, child: child),
        );
      },
    );
  }
}

class _ParticleSeed {
  final double x;
  final double y;
  final double horizontalNoise;
  final double verticalNoise;
  final bool usesPrimary;

  const _ParticleSeed({
    required this.x,
    required this.y,
    required this.horizontalNoise,
    required this.verticalNoise,
    required this.usesPrimary,
  });
}

class _ParticleBuffers {
  static const int bucketCount = 4;
  final List<Float32List> primary;
  final List<Float32List> surface;
  final List<int> primaryCounts = List<int>.filled(bucketCount, 0);
  final List<int> surfaceCounts = List<int>.filled(bucketCount, 0);

  _ParticleBuffers(int particleCapacity)
    : primary = List<Float32List>.generate(
        bucketCount,
        (_) => Float32List(particleCapacity * 2),
        growable: false,
      ),
      surface = List<Float32List>.generate(
        bucketCount,
        (_) => Float32List(particleCapacity * 2),
        growable: false,
      );

  void reset() {
    primaryCounts.fillRange(0, bucketCount, 0);
    surfaceCounts.fillRange(0, bucketCount, 0);
  }

  void add({
    required bool usesPrimary,
    required int bucket,
    required double x,
    required double y,
  }) {
    final lists = usesPrimary ? primary : surface;
    final counts = usesPrimary ? primaryCounts : surfaceCounts;
    final int index = counts[bucket];
    lists[bucket][index] = x;
    lists[bucket][index + 1] = y;
    counts[bucket] = index + 2;
  }
}

class _PixelParticlePainter extends CustomPainter {
  static const double _particleStep = 3.0;
  static final Map<String, List<_ParticleSeed>> _seedCache =
      <String, List<_ParticleSeed>>{};
  static final Map<String, _ParticleBuffers> _bufferCache =
      <String, _ParticleBuffers>{};

  final double progress;
  final bool isIncoming;
  final int direction;
  final String text;
  final double targetWidth;
  final double targetHeight;
  final Color primaryColor;
  final Color onSurfaceColor;

  _PixelParticlePainter({
    required this.progress,
    required this.isIncoming,
    required this.direction,
    required this.text,
    required this.targetWidth,
    required this.targetHeight,
    required this.primaryColor,
    required this.onSurfaceColor,
  });

  String get _particleKey =>
      '$text|${targetWidth.toStringAsFixed(1)}|${targetHeight.toStringAsFixed(1)}';

  List<_ParticleSeed> _particlesForText() {
    final String key = _particleKey;
    final cached = _seedCache[key];
    if (cached != null) return cached;

    final particles = <_ParticleSeed>[];
    for (double y = 0; y < targetHeight; y += _particleStep) {
      for (double x = 0; x < targetWidth; x += _particleStep) {
        final int row = (y / _particleStep).toInt();
        final int column = (x / _particleStep).toInt();
        final int h1 = (row * 129898 + column * 78233) % 43758;
        final int h2 = (row * 45123 + column * 13789) % 23456;
        particles.add(
          _ParticleSeed(
            x: x,
            y: y,
            horizontalNoise: (h1 / 43758.0) * 2.0 - 1.0,
            verticalNoise: (h2 / 23456.0) * 2.0 - 1.0,
            usesPrimary: (row + column).isEven,
          ),
        );
      }
    }
    if (_seedCache.length >= 12) {
      final String oldestKey = _seedCache.keys.first;
      _seedCache.remove(oldestKey);
      _bufferCache.remove(oldestKey);
    }
    _seedCache[key] = particles;
    return particles;
  }

  _ParticleBuffers _buffersForText(int particleCapacity) {
    return _bufferCache.putIfAbsent(
      _particleKey,
      () => _ParticleBuffers(particleCapacity),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01 || progress >= 0.99) return;
    final Paint paint = Paint()
      ..isAntiAlias = false
      ..strokeCap = StrokeCap.square;

    final int textLength = text.runes.length;
    final double dynamicScatterRange = (targetWidth * 0.38 + textLength * 0.8)
        .clamp(36.0, 140.0);
    final double releaseSpan = (0.18 + textLength * 0.004).clamp(0.18, 0.34);
    final particles = _particlesForText();
    final buffers = _buffersForText(particles.length)..reset();

    for (final particle in particles) {
      final double releaseThreshold =
          particle.horizontalNoise.abs() * releaseSpan;

      if (progress <= releaseThreshold) continue;
      final double age =
          (progress - releaseThreshold) / (1.0 - releaseThreshold);
      final double visibility = (1.0 - age).clamp(0.0, 1.0);
      final int bucket = (visibility * _ParticleBuffers.bucketCount).ceil() - 1;
      if (bucket < 0) continue;

      final double easedAge = age * age * (1.0 + 0.35 * age);
      final double offsetX =
          direction * particle.horizontalNoise * dynamicScatterRange * easedAge;
      final double offsetY = (particle.verticalNoise - 0.45) * 30.0 * age;
      buffers.add(
        usesPrimary: particle.usesPrimary,
        bucket: bucket.clamp(0, _ParticleBuffers.bucketCount - 1),
        x: particle.x + offsetX,
        y: particle.y + offsetY,
      );
    }

    for (int bucket = 0; bucket < _ParticleBuffers.bucketCount; bucket++) {
      final double alpha = (bucket + 1) / _ParticleBuffers.bucketCount;
      paint.strokeWidth = 0.62 + bucket * 0.07;

      final int primaryCount = buffers.primaryCounts[bucket];
      if (primaryCount > 0) {
        paint.color = primaryColor.withValues(alpha: alpha);
        canvas.drawRawPoints(
          PointMode.points,
          Float32List.sublistView(buffers.primary[bucket], 0, primaryCount),
          paint,
        );
      }

      final int surfaceCount = buffers.surfaceCounts[bucket];
      if (surfaceCount > 0) {
        paint.color = onSurfaceColor.withValues(alpha: alpha);
        canvas.drawRawPoints(
          PointMode.points,
          Float32List.sublistView(buffers.surface[bucket], 0, surfaceCount),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelParticlePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.text != text ||
      oldDelegate.targetWidth != targetWidth ||
      oldDelegate.targetHeight != targetHeight ||
      oldDelegate.direction != direction ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.onSurfaceColor != onSurfaceColor;
}
