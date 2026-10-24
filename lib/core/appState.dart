import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'appTypography.dart';

import 'mediaProvider.dart';
import 'mediaCaptureBackend.dart';
import 'musicFetcherBackend.dart';
import 'nativeMediaBackend.dart';
import 'lyricsCoordinator.dart';
import 'lyricsHighlight.dart';
export 'lyricsHighlight.dart';
import 'localLrcLyricsProvider.dart';
import 'lrclibLyricsProvider.dart';
import 'qqMusicLyricsProvider.dart';
import 'neteaseLyricsProvider.dart';
import 'amllLyricsProvider.dart';
import 'lyricsFallbackChain.dart';
import 'neteasePlaylistQueueProvider.dart';
import 'platformProvider.dart';
import 'localPlaylistQueueProvider.dart';
import 'qqMusicPlaylistQueueProvider.dart';
import 'queueCoordinator.dart';
import 'systemPerformanceProvider.dart';
import 'nextUpPreviewController.dart';
import 'persistentCache.dart';
import 'lyricsDiskCache.dart';
import 'trackNavigationDirection.dart';



part 'appSettingsPersistence.dart';

enum MD3Shape {
  circle,
  stadium,
  roundedMedium,
  roundedLarge,
  roundedExtraSmall,
  roundedSmall,
  roundedExtraLarge,
}

enum GlowMode { waterfall, wallpaper }

enum SpectrumMode { off, bars, mirror, waveform }

enum LyricsProviderChoice { lrclib, localLrc, qqMusic, neteaseCloud, amll }

enum LyricsTransitionStyle {
  fade,
  rise,
  descend,
  sideways,
  zoom,
  none,
  film,
  flip,
  settle,
  wipe,
}

enum CoverTransitionStyle {
  softSlide,
  fade,
  filmVertical,
  filmHorizontal,
  flipHorizontal,
  flipVertical,
  stack,
  none,
}

enum TrackTextTransitionStyle {
  particles,
  fade,
  rise,
  sideways,
  zoom,
  descend,
  settle,
  sweep,
}

enum TrackTextExitStyle { fade, rise, descend, sideways, shrink }

enum MD3ProgressStyle { linear, pill, segmented }

enum WidgetLayout { horizontal, vertical }

enum ComponentSizeMode { small, standard, large, custom }

class AppState {
  static Future<void> Function()? externalMediaStopper;
  static int fetcherPid = 0;
  static String trackTitle = "未在播放";
  static String artistName = "无媒体会话";
  static String trackVersion = "";
  static bool isPlaying = false;
  static int mediaCapabilities = MediaCapability.smtcDefault;
  static String selectedSourceAppId = '';
  static String localLyricsDirectory = '';
  static String playlistFilePath = '';
  static String qqPlaylistLink = '';
  static String neteasePlaylistLink = '';
  static String selectedQueueProviderId = '';
  static bool get hasPlaylistConfigured =>
      playlistFilePath.isNotEmpty ||
      qqPlaylistLink.isNotEmpty ||
      neteasePlaylistLink.isNotEmpty;
  static bool showNextUp = false;
  static int nextUpLeadSeconds = 20;
  static bool? isShuffleActive;
  static String autoRepeatMode = '';
  static PlatformTrack? currentPlatformTrack;
  static final trackNavigation = TrackNavigationDirection();
  static final LrclibLyricsProvider _lrclibLyrics = LrclibLyricsProvider(
    cache: LyricsDiskCache(lyricsCacheStore),
  );
  static final AmllLyricsProvider _amllLyrics = AmllLyricsProvider();
  static final _lyricsFallback = LyricsFallbackChain(
    id: 'amll',
    sources: [_amllLyrics, _lrclibLyrics],
  );
  static final QqMusicPlaylistQueueProvider _qqPlaylist =
      QqMusicPlaylistQueueProvider(playlistInput: () => qqPlaylistLink);
  static final NeteasePlaylistQueueProvider _neteasePlaylist =
      NeteasePlaylistQueueProvider(playlistInput: () => neteasePlaylistLink);
  static final PlatformProviderRegistry platformProviders =
      PlatformProviderRegistry()
        ..register(_lrclibLyrics)
        ..register(LocalLrcLyricsProvider(() => localLyricsDirectory))
        ..register(
          QqMusicLyricsProvider(
            fallback: _lyricsFallback,
            wordFallback: _amllLyrics,
          ),
        )
        ..register(
          NeteaseLyricsProvider(
            fallback: _lyricsFallback,
            wordFallback: _amllLyrics,
          ),
        )
        ..register(_lyricsFallback)
        ..register(_qqPlaylist)
        ..register(_neteasePlaylist)
        ..register(LocalPlaylistQueueProvider(() => playlistFilePath));
  static int lyricsCacheLimitMiB = 16;
  static bool usePersistentCaches = true;
  static int backgroundCacheLimitMiB = 128;
  static final Directory _cacheRoot = Directory(
    '${Platform.environment['LOCALAPPDATA'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path}${Platform.pathSeparator}MD3MusicWidget${Platform.pathSeparator}cache-v1',
  );
  static String customCacheDirectory = '';
  static Future<void> _cacheDirectoryTail = Future.value();
  static String get cacheDirectoryPath =>
      lyricsCacheStore.directory.parent.path;
  static final PersistentCache lyricsCacheStore = PersistentCache(
    isEnabled: () => usePersistentCaches,
    directory: Directory('${_cacheRoot.path}${Platform.pathSeparator}lyrics'),
    limitBytes: () => lyricsCacheLimitMiB * 1024 * 1024,
    maximumEntryBytes: 2 * 1024 * 1024,
  );
  static final PersistentCache backgroundCacheStore = PersistentCache(
    isEnabled: () => usePersistentCaches,
    directory: Directory(
      '${_cacheRoot.path}${Platform.pathSeparator}background',
    ),
    limitBytes: () => backgroundCacheLimitMiB * 1024 * 1024,
  );
  static final LyricsCoordinator lyrics = LyricsCoordinator(
    platformProviders,
    cache: LyricsDiskCache(lyricsCacheStore),
    maximumAttempts: 3,
    retryMissing: true,
    preferWordTimings: () => wordLyricsEnabled,
  );
  static final QueueCoordinator queue = QueueCoordinator(
    platformProviders,
    maximumAttempts: 3,
  );

