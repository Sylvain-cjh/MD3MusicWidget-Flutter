import 'dart:math' as math; 
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show PointMode;
import 'package:flutter/material.dart';
import '../../core/appState.dart';
import '../../core/mediaProvider.dart';
import 'playbackControlButton.dart';
import 'playbackPauseShade.dart';
import 'mediaGeometry.dart';
import 'coverParallax.dart';
import 'spectrumGlassSurface.dart';
import 'playbackTimeLabel.dart';
import 'adaptiveMediaText.dart';
import '../animations/coverArtworkSwitcher.dart';
import '../animations/mediaMotionTokens.dart';
import '../animations/layoutMorphMotion.dart';

part 'trackProgress.dart';
part 'trackSpectrum.dart';
part 'trackTextParticles.dart';

int get _globalSlideDirection => AppState.trackNavigation.direction;

class ContinuousTrackControls extends StatefulWidget {
  final bool isVertical;
  final LayoutMorphMotion? layoutMotion;
  const ContinuousTrackControls({
    super.key,
    required this.isVertical,
    this.layoutMotion,
  });

  @override
  State<ContinuousTrackControls> createState() =>
      _ContinuousTrackControlsState();
}

class _ContinuousTrackControlsState extends State<ContinuousTrackControls> {
  String _lastMeasureKey = '';
  double _cachedTitleTargetWidth = 0, _cachedTitleTargetHeight = 0;
  double _cachedArtistTargetWidth = 0, _cachedArtistTargetHeight = 0;
  String _directionCoverIdentity = '';
  int _coverDirection = 1;
  late bool _hasTimeline;
  Timer? _timelineHideTimer;

  @override
  void initState() {
    super.initState();
    _hasTimeline = _timelineAvailable;
    AppState.playbackRevision.addListener(_handleTimelineAvailability);
    AppState.typographyRevision.addListener(_handleTypographyChanged);
    AppState.fontsRevision.addListener(_handleTypographyChanged);
  }

  void _handleTypographyChanged() {
    if (mounted) setState(() {});
  }

  bool get _timelineAvailable =>
      AppState.playbackDurationMs > 0 &&
      MediaCapability.supports(
        AppState.mediaCapabilities,
        MediaCapability.timeline,
      );

