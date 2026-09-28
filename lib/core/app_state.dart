import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

import 'media_provider.dart';
import 'lyrics_coordinator.dart';
import 'local_lrc_lyrics_provider.dart';
import 'lrclib_lyrics_provider.dart';
import 'qq_music_lyrics_provider.dart';
import 'platform_provider.dart';
import 'local_playlist_queue_provider.dart';
import 'qq_music_playlist_queue_provider.dart';
import 'queue_coordinator.dart';



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

enum LyricsProviderChoice { lrclib, localLrc, qqMusic }

enum LyricsTransitionStyle { fade, rise, descend, sideways, zoom, none }

enum MD3ProgressStyle { linear, pill, segmented }

enum WidgetLayout { horizontal, vertical }

enum ComponentSizeMode { small, standard, large, custom }

class AppState {
  static Process? csharpEngine;
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
  static bool showNextUp = false;
  static int nextUpLeadSeconds = 20;
  static bool? isShuffleActive;
  static String autoRepeatMode = '';
  static PlatformTrack? currentPlatformTrack;
  static final LrclibLyricsProvider _lrclibLyrics = LrclibLyricsProvider();
  static final QqMusicPlaylistQueueProvider _qqPlaylist =
      QqMusicPlaylistQueueProvider(playlistInput: () => qqPlaylistLink);
  static final PlatformProviderRegistry platformProviders =
      PlatformProviderRegistry()
        ..register(_lrclibLyrics)
        ..register(LocalLrcLyricsProvider(() => localLyricsDirectory))
        ..register(QqMusicLyricsProvider(fallback: _lrclibLyrics))
        ..register(_qqPlaylist)
        ..register(LocalPlaylistQueueProvider(() => playlistFilePath));
  static final LyricsCoordinator lyrics = LyricsCoordinator(platformProviders);
  static final QueueCoordinator queue = QueueCoordinator(platformProviders);

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
    if (force) _qqPlaylist.invalidate();
    unawaited(
      queue.setTrack(
        showNextUp ? currentPlatformTrack : null,
        enabled: showNextUp,
        force: force,
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
    return remaining > 0 && remaining <= windowMs;
  }

  static void setLocalLyricsDirectory(String path) {
    localLyricsDirectory = path;
    platformProviders.register(
      LocalLrcLyricsProvider(() => localLyricsDirectory),
    );
    refreshLyrics();
  }

  static bool Function(MediaCommand command)? mediaCommandSender;
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
  static final ValueNotifier<bool> backgroundCacheHit = ValueNotifier<bool>(
    false,
  );
  static String currentRawBase64 = "";

  
  
  
  static final ValueNotifier<int> backgroundRevision = ValueNotifier<int>(0);
  static void notifyBackgroundChanged() => backgroundRevision.value++;
  static final ValueNotifier<int> playbackRevision = ValueNotifier<int>(0);
  static final ValueNotifier<bool> nextUpPreviewVisible = ValueNotifier<bool>(
    false,
  );
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
  static SpectrumMode spectrumMode = SpectrumMode.off;
  static bool showLyrics = false;
  static const String defaultFontFamily = 'System Default';
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
  static MD3Shape settingsNavigationShape = MD3Shape.roundedLarge;
  static bool enableProgressAutoContrast = true;
  static bool enableOledTheme = false;
  static bool enable3DCover = true;
  static bool showPlaybackControls = true;
  static bool showPerformanceMonitor = false;
  static DynamicSchemeVariant themeVariant = DynamicSchemeVariant.tonalSpot;

  
  static String currentFontFamily = defaultFontFamily;
  static List<String> loadedSystemFonts = ['System Default'];
  static List<String> customFontPaths = [];

  
  
  
  static const List<String> textFontFallback = [
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
  static List<FontVariation> variationsFor(double value) => [
    FontVariation('wght', value.clamp(100.0, 900.0)),
  ];
  static FontWeight get titleWeight => weightFor(titleWeightValue);
  static FontWeight get artistWeight => weightFor(artistWeightValue);
  static FontWeight get lyricsWeight => weightFor(lyricsWeightValue);
  static double _safeWeight(double value, double fallback) =>
      value.isFinite ? value.clamp(100.0, 900.0) : fallback;
  static String? get effectiveLyricsFontFamily {
    final family = lyricsUseThemeFont ? currentFontFamily : lyricsFontFamily;
    if (family != 'System Default') return family;
    return lyricsUseThemeFont ? null : 'Segoe UI Variable Text';
  }

  static TextStyle lyricsTextStyle(Color color) => TextStyle(
    color: color,
    fontSize: lyricsFontSize,
    fontWeight: lyricsWeight,
    fontVariations: variationsFor(lyricsWeightValue),
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
  static const double minimumComponentScale = 0.72;
  static const double maximumComponentScale = 1.50;

  static double scaleForSizeMode(ComponentSizeMode mode) => switch (mode) {
    ComponentSizeMode.small => 0.82,
    ComponentSizeMode.standard => 1.0,
    ComponentSizeMode.large => 1.22,
    ComponentSizeMode.custom => customComponentScale.clamp(
      minimumComponentScale,
      maximumComponentScale,
    ),
  };

  static double get componentScale => scaleForSizeMode(componentSizeMode);
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
      spectrumMode == SpectrumMode.off && !showPerformanceMonitor ? 0.0 : 64.0;
  static double lyricsPanelExtentOf(WidgetLayout l) => showLyrics ? 64.0 : 0.0;
  static double nextUpPanelExtentOf(WidgetLayout l) =>
      showNextUp &&
          nextUpPreviewVisible.value &&
          (playlistFilePath.isNotEmpty || qqPlaylistLink.isNotEmpty)
      ? 64.0
      : 0.0;
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
    final Process? ownedProcess = csharpEngine;
    final int ownedPid = fetcherPid > 0 ? fetcherPid : (ownedProcess?.pid ?? 0);
    csharpEngine = null;
    fetcherPid = 0;

    try {
      ownedProcess?.kill();
      if (Platform.isWindows && ownedPid > 0) {
        await Process.run('taskkill', [
          '/F',
          '/T',
          '/PID',
          '$ownedPid',
        ]).timeout(const Duration(milliseconds: 900));
      }
    } catch (_) {}
  }

  static Future<void> exitApp() async {
    if (_exitInProgress) return;
    _exitInProgress = true;
    try {
      await flushSettings().timeout(const Duration(milliseconds: 700));
    } catch (_) {}
    try {
      _commandClient.close(force: true);
      await stopFetcherProcess();
    } catch (_) {}
    exit(0);
  }

  static final HttpClient _commandClient = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 350)
    ..idleTimeout = const Duration(seconds: 2)
    ..maxConnectionsPerHost = 2;

  static Future<void> sendCommand(MediaCommand command) async {
    if (mediaCommandSender?.call(command) == true) return;
    HttpClientRequest? request;
    try {
      request = await _commandClient
          .getUrl(
            Uri.http('localhost:12580', '/command', <String, String>{
              'cmd': command.httpValue,
            }),
          )
          .timeout(const Duration(milliseconds: 350));
      request.persistentConnection = false;
      final response = await request.close().timeout(
        const Duration(milliseconds: 500),
      );
      await response.drain<void>().timeout(const Duration(milliseconds: 500));
    } catch (_) {
      request?.abort();
    }
  }

  static SharedPreferences? _prefs;
  static const String _settingsSnapshotKey = 'settingsSnapshotV2';
  static Timer? _settingsSaveDebounce;
  static String? _pendingSettingsSnapshot;
  static Future<void> _settingsWriteTail = Future<void>.value();

  static T _enumFromIndex<T>(List<T> values, int? index, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  static T _enumFromName<T extends Enum>(
    List<T> values,
    Object? name,
    T fallback,
  ) {
    if (name is! String) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static Future<void> loadSystemFonts() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('reg', [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        ]);
        final lines = result.stdout.toString().split('\n');
        bool changed = false;
        for (var line in lines) {
          if (line.contains('REG_SZ')) {
            var name = line.split('REG_SZ')[0].trim();
            name = name.replaceAll(RegExp(r'\s*\(.*\)$'), '');
            if (name.isNotEmpty && !loadedSystemFonts.contains(name)) {
              loadedSystemFonts.add(name);
              changed = true;
            }
          }
        }
        if (changed) fontsRevision.value++;
      } catch (_) {}
    }
  }