  static void refreshLyrics({bool force = false}) {
    unawaited(
      lyrics.setTrack(
        showLyrics ? currentPlatformTrack : null,
        providerId: lyricsProviderChoice.name,
        force: force,
      ),
    );
  }

  static void refreshQueue({bool force = false}) {
    _nextUpPreviewController?.refresh();
    if (force) {
      _qqPlaylist.invalidate();
      _neteasePlaylist.invalidate();
    }
    unawaited(
      queue.setTrack(
        showNextUp ? currentPlatformTrack : null,
        enabled: showNextUp,
        force: force,
        providerId: selectedQueueProviderId.isEmpty
            ? null
            : selectedQueueProviderId,
      ),
    );
  }

  static PlatformQueueItem? get nextQueueItem {
    if (!showNextUp || isShuffleActive == true || autoRepeatMode == 'track') {
      return null;
    }
    return queue.queue?.nextItem(wrap: autoRepeatMode == 'list');
  }

  static bool get shouldPreviewNext {
    if (!isPlaying || nextQueueItem == null || playbackDurationMs <= 0) {
      return false;
    }
    final remaining = playbackDurationMs - estimatedPlaybackPositionMs;
    final windowMs = (nextUpLeadSeconds * 1000.0).clamp(
      0.0,
      playbackDurationMs,
    );
    return remaining >
            NextUpPreviewController.dismissBeforeEnd.inMilliseconds &&
        remaining <= windowMs;
  }

  static void setLocalLyricsDirectory(String path) {
    localLyricsDirectory = path;
    platformProviders.register(
      LocalLrcLyricsProvider(() => localLyricsDirectory),
    );
    refreshLyrics();
  }

  static bool Function(MediaCommand command)? mediaCommandSender;
  static MediaCaptureBackend Function() mediaBackendFactory =
      const bool.fromEnvironment('LEGACY_MEDIA_BACKEND')
      ? MusicFetcherBackend.new
      : NativeMediaBackend.new;
  static MediaCaptureBackend? _mediaBackend;
  static MediaCaptureBackend get mediaBackend =>
      _mediaBackend ??= mediaBackendFactory();

  static void recordFetcherProcess(MediaCaptureBackend backend, int processId) {
    
    if (backend.usesExternalProcess && processId > 0) fetcherPid = processId;
  }

  static Future<void> releaseMediaBackend(MediaCaptureBackend backend) async {
    if (identical(_mediaBackend, backend)) _mediaBackend = null;
    await backend.close();
  }

  static double playbackPositionMs = 0.0;
  static double playbackDurationMs = 0.0;
  static int playbackUpdatedAtMs = 0;
  static const int spectrumBandCount = 32;
  static final Float32List spectrumLevels = Float32List(spectrumBandCount);
  static int spectrumUpdatedAtMs = 0;
  static final Stopwatch _playbackClock = Stopwatch()..start();
  static int _playbackReceivedAtMonotonicMs = 0;
  static int _playbackInitialAgeMs = 0;

