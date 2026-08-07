import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';



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

enum MD3ProgressStyle { linear, pill, segmented }

enum WidgetLayout { horizontal, vertical }

class AppState {
  static Process? csharpEngine;
  static int fetcherPid = 0;
  static String trackTitle = "未在播放";
  static String artistName = "无媒体会话";
  static String trackVersion = "";
  static bool isPlaying = false;
  static double playbackPositionMs = 0.0;
  static double playbackDurationMs = 0.0;
  static int playbackUpdatedAtMs = 0;
  static const int spectrumBandCount = 32;
  static final Float32List spectrumLevels = Float32List(spectrumBandCount);
  static int spectrumUpdatedAtMs = 0;

  static ImageProvider? coverProvider;
  static ImageProvider? bgBlurProvider;
  static String currentCoverVersion = "";
  static String currentRawBase64 = "";

  
  
  
  static final ValueNotifier<int> backgroundRevision = ValueNotifier<int>(0);
  static void notifyBackgroundChanged() => backgroundRevision.value++;
  static final ValueNotifier<int> playbackRevision = ValueNotifier<int>(0);
  static final ValueNotifier<int> trackTransitionRevision = ValueNotifier<int>(
    0,
  );
  static final ValueNotifier<int> spectrumRevision = ValueNotifier<int>(0);
  static final ValueNotifier<int> fontsRevision = ValueNotifier<int>(0);

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
        DateTime.now().millisecondsSinceEpoch - playbackUpdatedAtMs;
    final double estimated = playbackPositionMs + (elapsedMs.clamp(0, 60000));
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
  static MD3ProgressStyle progressStyle = MD3ProgressStyle.linear;
  static bool enableProgressAutoContrast = true;
  static bool enableOledTheme = false;
  static bool enable3DCover = true;
  static DynamicSchemeVariant themeVariant = DynamicSchemeVariant.tonalSpot;

  
  static String currentFontFamily = 'System Default';
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

  static int titleWeightIndex = 6;
  static int artistWeightIndex = 3;

  static FontWeight get titleWeight => FontWeight.values[titleWeightIndex];
  static FontWeight get artistWeight => FontWeight.values[artistWeightIndex];

  static MD3Shape prevButtonShape = MD3Shape.circle;
  static MD3Shape playButtonShape = MD3Shape.circle;
  static MD3Shape nextButtonShape = MD3Shape.circle;

  static WidgetLayout widgetLayout = WidgetLayout.horizontal;
  static bool get isVertical => widgetLayout == WidgetLayout.vertical;

  static const double _menuExtraSpace = 200.0;
  static const double cardMargin = 0.0;
  static double innerPlayerWidthOf(WidgetLayout l) =>
      l == WidgetLayout.vertical ? 340.0 : 480.0;
  static double corePlayerHeightOf(WidgetLayout l) =>
      l == WidgetLayout.vertical ? 520.0 : 176.0;
  static double spectrumPanelExtentOf(WidgetLayout l) =>
      spectrumMode == SpectrumMode.off ? 0.0 : 64.0;
  static double innerPlayerHeightOf(WidgetLayout l) =>
      corePlayerHeightOf(l) + spectrumPanelExtentOf(l);
  static double baseWindowWidthOf(WidgetLayout l) =>
      innerPlayerWidthOf(l) + cardMargin * 2;
  static double baseWindowHeightOf(WidgetLayout l) =>
      innerPlayerHeightOf(l) + cardMargin * 2;
  static const double innerSettingsPanelHeight = 460.0;
  static const double innerSettingsSideWidth = 360.0;
  static double expandedWindowWidthOf(WidgetLayout l) =>
      l == WidgetLayout.vertical
      ? innerPlayerWidthOf(l) + innerSettingsSideWidth + cardMargin * 2
      : baseWindowWidthOf(l);
  static double expandedWindowHeightOf(WidgetLayout l) =>
      l == WidgetLayout.vertical
      ? baseWindowHeightOf(l)
      : innerPlayerHeightOf(l) + innerSettingsPanelHeight + cardMargin * 2;
  static double get playerWidth => baseWindowWidthOf(widgetLayout);
  static double get baseWindowWidth => baseWindowWidthOf(widgetLayout);
  static double get baseWindowHeight => baseWindowHeightOf(widgetLayout);
  static double get expandedWindowWidth => expandedWindowWidthOf(widgetLayout);
  static double get expandedWindowHeight =>
      expandedWindowHeightOf(widgetLayout);
  static double get settingsWindowWidth => expandedWindowWidthOf(widgetLayout);
  static const double settingsPanelHeight = innerSettingsPanelHeight;
  static const double settingsSideWidth = innerSettingsSideWidth;

  
  