  void _handleTimelineAvailability() {
    final bool nextHasTimeline = _timelineAvailable;
    if (!mounted) return;
    if (nextHasTimeline) {
      _timelineHideTimer?.cancel();
      if (!_hasTimeline) setState(() => _hasTimeline = true);
      return;
    }
    if (!_hasTimeline || _timelineHideTimer?.isActive == true) return;
    
    
    _timelineHideTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && !_timelineAvailable && _hasTimeline) {
        setState(() => _hasTimeline = false);
      }
    });
  }

  @override
  void dispose() {
    _timelineHideTimer?.cancel();
    AppState.playbackRevision.removeListener(_handleTimelineAvailability);
    AppState.typographyRevision.removeListener(_handleTypographyChanged);
    AppState.fontsRevision.removeListener(_handleTypographyChanged);
    super.dispose();
  }

  Duration _textTransitionDuration(double measuredWidth) {
    final int milliseconds = (430 + measuredWidth * 0.75).round().clamp(
      460,
      760,
    );
    return Duration(milliseconds: milliseconds);
  }

  static bool _hasTrackText(String title) {
    final value = title.trim();
    return value.isNotEmpty &&
        value != '未在播放' &&
        value != '暂无音乐播放' &&
        value != '未知歌曲';
  }

  Duration _effectiveTextTransitionDuration(
    double measuredWidth, {
    required bool hasTrack,
    required bool reduceMotion,
  }) {
    if (!AppState.trackTextAnimationsEnabled || !hasTrack) {
      return Duration.zero;
    }
    if (reduceMotion) return MediaMotionTokens.reduced;
    if (AppState.trackTextTransitionStyle ==
        TrackTextTransitionStyle.particles) {
      return _textTransitionDuration(measuredWidth);
    }
    return MediaMotionTokens.replacement;
  }

  Widget _buildTextTransition(
    Widget child,
    Animation<double> animation, {
    required bool isIncoming,
    required bool reduceMotion,
  }) {
    final info = child as _TextInfoWidget;
    if (!AppState.trackTextAnimationsEnabled ||
        reduceMotion ||
        info.isPlaceholder) {
      return FadeTransition(opacity: animation, child: child);
    }
    if (!isIncoming) {
      return _buildTextExitTransition(child, animation);
    }
    switch (AppState.trackTextTransitionStyle) {
      case TrackTextTransitionStyle.particles:
        return _PixelDissolveTransition(
          animation: animation,
          isIncoming: true,
          direction: _globalSlideDirection,
          text: info.text,
          targetWidth: info.measuredWidth,
          targetHeight: info.measuredHeight,
          child: child,
        );
      case TrackTextTransitionStyle.fade:
        return FadeTransition(opacity: animation, child: child);
      case TrackTextTransitionStyle.rise:
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.24),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      case TrackTextTransitionStyle.sideways:
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(_globalSlideDirection * 0.08, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      case TrackTextTransitionStyle.zoom:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        );
      case TrackTextTransitionStyle.descend:
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.20),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      case TrackTextTransitionStyle.settle:
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.04, end: 1).animate(animation),
            child: child,
          ),
        );
      case TrackTextTransitionStyle.sweep:
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(_globalSlideDirection * 0.16, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
    }
  }

  Widget _buildTextExitTransition(Widget child, Animation<double> animation) {
    final style = AppState.trackTextAnimationsLinked
        ? switch (AppState.trackTextTransitionStyle) {
            TrackTextTransitionStyle.particles ||
            TrackTextTransitionStyle.fade => TrackTextExitStyle.fade,
            TrackTextTransitionStyle.rise => TrackTextExitStyle.rise,
            TrackTextTransitionStyle.descend => TrackTextExitStyle.descend,
            TrackTextTransitionStyle.sideways ||
            TrackTextTransitionStyle.sweep => TrackTextExitStyle.sideways,
            TrackTextTransitionStyle.zoom ||
            TrackTextTransitionStyle.settle => TrackTextExitStyle.shrink,
          }
        : AppState.trackTextExitStyle;
    final Widget outgoing = switch (style) {
      TrackTextExitStyle.fade => child,
      TrackTextExitStyle.rise => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.16),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
      TrackTextExitStyle.descend => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.16),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
      TrackTextExitStyle.sideways => SlideTransition(
        position: Tween<Offset>(
          begin: Offset(-_globalSlideDirection * 0.10, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
      TrackTextExitStyle.shrink => ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
        child: child,
      ),
    };
    return FadeTransition(opacity: animation, child: outgoing);
  }

  void _measureTexts(
    BuildContext context,
    double w,
    Color textColor,
    double titleFontSize,
    double artistFontSize,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final String key =
        "${AppState.trackTitle}|${AppState.artistName}|$w|$titleFontSize|$artistFontSize|${AppState.titleWeightValue}|${AppState.artistWeightValue}|${AppState.currentFontFamily}|${AppState.fontsRevision.value}|${AppState.componentScale}|${scaler.scale(titleFontSize)}|${scaler.scale(artistFontSize)}|$direction|$locale";
    if (key == _lastMeasureKey) return;
    _lastMeasureKey = key;

    final titleStyle = TextStyle(
      fontSize: titleFontSize,
      fontWeight: AppState.titleWeight,
      fontVariations: AppState.variationsFor(
        AppState.titleWeightValue,
        fontSize: titleFontSize,
      ),
      fontFamily: AppState.effectiveGlobalFontFamily,
      color: textColor,
      fontFamilyFallback: AppState.textFontFallback,
      letterSpacing: 0.0,
      height: 1.2,
    );
    final artistStyle = TextStyle(
      fontSize: artistFontSize,
      fontWeight: AppState.artistWeight,
      fontVariations: AppState.variationsFor(
        AppState.artistWeightValue,
        fontSize: artistFontSize,
      ),
      fontFamily: AppState.effectiveGlobalFontFamily,
      color: textColor.withValues(alpha: 0.7),
      fontFamilyFallback: AppState.textFontFallback,
      height: 1.2,
    );

    final titlePainter = TextPainter(
      text: TextSpan(text: AppState.trackTitle, style: titleStyle),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      textHeightBehavior: AppState.crispTextHeightBehavior,
    )..layout(maxWidth: w);
    final artistPainter = TextPainter(
      text: TextSpan(text: AppState.artistName, style: artistStyle),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      textHeightBehavior: AppState.crispTextHeightBehavior,
    )..layout(maxWidth: w);

    _cachedTitleTargetWidth = titlePainter.width;
    _cachedTitleTargetHeight = titlePainter.height;
    _cachedArtistTargetWidth = artistPainter.width;
    _cachedArtistTargetHeight = artistPainter.height;
    titlePainter.dispose();
    artistPainter.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool textOverArtwork = AppState.enableGlow;
    final Color textColor = textOverArtwork
        ? Colors.white
        : AppState.currentScheme.onSurface;
    final Color subTextColor = textOverArtwork
        ? Colors.white.withValues(alpha: 0.78)
        : AppState.currentScheme.onSurfaceVariant;
    final bool isV = widget.isVertical;
    final bool canPrevious =
        AppState.showPlaybackControls &&
        MediaCapability.supports(
          AppState.mediaCapabilities,
          MediaCapability.previous,
        );
    final bool canPlayPause =
        AppState.showPlaybackControls &&
        MediaCapability.supports(
          AppState.mediaCapabilities,
          MediaCapability.playPause,
        );
    final bool canNext =
        AppState.showPlaybackControls &&
        MediaCapability.supports(
          AppState.mediaCapabilities,
          MediaCapability.next,
        );
    final bool hasProgress = _hasTimeline;
    final bool hasControls = canPrevious || canPlayPause || canNext;

    return Builder(
      builder: (context) {
        final WidgetLayout targetLayout = isV
            ? WidgetLayout.vertical
            : WidgetLayout.horizontal;
        final double availableW = AppState.innerPlayerWidthOf(targetLayout);
        final double availableH = AppState.corePlayerHeightOf(targetLayout);
        final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final double md3ProgressHeight = AppState.showPlaybackTime
            ? math.max(18.0, PlaybackTimeLabel.preferredHeight(context))
            : switch (AppState.progressStyle) {
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
          if (AppState.showPlaybackTime) progressW = infoW;
          playH = hasControls ? (availableH * 0.116).clamp(52.0, 60.0) : 0.0;
          btnH = playH * 0.83;

          final int gapCount =
              2 + (hasProgress ? 1 : 0) + (hasControls ? 1 : 0);
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
          if (AppState.showPlaybackTime) progressW = infoW;
          final double contentHeight = math.max(
            80.0,
            availableH - padding * 2.0,
          );
          playH = hasControls ? (contentHeight * 0.44).clamp(48.0, 58.0) : 0.0;
          btnH = playH * 0.83;

          final int gapCount =
              1 + (hasProgress ? 1 : 0) + (hasControls ? 1 : 0);
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

        final double prevW = canPrevious
            ? shapedWidth(AppState.prevButtonShape, btnH, 0.34)
            : 0.0;
        final double playW = canPlayPause
            ? shapedWidth(AppState.playButtonShape, playH, 0.31)
            : 0.0;
        final double nextW = canNext
            ? shapedWidth(AppState.nextButtonShape, btnH, 0.34)
            : 0.0;
        final double buttonGap = (infoW * 0.052).clamp(8.0, 16.0);
        final int visibleButtonCount =
            (canPrevious ? 1 : 0) + (canPlayPause ? 1 : 0) + (canNext ? 1 : 0);
        final double buttonGroupWidth =
            prevW +
            playW +
            nextW +
            buttonGap * math.max(0, visibleButtonCount - 1);
        double buttonCursor = isV
            ? (availableW - buttonGroupWidth) / 2.0
            : titleL;
        double takeButtonLeft(bool visible, double width, bool hasFollowing) {
          final double left = buttonCursor;
          if (visible) {
            buttonCursor += width;
            if (hasFollowing) buttonCursor += buttonGap;
          }
          return left;
        }

        final double prevL = takeButtonLeft(
          canPrevious,
          prevW,
          canPlayPause || canNext,
        );
        final double playL = takeButtonLeft(canPlayPause, playW, canNext);
        final double nextL = takeButtonLeft(canNext, nextW, false);

        
        
        
        
        
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

        _measureTexts(
          context,
          snappedInfoW,
          textColor,
          titleFontSize,
          artistFontSize,
        );
        final bool hasTrackText = _hasTrackText(AppState.trackTitle);
        final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
        final Duration mediaTextTransitionDuration =
            _effectiveTextTransitionDuration(
              math.max(_cachedTitleTargetWidth, _cachedArtistTargetWidth),
              hasTrack: hasTrackText,
              reduceMotion: reduceMotion,
            );
        final Duration titleTransitionDuration = mediaTextTransitionDuration;
        final Duration artistTransitionDuration = mediaTextTransitionDuration;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            MorphPositioned(
              motion: widget.layoutMotion,
              cover: true,
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: coverL,
              top: coverT,
              width: coverSize,
              height: coverSize,
              child: _buildCover(coverSize),
            ),

            MorphPositioned(
              motion: widget.layoutMotion,
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: snappedTitleL,
              top: snappedTitleT,
              width: snappedInfoW,
              height: snappedTitleH,
              child: RepaintBoundary(
                child: AnimatedSwitcher(
                  key: ValueKey(
                    'title_${AppState.trackTextAnimationsEnabled}_${AppState.trackTextTransitionStyle}_$reduceMotion',
                  ),
                  duration: titleTransitionDuration,
                  reverseDuration: titleTransitionDuration == Duration.zero
                      ? Duration.zero
                      : mediaTextTransitionDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: <Widget>[...previousChildren, ?currentChild],
                  ),
                  transitionBuilder: (child, anim) {
                    return _buildTextTransition(
                      child,
                      anim,
                      isIncoming:
                          child.key == ValueKey('title|${AppState.trackTitle}'),
                      reduceMotion: reduceMotion,
                    );
                  },
                  child: _TextInfoWidget(
                    key: ValueKey('title|${AppState.trackTitle}'),
                    text: AppState.trackTitle,
                    isPlaceholder: !hasTrackText,
                    measuredWidth: _cachedTitleTargetWidth,
                    measuredHeight: _cachedTitleTargetHeight,
                    layoutMotion: widget.layoutMotion,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: AppState.titleWeight,
                      fontVariations: AppState.variationsFor(
                        AppState.titleWeightValue,
                        fontSize: titleFontSize,
                      ),
                      color: textColor,
                      fontFamily: AppState.effectiveGlobalFontFamily,
                      fontFamilyFallback: AppState.textFontFallback,
                      letterSpacing: 0.0,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),

            MorphPositioned(
              motion: widget.layoutMotion,
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: snappedArtistL,
              top: snappedArtistT,
              width: snappedInfoW,
              height: snappedArtistH,
              child: RepaintBoundary(
                child: AnimatedSwitcher(
                  key: ValueKey(
                    'artist_${AppState.trackTextAnimationsEnabled}_${AppState.trackTextTransitionStyle}_$reduceMotion',
                  ),
                  duration: artistTransitionDuration,
                  reverseDuration: artistTransitionDuration == Duration.zero
                      ? Duration.zero
                      : mediaTextTransitionDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: <Widget>[...previousChildren, ?currentChild],
                  ),
                  transitionBuilder: (child, anim) {
                    return _buildTextTransition(
                      child,
                      anim,
                      isIncoming:
                          child.key ==
                          ValueKey('artist|${AppState.artistName}'),
                      reduceMotion: reduceMotion,
                    );
                  },
                  child: _TextInfoWidget(
                    key: ValueKey('artist|${AppState.artistName}'),
                    text: AppState.artistName,
                    isPlaceholder: !hasTrackText,
                    measuredWidth: _cachedArtistTargetWidth,
                    measuredHeight: _cachedArtistTargetHeight,
                    layoutMotion: widget.layoutMotion,
                    style: TextStyle(
                      fontSize: artistFontSize,
                      fontWeight: AppState.artistWeight,
                      fontVariations: AppState.variationsFor(
                        AppState.artistWeightValue,
                        fontSize: artistFontSize,
                      ),
                      color: subTextColor,
                      fontFamily: AppState.effectiveGlobalFontFamily,
                      fontFamilyFallback: AppState.textFontFallback,
                      letterSpacing: 0.0,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),

            MorphPositioned(
              motion: widget.layoutMotion,
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: titleL,
              top: progressT,
              width: progressW,
              height: progressH,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: switch (AppState.progressStyle) {
                          MD3ProgressStyle.linear => isV ? 5.0 : 4.0,
                          MD3ProgressStyle.pill => isV ? 9.0 : 8.0,
                          MD3ProgressStyle.segmented => isV ? 7.0 : 6.0,
                        },
                        child: const RepaintBoundary(
                          child: _PlaybackProgress(),
                        ),
                      ),
                    ),
                  ),
                  if (AppState.showPlaybackTime)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: RepaintBoundary(
                        child: PlaybackTimeLabel(maxWidth: progressW * .58),
                      ),
                    ),
                ],
              ),
            ),

            MorphPositioned(
              motion: widget.layoutMotion,
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: prevL,
              top: btnT,
              width: prevW,
              height: btnH,
              child: canPrevious
                  ? PlaybackControlButton(
                      key: const ValueKey('transport_previous'),
                      width: prevW,
                      height: btnH,
                      borderRadius: AppState.getShapeRadius(
                        AppState.prevButtonShape,
                        btnH,
                      ),
                      background: AppState.currentScheme.primaryContainer,
                      foreground: AppState.currentScheme.onPrimaryContainer,
                      icon: Icons.skip_previous_rounded,
                      iconSize: btnH * 0.54,
                      label: '上一首',
                      direction: -1,
                      onPressed: () {
                        AppState.sendCommand(MediaCommand.previous);
                      },
                    )
                  : const SizedBox.shrink(),
            ),

            MorphPositioned(
              motion: widget.layoutMotion,
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: nextL,
              top: btnT,
              width: nextW,
              height: btnH,
              child: canNext
                  ? PlaybackControlButton(
                      key: const ValueKey('transport_next'),
                      width: nextW,
                      height: btnH,
                      borderRadius: AppState.getShapeRadius(
                        AppState.nextButtonShape,
                        btnH,
                      ),
                      background: AppState.currentScheme.primaryContainer,
                      foreground: AppState.currentScheme.onPrimaryContainer,
                      icon: Icons.skip_next_rounded,
                      iconSize: btnH * 0.54,
                      label: '下一首',
                      direction: 1,
                      onPressed: () {
                        AppState.sendCommand(MediaCommand.next);
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            Positioned.fill(
              child: PlaybackPauseShade(paused: !AppState.isPlaying),
            ),
            MorphPositioned(
              motion: widget.layoutMotion,
              duration: AppState.layoutSwitchDuration,
              curve: AppState.layoutSwitchCurve,
              left: playL,
              top: playT,
              width: playW,
              height: playH,
              child: canPlayPause
                  ? PlaybackControlButton(
                      key: const ValueKey('transport_play_pause'),
                      width: playW,
                      height: playH,
                      borderRadius: AppState.getShapeRadius(
                        AppState.playButtonShape,
                        playH,
                      ),
                      background: AppState.currentScheme.primary,
                      foreground: AppState.currentScheme.onPrimary,
                      icon: Icons.play_arrow_rounded,
                      iconSize: playH * 0.59,
                      isPlaying: AppState.isPlaying,
                      label: AppState.isPlaying ? '暂停' : '播放',
                      onPressed: () {
                        AppState.sendCommand(MediaCommand.togglePlayPause);
                        setState(
                          () => AppState.isPlaying = !AppState.isPlaying,
                        );
                        AppState.notifyBackgroundChanged();
                      },
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCover(double size) {
    if (_directionCoverIdentity != _coverIdentity) {
      _directionCoverIdentity = _coverIdentity;
      _coverDirection = _globalSlideDirection;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return CoverArtworkSwitcher(
      fit: StackFit.expand,
      style: AppState.coverTransitionStyle,
      direction: _coverDirection,
      reduceMotion: reduceMotion,
      borderRadius: BorderRadius.circular((size * 0.055).clamp(14.0, 20.0)),
      child: IgnorePointer(
        key: ValueKey(_coverIdentity),
        ignoring: !AppState.isPlaying,
        child: RepaintBoundary(
          child: CoverParallax(
            size: size,
            borderRadius: BorderRadius.circular(
              (size * 0.055).clamp(14.0, 20.0),
            ),
            backgroundColor: AppState.currentScheme.surface,
            accentColor: AppState.currentScheme.primary,
            image: AppState.coverProvider,
            isPlaying: AppState.isPlaying,
            dimWhenPaused: false,
            enable3D: AppState.enable3DCover,
            layered: AppState.enableCoverLayers,
            layerIdentity: _coverIdentity,
          ),
        ),
      ),
    );
  }

  String get _coverIdentity => AppState.currentCoverVersion.isNotEmpty
      ? AppState.currentCoverVersion
      : 'fallback|${AppState.trackTitle}|${AppState.artistName}';
}
