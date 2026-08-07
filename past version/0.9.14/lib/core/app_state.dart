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

  static void exitApp() {
    try {
      _commandClient.close(force: true);
      csharpEngine?.kill();
      if (Platform.isWindows) {
        Process.start('taskkill', ['/F', '/T', '/IM', 'MusicFetcher.exe']);
      }
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
  static T _enumFromIndex<T>(List<T> values, int? index, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  static Future<void> loadSystemFonts() async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('reg', [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        ]);
        final lines = result.stdout.toString().split('\n');
        for (var line in lines) {
          if (line.contains('REG_SZ')) {
            var name = line.split('REG_SZ')[0].trim();
            name = name.replaceAll(RegExp(r'\s*\(.*\)$'), '');
            if (name.isNotEmpty && !loadedSystemFonts.contains(name)) {
              loadedSystemFonts.add(name);
            }
          }
        }
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
          }
        }
      } catch (_) {}
    }
  }

  static Future<void> loadSettings() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final p = _prefs!;

      customFontPaths = p.getStringList('customFontPaths') ?? [];

      await Future.wait([loadSystemFonts(), _restoreCustomFonts()]);

      themeBrightness = (p.getBool('themeIsDark') ?? true)
          ? Brightness.dark
          : Brightness.light;
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
      isMousePassthrough = false;
    } catch (_) {}
  }

  static Future<void> saveSettings() async {
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setStringList('customFontPaths', customFontPaths);

      await p.setBool('themeIsDark', themeBrightness == Brightness.dark);
      await p.setInt('themeVariant', themeVariant.index);
      await p.setBool('enableGlow', enableGlow);
      await p.setInt('glowMode', glowMode.index);
      await p.setInt('spectrumMode', spectrumMode.index);
      await p.setInt('progressStyle', progressStyle.index);
      await p.setBool('enableProgressAutoContrast', enableProgressAutoContrast);
      await p.setBool('enableOledTheme', enableOledTheme);
      await p.setBool('enable3DCover', enable3DCover);

      await p.setString('currentFontFamily', currentFontFamily);
      await p.setInt('titleWeightIndex', titleWeightIndex);
      await p.setInt('artistWeightIndex', artistWeightIndex);

      await p.setInt('prevButtonShape', prevButtonShape.index);
      await p.setInt('playButtonShape', playButtonShape.index);
      await p.setInt('nextButtonShape', nextButtonShape.index);
      await p.setInt('widgetLayout', widgetLayout.index);
      await p.setBool('isAlwaysOnTop', isAlwaysOnTop);
    } catch (_) {}
  }
}