  static Future<bool> importCustomFont({bool forLyrics = false}) async {
    try {
      
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
        dialogTitle: '选择字体文件',
      );

      if (result != null && result.files.single.path != null) {
        String path = result.files.single.path!;
        String fontName = result.files.single.name.split('.').first;

        var fontFile = File(path);
        if (!fontFile.existsSync()) return false;

        var bytes = await fontFile.readAsBytes();
        var fontLoader = FontLoader(fontName);
        fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
        await fontLoader.load();

        if (!loadedSystemFonts.contains(fontName)) {
          loadedSystemFonts.insert(1, fontName);
          fontsRevision.value++;
        }
        if (!customFontPaths.contains(path)) {
          customFontPaths.add(path);
          await saveSettings();
        }
        if (forLyrics) {
          lyricsFontFamily = fontName;
        } else {
          currentFontFamily = fontName;
        }
        return true;
      }
    } catch (e) {
      debugPrint("加载自定义字体失败: $e");
    }
    return false;
  }

  static Future<void> _restoreCustomFonts() async {
    for (String path in customFontPaths) {
      try {
        var file = File(path);
        if (file.existsSync()) {
          String fontName = file.uri.pathSegments.last.split('.').first;
          var bytes = await file.readAsBytes();
          var fontLoader = FontLoader(fontName);
          fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
          await fontLoader.load();
          if (!loadedSystemFonts.contains(fontName)) {
            loadedSystemFonts.insert(1, fontName);
            fontsRevision.value++;
          }
        }
      } catch (_) {}
    }
  }

  static Future<void> loadSettings() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final p = _prefs!;

      Map<String, dynamic>? snapshot;
      final String? rawSnapshot = p.getString(_settingsSnapshotKey);
      if (rawSnapshot != null) {
        try {
          final decoded = jsonDecode(rawSnapshot);
          if (decoded is Map) snapshot = Map<String, dynamic>.from(decoded);
        } catch (_) {
          snapshot = null;
        }
      }

      customFontPaths = snapshot?['customFontPaths'] is List
          ? (snapshot!['customFontPaths'] as List).whereType<String>().toList(
              growable: true,
            )
          : p.getStringList('customFontPaths') ?? [];

      final bool themeIsDark = snapshot?['themeIsDark'] is bool
          ? snapshot!['themeIsDark'] as bool
          : p.getBool('themeIsDark') ?? true;
      themeBrightness = themeIsDark ? Brightness.dark : Brightness.light;
      if (snapshot != null) {
        themeVariant = _enumFromName(
          DynamicSchemeVariant.values,
          snapshot['themeVariant'],
          DynamicSchemeVariant.tonalSpot,
        );
        enableGlow = snapshot['enableGlow'] is bool
            ? snapshot['enableGlow'] as bool
            : true;
        glowMode = _enumFromName(
          GlowMode.values,
          snapshot['glowMode'],
          GlowMode.waterfall,
        );
        spectrumMode = _enumFromName(
          SpectrumMode.values,
          snapshot['spectrumMode'],
          SpectrumMode.off,
        );
        showLyrics = snapshot['showLyrics'] == true;
        lyricsUseThemeFont = snapshot['lyricsUseThemeFont'] is bool
            ? snapshot['lyricsUseThemeFont'] as bool
            : true;
        lyricsFontFamily = snapshot['lyricsFontFamily'] is String
            ? snapshot['lyricsFontFamily'] as String
            : 'System Default';
        lyricsWeightValue = snapshot['lyricsWeightValue'] is num
            ? (snapshot['lyricsWeightValue'] as num).toDouble()
            : 500.0;
        lyricsFontSize = snapshot['lyricsFontSize'] is num
            ? (snapshot['lyricsFontSize'] as num).toDouble()
            : 14.0;
        lyricsProviderChoice = _enumFromName(
          LyricsProviderChoice.values,
          snapshot['lyricsProviderChoice'],
          LyricsProviderChoice.lrclib,
        );
        lyricsTransitionStyle = _enumFromName(
          LyricsTransitionStyle.values,
          snapshot['lyricsTransitionStyle'],
          LyricsTransitionStyle.fade,
        );
        lyricsAnimationsLinked = snapshot['lyricsAnimationsLinked'] is bool
            ? snapshot['lyricsAnimationsLinked'] as bool
            : true;
        lyricsExitTransitionStyle = _enumFromName(
          LyricsTransitionStyle.values,
          snapshot['lyricsExitTransitionStyle'],
          lyricsTransitionStyle,
        );
        localLyricsDirectory = snapshot['localLyricsDirectory'] is String
            ? snapshot['localLyricsDirectory'] as String
            : '';
        progressStyle = _enumFromName(
          MD3ProgressStyle.values,
          snapshot['progressStyle'],
          MD3ProgressStyle.linear,
        );
        settingsNavigationShape = _enumFromName(
          MD3Shape.values,
          snapshot['settingsNavigationShape'],
          MD3Shape.roundedLarge,
        );
        enableProgressAutoContrast =
            snapshot['enableProgressAutoContrast'] is bool
            ? snapshot['enableProgressAutoContrast'] as bool
            : true;
        enableOledTheme = snapshot['enableOledTheme'] is bool
            ? snapshot['enableOledTheme'] as bool
            : false;
        showPlaybackControls = snapshot['showPlaybackControls'] is bool
            ? snapshot['showPlaybackControls'] as bool
            : true;
        showPerformanceMonitor = snapshot['showPerformanceMonitor'] == true;
        selectedSourceAppId = snapshot['selectedSourceAppId'] is String
            ? snapshot['selectedSourceAppId'] as String
            : '';
        playlistFilePath = snapshot['playlistFilePath'] is String
            ? snapshot['playlistFilePath'] as String
            : '';
        qqPlaylistLink = snapshot['qqPlaylistLink'] is String
            ? snapshot['qqPlaylistLink'] as String
            : '';
        showNextUp = snapshot['showNextUp'] == true;
        nextUpLeadSeconds = switch (snapshot['nextUpLeadSeconds']) {
          10 || 20 || 30 || 45 => snapshot['nextUpLeadSeconds'] as int,
          _ => 20,
        };
        enable3DCover = snapshot['enable3DCover'] is bool
            ? snapshot['enable3DCover'] as bool
            : true;
        currentFontFamily = snapshot['currentFontFamily'] is String
            ? snapshot['currentFontFamily'] as String
            : 'System Default';
        titleWeightValue = snapshot['titleWeightValue'] is num
            ? (snapshot['titleWeightValue'] as num).toDouble()
            : ((snapshot['titleWeightIndex'] is int
                          ? snapshot['titleWeightIndex'] as int
                          : 6) +
                      1) *
                  100.0;
        artistWeightValue = snapshot['artistWeightValue'] is num
            ? (snapshot['artistWeightValue'] as num).toDouble()
            : ((snapshot['artistWeightIndex'] is int
                          ? snapshot['artistWeightIndex'] as int
                          : 3) +
                      1) *
                  100.0;
        prevButtonShape = _enumFromName(
          MD3Shape.values,
          snapshot['prevButtonShape'],
          MD3Shape.circle,
        );
        playButtonShape = _enumFromName(
          MD3Shape.values,
          snapshot['playButtonShape'],
          MD3Shape.circle,
        );
        nextButtonShape = _enumFromName(
          MD3Shape.values,
          snapshot['nextButtonShape'],
          MD3Shape.circle,
        );
        widgetLayout = _enumFromName(
          WidgetLayout.values,
          snapshot['widgetLayout'],
          WidgetLayout.horizontal,
        );
        componentSizeMode = _enumFromName(
          ComponentSizeMode.values,
          snapshot['componentSizeMode'],
          ComponentSizeMode.standard,
        );
        customComponentScale = snapshot['customComponentScale'] is num
            ? (snapshot['customComponentScale'] as num).toDouble()
            : 1.0;
        isAlwaysOnTop = snapshot['isAlwaysOnTop'] is bool
            ? snapshot['isAlwaysOnTop'] as bool
            : true;
        isMousePassthrough = snapshot['isMousePassthrough'] is bool
            ? snapshot['isMousePassthrough'] as bool
            : false;
      } else {
        _loadLegacySettings(p);
      }

      titleWeightValue = _safeWeight(titleWeightValue, 700.0);
      artistWeightValue = _safeWeight(artistWeightValue, 400.0);
      lyricsWeightValue = _safeWeight(lyricsWeightValue, 500.0);
      lyricsFontSize = lyricsFontSize.isFinite
          ? lyricsFontSize.clamp(12.0, 17.0)
          : 14.0;
      customComponentScale = customComponentScale.clamp(
        minimumComponentScale,
        maximumComponentScale,
      );
      isMousePassthrough = false;
      refreshQueue(force: true);
      await _restoreCustomFonts();
    } catch (_) {}
  }

  static void _loadLegacySettings(SharedPreferences p) {
    themeVariant = _enumFromIndex(
      DynamicSchemeVariant.values,
      p.getInt('themeVariant'),
      DynamicSchemeVariant.tonalSpot,
    );
    enableGlow = p.getBool('enableGlow') ?? true;
    glowMode = _enumFromIndex(
      GlowMode.values,
      p.getInt('glowMode'),
      GlowMode.waterfall,
    );
    spectrumMode = _enumFromIndex(
      SpectrumMode.values,
      p.getInt('spectrumMode'),
      SpectrumMode.off,
    );
    showLyrics = p.getBool('showLyrics') ?? false;
    lyricsUseThemeFont = p.getBool('lyricsUseThemeFont') ?? true;
    lyricsFontFamily = p.getString('lyricsFontFamily') ?? 'System Default';
    lyricsWeightValue = p.getDouble('lyricsWeightValue') ?? 500.0;
    lyricsFontSize = p.getDouble('lyricsFontSize') ?? 14.0;
    lyricsProviderChoice = _enumFromIndex(
      LyricsProviderChoice.values,
      p.getInt('lyricsProviderChoice'),
      LyricsProviderChoice.lrclib,
    );
    lyricsTransitionStyle = _enumFromIndex(
      LyricsTransitionStyle.values,
      p.getInt('lyricsTransitionStyle'),
      LyricsTransitionStyle.fade,
    );
    lyricsAnimationsLinked = p.getBool('lyricsAnimationsLinked') ?? true;
    lyricsExitTransitionStyle = _enumFromIndex(
      LyricsTransitionStyle.values,
      p.getInt('lyricsExitTransitionStyle'),
      lyricsTransitionStyle,
    );
    localLyricsDirectory = p.getString('localLyricsDirectory') ?? '';
    progressStyle = _enumFromIndex(
      MD3ProgressStyle.values,
      p.getInt('progressStyle'),
      MD3ProgressStyle.linear,
    );
    settingsNavigationShape = _enumFromIndex(
      MD3Shape.values,
      p.getInt('settingsNavigationShape'),
      MD3Shape.roundedLarge,
    );
    enableProgressAutoContrast =
        p.getBool('enableProgressAutoContrast') ?? true;
    enableOledTheme = p.getBool('enableOledTheme') ?? false;
    enable3DCover = p.getBool('enable3DCover') ?? true;
    showPlaybackControls = p.getBool('showPlaybackControls') ?? true;
    showPerformanceMonitor = p.getBool('showPerformanceMonitor') ?? false;
    selectedSourceAppId = p.getString('selectedSourceAppId') ?? '';
    playlistFilePath = p.getString('playlistFilePath') ?? '';
    qqPlaylistLink = p.getString('qqPlaylistLink') ?? '';
    showNextUp = p.getBool('showNextUp') ?? false;
    nextUpLeadSeconds = switch (p.getInt('nextUpLeadSeconds')) {
      10 || 20 || 30 || 45 => p.getInt('nextUpLeadSeconds')!,
      _ => 20,
    };

    currentFontFamily = p.getString('currentFontFamily') ?? 'System Default';
    titleWeightValue =
        p.getDouble('titleWeightValue') ??
        ((p.getInt('titleWeightIndex') ?? 6) + 1) * 100.0;
    artistWeightValue =
        p.getDouble('artistWeightValue') ??
        ((p.getInt('artistWeightIndex') ?? 3) + 1) * 100.0;

    prevButtonShape = _enumFromIndex(
      MD3Shape.values,
      p.getInt('prevButtonShape'),
      MD3Shape.circle,
    );
    playButtonShape = _enumFromIndex(
      MD3Shape.values,
      p.getInt('playButtonShape'),
      MD3Shape.circle,
    );
    nextButtonShape = _enumFromIndex(
      MD3Shape.values,
      p.getInt('nextButtonShape'),
      MD3Shape.circle,
    );
    widgetLayout = _enumFromIndex(
      WidgetLayout.values,
      p.getInt('widgetLayout'),
      WidgetLayout.horizontal,
    );
    componentSizeMode = _enumFromIndex(
      ComponentSizeMode.values,
      p.getInt('componentSizeMode'),
      ComponentSizeMode.standard,
    );
    customComponentScale =
        p
            .getDouble('customComponentScale')
            ?.clamp(minimumComponentScale, maximumComponentScale) ??
        1.0;
    isAlwaysOnTop = p.getBool('isAlwaysOnTop') ?? true;
    isMousePassthrough = p.getBool('isMousePassthrough') ?? false;
  }

  static Map<String, Object> _captureSettingsSnapshot() => <String, Object>{
    'customFontPaths': List<String>.from(customFontPaths),
    'themeIsDark': themeBrightness == Brightness.dark,
    'themeVariant': themeVariant.name,
    'enableGlow': enableGlow,
    'glowMode': glowMode.name,
    'spectrumMode': spectrumMode.name,
    'showLyrics': showLyrics,
    'lyricsUseThemeFont': lyricsUseThemeFont,
    'lyricsFontFamily': lyricsFontFamily,
    'lyricsWeightValue': lyricsWeightValue,
    'lyricsFontSize': lyricsFontSize,
    'lyricsProviderChoice': lyricsProviderChoice.name,
    'lyricsTransitionStyle': lyricsTransitionStyle.name,
    'lyricsAnimationsLinked': lyricsAnimationsLinked,
    'lyricsExitTransitionStyle': lyricsExitTransitionStyle.name,
    'localLyricsDirectory': localLyricsDirectory,
    'progressStyle': progressStyle.name,
    'settingsNavigationShape': settingsNavigationShape.name,
    'enableProgressAutoContrast': enableProgressAutoContrast,
    'enableOledTheme': enableOledTheme,
    'enable3DCover': enable3DCover,
    'showPlaybackControls': showPlaybackControls,
    'showPerformanceMonitor': showPerformanceMonitor,
    'selectedSourceAppId': selectedSourceAppId,
    'playlistFilePath': playlistFilePath,
    'qqPlaylistLink': qqPlaylistLink,
    'showNextUp': showNextUp,
    'nextUpLeadSeconds': nextUpLeadSeconds,
    'currentFontFamily': currentFontFamily,
    'titleWeightValue': titleWeightValue,
    'artistWeightValue': artistWeightValue,
    'prevButtonShape': prevButtonShape.name,
    'playButtonShape': playButtonShape.name,
    'nextButtonShape': nextButtonShape.name,
    'widgetLayout': widgetLayout.name,
    'componentSizeMode': componentSizeMode.name,
    'customComponentScale': customComponentScale,
    'isAlwaysOnTop': isAlwaysOnTop,
    'isMousePassthrough': isMousePassthrough,
  };

  static Future<void> _persistPendingSettings() {
    final p = _prefs;
    final snapshot = _pendingSettingsSnapshot;
    if (p == null || snapshot == null) return Future<void>.value();
    _pendingSettingsSnapshot = null;
    _settingsWriteTail = _settingsWriteTail
        .then((_) async {
          await p.setString(_settingsSnapshotKey, snapshot);
        })
        .catchError((_) {});
    return _settingsWriteTail;
  }

  static Future<void> saveSettings() async {
    if (_prefs == null) return;
    _pendingSettingsSnapshot = jsonEncode(_captureSettingsSnapshot());
    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = Timer(const Duration(milliseconds: 350), () {
      _settingsSaveDebounce = null;
      unawaited(_persistPendingSettings());
    });
  }

  static Future<void> flushSettings() async {
    _settingsSaveDebounce?.cancel();
    _settingsSaveDebounce = null;
    await _persistPendingSettings();
    await _settingsWriteTail;
  }
}