  static double playerWidthOf(WidgetLayout l) => baseWindowWidthOf(l);
  static double playerAreaHeightOf(WidgetLayout l) => innerPlayerHeightOf(l);
  static double settingsWindowWidthOf(WidgetLayout l) =>
      expandedWindowWidthOf(l);
  
  
  static const double canvasWidth = 700.0;
  static const double canvasHeight = 700.0;
  static double get menuWindowWidth => baseWindowWidth + _menuExtraSpace;
  static double get menuExtraSpace => _menuExtraSpace;
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

  static Future<void> sendCommand(String command) async {
    HttpClientRequest? request;
    try {
      request = await _commandClient
          .getUrl(
            Uri.http('localhost:12580', '/command', <String, String>{
              'cmd': command,
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

  static Future<bool> importCustomFont() async {
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
        currentFontFamily = fontName;
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
        progressStyle = _enumFromName(
          MD3ProgressStyle.values,
          snapshot['progressStyle'],
          MD3ProgressStyle.linear,
        );
        enableProgressAutoContrast =
            snapshot['enableProgressAutoContrast'] is bool
            ? snapshot['enableProgressAutoContrast'] as bool
            : true;
        enableOledTheme = snapshot['enableOledTheme'] is bool
            ? snapshot['enableOledTheme'] as bool
            : false;
        enable3DCover = snapshot['enable3DCover'] is bool
            ? snapshot['enable3DCover'] as bool
            : true;
        currentFontFamily = snapshot['currentFontFamily'] is String
            ? snapshot['currentFontFamily'] as String
            : 'System Default';
        titleWeightIndex = snapshot['titleWeightIndex'] is int
            ? snapshot['titleWeightIndex'] as int
            : 6;
        artistWeightIndex = snapshot['artistWeightIndex'] is int
            ? snapshot['artistWeightIndex'] as int
            : 3;
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
        isAlwaysOnTop = snapshot['isAlwaysOnTop'] is bool
            ? snapshot['isAlwaysOnTop'] as bool
            : true;
        isMousePassthrough = snapshot['isMousePassthrough'] is bool
            ? snapshot['isMousePassthrough'] as bool
            : false;
      } else {
        _loadLegacySettings(p);
      }

      titleWeightIndex = titleWeightIndex.clamp(0, 8);
      artistWeightIndex = artistWeightIndex.clamp(0, 8);
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
    progressStyle = _enumFromIndex(
      MD3ProgressStyle.values,
      p.getInt('progressStyle'),
      MD3ProgressStyle.linear,
    );
    enableProgressAutoContrast =
        p.getBool('enableProgressAutoContrast') ?? true;
    enableOledTheme = p.getBool('enableOledTheme') ?? false;
    enable3DCover = p.getBool('enable3DCover') ?? true;

    currentFontFamily = p.getString('currentFontFamily') ?? 'System Default';
    titleWeightIndex = p.getInt('titleWeightIndex') ?? 6;
    artistWeightIndex = p.getInt('artistWeightIndex') ?? 3;

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
    'progressStyle': progressStyle.name,
    'enableProgressAutoContrast': enableProgressAutoContrast,
    'enableOledTheme': enableOledTheme,
    'enable3DCover': enable3DCover,
    'currentFontFamily': currentFontFamily,
    'titleWeightIndex': titleWeightIndex,
    'artistWeightIndex': artistWeightIndex,
    'prevButtonShape': prevButtonShape.name,
    'playButtonShape': playButtonShape.name,
    'nextButtonShape': nextButtonShape.name,
    'widgetLayout': widgetLayout.name,
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