  static ImageProvider? coverProvider;
  static ImageProvider? bgBlurProvider;
  static String currentCoverVersion = "";
  static String currentRawBase64 = "";

  
  
  
  static final ValueNotifier<int> backgroundRevision = ValueNotifier<int>(0);
  static void notifyBackgroundChanged() {
    backgroundRevision.value++;
    _updateMediaTextColor();
  }

  static final ValueNotifier<Color> mediaTextColor = ValueNotifier<Color>(
    Colors.white,
  );
  static Color? _previousArtworkTone;
  static Color? _targetArtworkTone;
  static int _artworkToneChangedAt = 0;
  static Timer? _mediaTextToneTimer;
  static Color? get _estimatedArtworkTone => Color.lerp(
    _previousArtworkTone,
    _targetArtworkTone,
    ((_playbackClock.elapsedMilliseconds - _artworkToneChangedAt) / 800).clamp(
      0.0,
      1.0,
    ),
  );
  static void setArtworkTone(Color? color) {
    _previousArtworkTone = _targetArtworkTone == null
        ? color
        : _estimatedArtworkTone;
    _targetArtworkTone = color;
    _artworkToneChangedAt = _playbackClock.elapsedMilliseconds;
    _mediaTextToneTimer?.cancel();
    _updateMediaTextColor();
    if (_previousArtworkTone == _targetArtworkTone) return;
    _mediaTextToneTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) {
      _updateMediaTextColor();
      if (_playbackClock.elapsedMilliseconds - _artworkToneChangedAt >= 800) {
        timer.cancel();
        _mediaTextToneTimer = null;
      }
    });
  }

  static void finishArtworkToneTransition() {
    _mediaTextToneTimer?.cancel();
    _mediaTextToneTimer = null;
    _previousArtworkTone = _targetArtworkTone;
    _artworkToneChangedAt = _playbackClock.elapsedMilliseconds - 800;
    _updateMediaTextColor();
  }

  static Color get estimatedMediaBackdrop {
    final dark = themeBrightness == Brightness.dark;
    final surface = dark
        ? (enableGlow
              ? currentScheme.surfaceContainerLow
              : enableOledTheme
              ? Colors.black
              : currentScheme.surfaceContainerHigh)
        : enableGlow
        ? currentScheme.surface
        : currentScheme.surfaceContainerHighest;
    final tone = _estimatedArtworkTone;
    final imageColor = enableGlow && tone != null
        ? Color.alphaBlend(tone, surface)
        : surface;
    final lum = currentScheme.surface.computeLuminance();
    final opacity = dark
        ? (0.25 + lum * 0.50).clamp(0.25, 0.75)
        : (0.25 + (1 - lum) * 0.40).clamp(0.25, 0.65);
    return Color.alphaBlend(
      (dark ? Colors.black : Colors.white).withValues(alpha: opacity),
      imageColor,
    );
  }

  static Color readableMediaColor(Color background) =>
      background.computeLuminance() > 0.179 ? Colors.black : Colors.white;
  static void _updateMediaTextColor() =>
      mediaTextColor.value = readableMediaColor(estimatedMediaBackdrop);

  static Future<void> applyCacheLimits() async {
    await Future.wait([
      lyricsCacheStore.applyLimit(),
      backgroundCacheStore.applyLimit(),
    ]);
  }

  static Future<void> clearPersistentCaches() async {
    await Future.wait([lyricsCacheStore.clear(), backgroundCacheStore.clear()]);
  }

  static Future<void> setCacheDirectory(
    String path, {
    bool persist = true,
    bool migrate = true,
  }) {
    Future<void> change() async {
      final selected = path.trim();
      if (selected.contains('\u0000')) {
        throw const FormatException('Invalid cache directory');
      }
      final root = selected.isEmpty
          ? _cacheRoot
          : Directory(
              '${Directory(selected).absolute.path}${Platform.pathSeparator}MD3MusicWidget-cache-v1',
            );
      final oldLyrics = lyricsCacheStore.directory;
      final oldBackground = backgroundCacheStore.directory;
      try {
        await lyricsCacheStore.relocate(
          Directory('${root.path}${Platform.pathSeparator}lyrics'),
          copyExisting: migrate,
        );
        await backgroundCacheStore.relocate(
          Directory('${root.path}${Platform.pathSeparator}background'),
          copyExisting: migrate,
        );
      } catch (_) {
        await lyricsCacheStore.relocate(oldLyrics);
        await backgroundCacheStore.relocate(oldBackground);
        rethrow;
      }
      customCacheDirectory = selected.isEmpty
          ? ''
          : Directory(selected).absolute.path;
      if (persist) await saveSettings();
    }

    
    
    if (!usePersistentCaches) return change();
    final result = _cacheDirectoryTail.then((_) => change());
    _cacheDirectoryTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static final ValueNotifier<int> playbackRevision = ValueNotifier<int>(0);
  static final ValueNotifier<bool> nextUpPreviewVisible = ValueNotifier<bool>(
    false,
  );
  static bool nextUpPanelOccupied = false;
  static NextUpPreviewController? _nextUpPreviewController;
  static NextUpPreviewController get nextUpPreviewController {
    if (_nextUpPreviewController case final existing?) return existing;
    final controller = NextUpPreviewController(
      readInput: () => NextUpPreviewInput(
        trackIdentity: currentPlatformTrack?.contextIdentity,
        next: nextQueueItem,
        enabled: showNextUp && hasPlaylistConfigured,
        playing: isPlaying,
        durationMs: playbackDurationMs,
        positionMs: estimatedPlaybackPositionMs,
        leadSeconds: nextUpLeadSeconds,
      ),
    );
    _nextUpPreviewController = controller;
    controller.addListener(
      () => nextUpPreviewVisible.value = controller.visible,
    );
    playbackRevision.addListener(controller.refresh);
    queue.addListener(controller.refresh);
    controller.refresh();
    return controller;
  }

  static final ValueNotifier<int> trackTransitionRevision = ValueNotifier<int>(
    0,
  );
  static final ValueNotifier<int> spectrumRevision = ValueNotifier<int>(0);
  static final ValueNotifier<int> fontsRevision = ValueNotifier<int>(0);
  static final ValueNotifier<int> typographyRevision = ValueNotifier<int>(0);
  static final ValueNotifier<int> lyricsVisualRevision = ValueNotifier<int>(0);

  static void notifyTypographyChanged() => typographyRevision.value++;
  static void notifyLyricsVisualChanged() => lyricsVisualRevision.value++;

  static void notifyTrackTransition() => trackTransitionRevision.value++;

  static void updateSpectrum(List<dynamic> values, int updatedAtMs) {
    bool changed = false;
    for (int i = 0; i < spectrumBandCount; i++) {
      final value = i < values.length ? values[i] : 0.0;
      final level = value is num ? value.toDouble() : 0.0;
      final double nextLevel = level.clamp(0.0, 1.0).toDouble();
      if ((spectrumLevels[i] - nextLevel).abs() > 0.0015) changed = true;
      spectrumLevels[i] = nextLevel;
    }
    spectrumUpdatedAtMs = updatedAtMs;
    if (changed) spectrumRevision.value++;
  }

  static void updateSpectrumTyped(Float32List values, int updatedAtMs) {
    bool changed = false;
    for (int i = 0; i < spectrumBandCount; i++) {
      final double level = i < values.length ? values[i] : 0.0;
      final double nextLevel = level.isFinite
          ? level.clamp(0.0, 1.0).toDouble()
          : 0.0;
      if ((spectrumLevels[i] - nextLevel).abs() > 0.0015) changed = true;
      spectrumLevels[i] = nextLevel;
    }
    spectrumUpdatedAtMs = updatedAtMs;
    if (changed) spectrumRevision.value++;
  }

  static void clearSpectrum() {
    bool changed = false;
    for (final level in spectrumLevels) {
      if (level > 0.0015) {
        changed = true;
        break;
      }
    }
    spectrumLevels.fillRange(0, spectrumBandCount, 0.0);
    spectrumUpdatedAtMs = 0;
    if (changed) spectrumRevision.value++;
  }

  static double get estimatedPlaybackPositionMs {
    if (!isPlaying || playbackUpdatedAtMs <= 0) return playbackPositionMs;
    final int elapsedMs =
        _playbackClock.elapsedMilliseconds - _playbackReceivedAtMonotonicMs;
    final double estimated =
        playbackPositionMs + _playbackInitialAgeMs + elapsedMs.clamp(0, 60000);
    return estimated > playbackDurationMs && playbackDurationMs > 0
        ? playbackDurationMs
        : estimated;
  }

  static void updatePlaybackTimeline({
    required double positionMs,
    required double durationMs,
    required int updatedAtMs,
  }) {
    final double safeDuration = durationMs.isFinite && durationMs > 0
        ? durationMs
        : 0.0;
    final double safePosition = positionMs.isFinite && positionMs > 0
        ? positionMs
        : 0.0;
    playbackDurationMs = safeDuration;
    playbackPositionMs = safeDuration > 0
        ? safePosition.clamp(0.0, safeDuration)
        : safePosition;
    playbackUpdatedAtMs = updatedAtMs > 0
        ? updatedAtMs
        : DateTime.now().millisecondsSinceEpoch;
    final int receivedAtWallClockMs = DateTime.now().millisecondsSinceEpoch;
    _playbackInitialAgeMs = isPlaying && updatedAtMs > 0
        ? (receivedAtWallClockMs - updatedAtMs).clamp(0, 2000)
        : 0;
    _playbackReceivedAtMonotonicMs = _playbackClock.elapsedMilliseconds;
    playbackRevision.value++;
  }

  static ColorScheme currentScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1E5B6B),
    brightness: Brightness.dark,
  );

  static bool isAlwaysOnTop = true;
  static bool isMousePassthrough = false;
  static Brightness themeBrightness = Brightness.dark;

  static bool enableGlow = true;
  static GlowMode glowMode = GlowMode.waterfall;
  static const defaultRightCoverDarkening = 0.32;
  static const defaultRightCoverFadeLength = 0.65;
  static const defaultRightCoverBlur = 1.2;
  static double rightCoverDarkening = defaultRightCoverDarkening;
  static double rightCoverFadeLength = defaultRightCoverFadeLength;
  static bool rightCoverFadeLinked = true;
  static double rightCoverFadeLengthX = defaultRightCoverFadeLength;
  static double rightCoverFadeLengthY = defaultRightCoverFadeLength;
  static double get rightCoverEffectiveFadeX =>
      rightCoverFadeLinked ? rightCoverFadeLength : rightCoverFadeLengthX;
  static double get rightCoverEffectiveFadeY =>
      rightCoverFadeLinked ? rightCoverFadeLength : rightCoverFadeLengthY;
  static void setRightCoverFadeLinked(bool linked) {
    if (rightCoverFadeLinked == linked) return;
    if (linked) {
      rightCoverFadeLength =
          (rightCoverFadeLengthX + rightCoverFadeLengthY) / 2;
    } else {
      
      rightCoverFadeLengthX = rightCoverFadeLength;
      rightCoverFadeLengthY = rightCoverFadeLength;
    }
    rightCoverFadeLinked = linked;
  }

  static double rightCoverBlur = defaultRightCoverBlur;
  static final rightArtworkRevision = ValueNotifier<int>(0);
  static void notifyRightArtworkChanged() => rightArtworkRevision.value++;
  static SpectrumMode spectrumMode = SpectrumMode.off;
  static const defaultSpectrumThickness = 1.0;
  static double spectrumThickness = defaultSpectrumThickness;
  static bool automaticSpectrumColumns = true;
  static int spectrumColumnCount = 32;
  static final spectrumStyleRevision = ValueNotifier<int>(0);
  static void notifySpectrumStyleChanged() => spectrumStyleRevision.value++;
  static bool showLyrics = false;
  static bool hideUnavailableLyrics = false;
  static bool wordLyricsEnabled = true;
  static bool wordLyricsSmokeEnabled = false;
  static LyricsHighlightStyle lyricsHighlightStyle = LyricsHighlightStyle.sweep;
  static double lyricsInactiveOpacity = .46;
  static double lyricsOffsetMs = 0;
  static double get lyricsPlaybackPositionMs =>
      estimatedPlaybackPositionMs + lyricsOffsetMs;
  static bool get lyricsPanelVisible =>
      showLyrics &&
      (!hideUnavailableLyrics ||
          lyrics.state.status == LyricsStatus.loading ||
          lyrics.state.status == LyricsStatus.ready);
  static const String defaultFontFamily = 'System Default';
  static const String bundledFontFamily = 'MiSans';
  static const double defaultTitleWeightValue = 700.0;
  static const double defaultArtistWeightValue = 400.0;
  static const double defaultLyricsWeightValue = 500.0;
  static const double defaultLyricsFontSize = 14.0;
  static LyricsProviderChoice lyricsProviderChoice =
      LyricsProviderChoice.lrclib;
  static LyricsTransitionStyle lyricsTransitionStyle =
      LyricsTransitionStyle.fade;
  static bool lyricsAnimationsLinked = true;
  static LyricsTransitionStyle lyricsExitTransitionStyle =
      LyricsTransitionStyle.fade;
  static LyricsTransitionStyle get effectiveLyricsExitTransitionStyle =>
      lyricsAnimationsLinked
      ? lyricsTransitionStyle
      : lyricsExitTransitionStyle;
  static bool lyricsUseThemeFont = true;
  static String lyricsFontFamily = defaultFontFamily;
  static double lyricsWeightValue = defaultLyricsWeightValue;
  static double lyricsFontSize = defaultLyricsFontSize;
  static MD3ProgressStyle progressStyle = MD3ProgressStyle.linear;
  static bool showPlaybackTime = false;
  static MD3Shape settingsNavigationShape = MD3Shape.roundedLarge;
  static bool enableProgressAutoContrast = true;
  static bool enableOledTheme = false;
  static bool enable3DCover = true;
  static bool enableCoverLayers = true;
  static CoverTransitionStyle coverTransitionStyle =
      CoverTransitionStyle.softSlide;
  static bool showPlaybackControls = true;
  static bool trackTextAnimationsEnabled = true;
  static TrackTextTransitionStyle trackTextTransitionStyle =
      TrackTextTransitionStyle.particles;
  static bool trackTextAnimationsLinked = true;
  static TrackTextExitStyle trackTextExitStyle = TrackTextExitStyle.fade;
  static bool showPerformanceMonitor = false;
  static int performanceMetricsMask = PerformanceMetric.allMask;
  static bool get performanceMonitorVisible =>
      showPerformanceMonitor && performanceMetricsMask != 0;
  static bool performanceMetricEnabled(PerformanceMetric metric) =>
      metric.enabledIn(performanceMetricsMask);
  static String performanceProcessExecutable = '';
  static final performanceRevision = ValueNotifier<int>(0);
  static void notifyPerformanceChanged() => performanceRevision.value++;
  static DynamicSchemeVariant themeVariant = DynamicSchemeVariant.tonalSpot;

  
  static String currentFontFamily = defaultFontFamily;
  static String get effectiveGlobalFontFamily =>
      currentFontFamily == defaultFontFamily
      ? bundledFontFamily
      : currentFontFamily;
  static List<String> loadedSystemFonts = ['System Default'];
  static List<String> customFontPaths = [];

  
  
  static const List<String> textFontFallback = [
    bundledFontFamily,
    'Segoe UI Variable Text',
    'Segoe UI',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Yu Gothic UI',
    'Meiryo',
    'Malgun Gothic',
    'Arial Unicode MS',
  ];

  
  
  static const TextHeightBehavior crispTextHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  static double snapToDevicePixel(double value, double devicePixelRatio) {
    if (!value.isFinite || devicePixelRatio <= 0) return value;
    return (value * devicePixelRatio).round() / devicePixelRatio;
  }

  static double titleWeightValue = defaultTitleWeightValue;
  static double artistWeightValue = defaultArtistWeightValue;

  static FontWeight weightFor(double value) =>
      FontWeight.values[((value / 100).round() - 1).clamp(0, 8)];
  static List<FontVariation> variationsFor(
    double value, {
    double? fontSize,
    String? fontFamily,
  }) => AppTypography.variations(
    weight: value,
    family: fontFamily ?? effectiveGlobalFontFamily,
    fontSize: fontSize,
    displayScale: componentScale,
  );
  static (ColorScheme, String, double)? _typographyThemeKey;
  static ThemeData? _typographyTheme;
  static ThemeData buildTheme() {
    final key = (currentScheme, effectiveGlobalFontFamily, componentScale);
    if (key == _typographyThemeKey && _typographyTheme != null) {
      return _typographyTheme!;
    }
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: currentScheme,
      fontFamily: effectiveGlobalFontFamily,
      fontFamilyFallback: textFontFallback,
    );
    _typographyThemeKey = key;
    return _typographyTheme = base.copyWith(
      textTheme: AppTypography.refineTheme(
        base.textTheme,
        family: effectiveGlobalFontFamily,
        fallback: textFontFallback,
        displayScale: componentScale,
      ),
      primaryTextTheme: AppTypography.refineTheme(
        base.primaryTextTheme,
        family: effectiveGlobalFontFamily,
        fallback: textFontFallback,
        displayScale: componentScale,
      ),
    );
  }

  static FontWeight get titleWeight => weightFor(titleWeightValue);
  static FontWeight get artistWeight => weightFor(artistWeightValue);
  static FontWeight get lyricsWeight => weightFor(lyricsWeightValue);
  static double _safeWeight(double value, double fallback) =>
      value.isFinite ? value.clamp(100.0, 900.0) : fallback;
  static String? get effectiveLyricsFontFamily {
    final family = lyricsUseThemeFont ? currentFontFamily : lyricsFontFamily;
    if (family != defaultFontFamily) return family;
    return bundledFontFamily;
  }

  static TextStyle lyricsTextStyle(Color color) => TextStyle(
    color: color,
    fontSize: lyricsFontSize,
    fontWeight: lyricsWeight,
    fontVariations: variationsFor(
      lyricsWeightValue,
      fontSize: lyricsFontSize,
      fontFamily: effectiveLyricsFontFamily,
    ),
    fontFamily: effectiveLyricsFontFamily,
    fontFamilyFallback: textFontFallback,
    height: 1.2,
  );

  static MD3Shape prevButtonShape = MD3Shape.circle;
  static MD3Shape playButtonShape = MD3Shape.circle;
  static MD3Shape nextButtonShape = MD3Shape.circle;

  static WidgetLayout widgetLayout = WidgetLayout.horizontal;
  static bool get isVertical => widgetLayout == WidgetLayout.vertical;

  static ComponentSizeMode componentSizeMode = ComponentSizeMode.standard;
  static double customComponentScale = 1.0;
  
  
  static const double standardDisplayScale = 0.90;
  static const double minimumSizeRatio = 0.72;
  static const double maximumSizeRatio = 1.50;
  static const double minimumComponentScale =
      minimumSizeRatio * standardDisplayScale;
  static const double maximumComponentScale =
      maximumSizeRatio * standardDisplayScale;

  static double scaleForSizeMode(ComponentSizeMode mode) => switch (mode) {
    ComponentSizeMode.small => 0.82,
    ComponentSizeMode.standard => 1.0,
    ComponentSizeMode.large => 1.22,
    ComponentSizeMode.custom => customComponentScale.clamp(
      minimumSizeRatio,
      maximumSizeRatio,
    ),
  };

  static double get componentScale =>
      standardDisplayScale * scaleForSizeMode(componentSizeMode);
  static bool get isCustomComponentSize =>
      componentSizeMode == ComponentSizeMode.custom;

  static const double _menuExtraSpace = 200.0;
  static const double cardMargin = 0.0;
  static double innerPlayerWidthOf(WidgetLayout l) =>
      l == WidgetLayout.vertical ? 340.0 : 480.0;
  static double corePlayerHeightOf(WidgetLayout l) => l == WidgetLayout.vertical
      ? (showPlaybackControls ? 520.0 : 448.0)
      : (showPlaybackControls ? 176.0 : 140.0);
  static double spectrumPanelExtentOf(WidgetLayout l) =>
      spectrumMode == SpectrumMode.off && !performanceMonitorVisible
      ? 0.0
      : 64.0;
  static double lyricsPanelExtentOf(WidgetLayout l) => showLyrics ? 64.0 : 0.0;
  static double nextUpPanelExtentOf(WidgetLayout l) =>
      nextUpPanelOccupied ? 64.0 : 0.0;
  static double innerPlayerHeightOf(WidgetLayout l) =>
      corePlayerHeightOf(l) +
      spectrumPanelExtentOf(l) +
      lyricsPanelExtentOf(l) +
      nextUpPanelExtentOf(l);
  static double unscaledBaseWindowWidthOf(WidgetLayout l) =>
      innerPlayerWidthOf(l) + cardMargin * 2;
  static double unscaledBaseWindowHeightOf(WidgetLayout l) =>
      innerPlayerHeightOf(l) + cardMargin * 2;
  static double baseWindowWidthOf(WidgetLayout l) =>
      unscaledBaseWindowWidthOf(l);
  static double baseWindowHeightOf(WidgetLayout l) =>
      unscaledBaseWindowHeightOf(l);
  static const double innerSettingsPanelHeight = 460.0;
  static const double innerSettingsSideWidth = 360.0;
  static double expandedWindowWidthOf(WidgetLayout l) =>
      unscaledExpandedWindowWidthOf(l);
  static double expandedWindowHeightOf(WidgetLayout l) =>
      unscaledExpandedWindowHeightOf(l);
  static double unscaledExpandedWindowWidthOf(WidgetLayout l) =>
      l == WidgetLayout.vertical
      ? innerPlayerWidthOf(l) + innerSettingsSideWidth + cardMargin * 2
      : unscaledBaseWindowWidthOf(l);
  static double unscaledExpandedWindowHeightOf(WidgetLayout l) =>
      l == WidgetLayout.vertical
      ? unscaledBaseWindowHeightOf(l)
      : innerPlayerHeightOf(l) + innerSettingsPanelHeight + cardMargin * 2;
  static double windowBaseWidthOf(WidgetLayout l) =>
      baseWindowWidthOf(l) * componentScale;
  static double windowBaseHeightOf(WidgetLayout l) =>
      baseWindowHeightOf(l) * componentScale;
  static double windowExpandedWidthOf(WidgetLayout l) =>
      expandedWindowWidthOf(l) * componentScale;
  static double windowExpandedHeightOf(WidgetLayout l) =>
      expandedWindowHeightOf(l) * componentScale;
  static double get playerWidth => windowBaseWidthOf(widgetLayout);
  static double get baseWindowWidth => windowBaseWidthOf(widgetLayout);
  static double get baseWindowHeight => windowBaseHeightOf(widgetLayout);
  static double get expandedWindowWidth => windowExpandedWidthOf(widgetLayout);
  static double get expandedWindowHeight =>
      windowExpandedHeightOf(widgetLayout);
  static double get settingsWindowWidth => expandedWindowWidthOf(widgetLayout);
  static const double settingsPanelHeight = innerSettingsPanelHeight;
  static const double settingsSideWidth = innerSettingsSideWidth;

  
  
  static double playerWidthOf(WidgetLayout l) => baseWindowWidthOf(l);
  static double playerAreaHeightOf(WidgetLayout l) => innerPlayerHeightOf(l);
  static double settingsWindowWidthOf(WidgetLayout l) =>
      expandedWindowWidthOf(l);
  
  
  static const double canvasWidth = 700.0;
  static const double canvasHeight = 800.0;
  static double get menuWindowWidth =>
      baseWindowWidth + _menuExtraSpace * componentScale;
  static double get menuExtraSpace => _menuExtraSpace * componentScale;
  static double get unscaledMenuExtraSpace => _menuExtraSpace;
  static double glowHeaderHeightOf(WidgetLayout l) =>
      l == WidgetLayout.vertical ? 360.0 : corePlayerHeightOf(l);
  static double get glowHeaderHeight => glowHeaderHeightOf(widgetLayout);
  static Offset revealCenterOf(WidgetLayout l) => l == WidgetLayout.vertical
      ? const Offset(170, 170)
      : const Offset(80, 80);
  static Offset get revealCenter => revealCenterOf(widgetLayout);
  static const Duration layoutSwitchDuration = Duration(milliseconds: 420);
  static const Curve layoutSwitchCurve = Curves.easeInOutCubicEmphasized;

  static BorderRadius getShapeRadius(MD3Shape shape, double height) {
    switch (shape) {
      case MD3Shape.circle:
        return BorderRadius.circular(height / 2);
      case MD3Shape.stadium:
        return BorderRadius.circular(999);
      case MD3Shape.roundedExtraSmall:
        return BorderRadius.circular(4);
      case MD3Shape.roundedSmall:
        return BorderRadius.circular(8);
      case MD3Shape.roundedMedium:
        return BorderRadius.circular(12);
      case MD3Shape.roundedLarge:
        return BorderRadius.circular(20);
      case MD3Shape.roundedExtraLarge:
        return BorderRadius.circular(28);
    }
  }

  static bool _exitInProgress = false;

  static Future<void> stopFetcherProcess() async {
    final stopOwned = externalMediaStopper;
    fetcherPid = 0;
    if (stopOwned != null) {
      try {
        await stopOwned();
      } catch (_) {}
    }
  }

  static Future<void> exitApp() async {
    finishArtworkToneTransition();
    if (_exitInProgress) return;
    _exitInProgress = true;
    try {
      await flushSettings().timeout(const Duration(milliseconds: 700));
      await Future.wait([
        lyricsCacheStore.flush(),
        backgroundCacheStore.flush(),
      ]).timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await SystemPerformanceProvider.shutdown();
      final backend = _mediaBackend;
      if (backend != null) await releaseMediaBackend(backend);
      await stopFetcherProcess();
    } catch (_) {}
    exit(0);
  }

  static Future<void> sendCommand(MediaCommand command) async {
    trackNavigation.observe(currentPlatformTrack);
    final navigationIntent = trackNavigation.noteCommand(command);
    try {
      if (mediaCommandSender?.call(command) == true) return;
      if (!await mediaBackend.dispatchCommand(command)) {
        trackNavigation.cancelCommand(navigationIntent);
      }
    } catch (_) {
      trackNavigation.cancelCommand(navigationIntent);
    }
  }

  static Future<void> loadSystemFonts({bool invalidateMetrics = false}) =>
      _AppSettings.loadSystemFonts(invalidateMetrics: invalidateMetrics);
  static Future<bool> importCustomFont({bool forLyrics = false}) =>
      _AppSettings.importCustomFont(forLyrics: forLyrics);
  static Future<void> loadSettings() => _AppSettings.loadSettings();
  static Future<void> saveSettings() => _AppSettings.saveSettings();
  static Future<void> flushSettings() => _AppSettings.flushSettings();
}
