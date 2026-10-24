part of 'appState.dart';


class _AppSettings {
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

  static const _systemFontsChannel = MethodChannel(
    'md3_music_widget/system_fonts',
  );
  static Future<void> loadSystemFonts({bool invalidateMetrics = false}) async {
    if (Platform.isWindows) {
      _systemFontsChannel.setMethodCallHandler((call) async {
        if (call.method == 'changed') {
          await loadSystemFonts(invalidateMetrics: true);
        }
      });
      try {
        final result = await _systemFontsChannel.invokeMethod<Object?>(
          'families',
        );
        final families = result is List
            ? result.whereType<String>()
            : const <String>[];
        var changed = false;
        final known = AppState.loadedSystemFonts.toSet();
        for (final family in families) {
          final name = family.trim();
          if (name.isNotEmpty && known.add(name)) {
            AppState.loadedSystemFonts.add(name);
            changed = true;
          }
        }
        if (changed || invalidateMetrics) AppState.fontsRevision.value++;
      } on MissingPluginException {
        
      } on PlatformException catch (error) {
        if (error.code != 'fonts_loading') {
          debugPrint('System font enumeration unavailable: ${error.code}');
        }
      }
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

        if (!AppState.loadedSystemFonts.contains(fontName)) {
          AppState.loadedSystemFonts.insert(1, fontName);
          AppState.fontsRevision.value++;
        }
        if (!AppState.customFontPaths.contains(path)) {
          AppState.customFontPaths.add(path);
          await saveSettings();
        }
        if (forLyrics) {
          AppState.lyricsFontFamily = fontName;
        } else {
          AppState.currentFontFamily = fontName;
        }
        return true;
      }
    } catch (e) {
      debugPrint("加载自定义字体失败: $e");
    }
    return false;
  }

  static Future<void> _restoreCustomFonts() async {
    for (String path in AppState.customFontPaths) {
      try {
        var file = File(path);
        if (file.existsSync()) {
          String fontName = file.uri.pathSegments.last.split('.').first;
          var bytes = await file.readAsBytes();
          var fontLoader = FontLoader(fontName);
          fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
          await fontLoader.load();
          if (!AppState.loadedSystemFonts.contains(fontName)) {
            AppState.loadedSystemFonts.insert(1, fontName);
            AppState.fontsRevision.value++;
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

      AppState.customFontPaths = snapshot?['customFontPaths'] is List
          ? (snapshot!['customFontPaths'] as List).whereType<String>().toList(
              growable: true,
            )
          : p.getStringList('customFontPaths') ?? [];

      final bool themeIsDark = snapshot?['themeIsDark'] is bool
          ? snapshot!['themeIsDark'] as bool
          : p.getBool('themeIsDark') ?? true;
      AppState.themeBrightness = themeIsDark
          ? Brightness.dark
          : Brightness.light;
      if (snapshot != null) {
        AppState.themeVariant = _enumFromName(
          DynamicSchemeVariant.values,
          snapshot['themeVariant'],
          DynamicSchemeVariant.tonalSpot,
        );
        AppState.enableGlow = snapshot['enableGlow'] is bool
            ? snapshot['enableGlow'] as bool
            : true;
        AppState.glowMode = _enumFromName(
          GlowMode.values,
          snapshot['glowMode'],
          GlowMode.waterfall,
        );
        AppState.spectrumMode = _enumFromName(
          SpectrumMode.values,
          snapshot['spectrumMode'],
          SpectrumMode.off,
        );
        AppState.showLyrics = snapshot['showLyrics'] == true;
        AppState.hideUnavailableLyrics =
            snapshot['hideUnavailableLyrics'] == true;
        AppState.wordLyricsEnabled = snapshot['wordLyricsEnabled'] != false;
        AppState.wordLyricsSmokeEnabled =
            snapshot['wordLyricsSmokeEnabled'] == true;
        AppState.lyricsHighlightStyle = _enumFromName(
          LyricsHighlightStyle.values,
          snapshot['lyricsHighlightStyle'],
          LyricsHighlightStyle.sweep,
        );
        AppState.lyricsInactiveOpacity = _validLyricsNumber(
          snapshot['lyricsInactiveOpacity'],
          .46,
          .15,
          1,
        );
        AppState.lyricsOffsetMs = _validLyricsNumber(
          snapshot['lyricsOffsetMs'],
          0,
          -5000,
          5000,
        );
        AppState.spectrumThickness = _validSpectrumThickness(
          snapshot['spectrumThickness'],
        );
        AppState.automaticSpectrumColumns =
            snapshot['automaticSpectrumColumns'] is bool
            ? snapshot['automaticSpectrumColumns'] as bool
            : true;
        AppState.spectrumColumnCount = _validSpectrumColumns(
          snapshot['spectrumColumnCount'],
        );
        AppState.lyricsUseThemeFont = snapshot['lyricsUseThemeFont'] is bool
            ? snapshot['lyricsUseThemeFont'] as bool
            : true;
        AppState.lyricsFontFamily = snapshot['lyricsFontFamily'] is String
            ? snapshot['lyricsFontFamily'] as String
            : 'System Default';
        AppState.lyricsWeightValue = snapshot['lyricsWeightValue'] is num
            ? (snapshot['lyricsWeightValue'] as num).toDouble()
            : 500.0;
        AppState.lyricsFontSize = snapshot['lyricsFontSize'] is num
            ? (snapshot['lyricsFontSize'] as num).toDouble()
            : 14.0;
        AppState.lyricsProviderChoice = _enumFromName(
          LyricsProviderChoice.values,
          snapshot['lyricsProviderChoice'],
          LyricsProviderChoice.lrclib,
        );
        AppState.lyricsTransitionStyle = _enumFromName(
          LyricsTransitionStyle.values,
          snapshot['lyricsTransitionStyle'],
          LyricsTransitionStyle.fade,
        );
        AppState.lyricsAnimationsLinked =
            snapshot['lyricsAnimationsLinked'] is bool
            ? snapshot['lyricsAnimationsLinked'] as bool
            : true;
        AppState.lyricsExitTransitionStyle = _enumFromName(
          LyricsTransitionStyle.values,
          snapshot['lyricsExitTransitionStyle'],
          AppState.lyricsTransitionStyle,
        );
        AppState.localLyricsDirectory =
            snapshot['localLyricsDirectory'] is String
            ? snapshot['localLyricsDirectory'] as String
            : '';
        AppState.progressStyle = _enumFromName(
          MD3ProgressStyle.values,
          snapshot['progressStyle'],
          MD3ProgressStyle.linear,
        );
        AppState.showPlaybackTime = snapshot['showPlaybackTime'] == true;
        AppState.settingsNavigationShape = _enumFromName(
          MD3Shape.values,
          snapshot['settingsNavigationShape'],
          MD3Shape.roundedLarge,
        );
        AppState.enableProgressAutoContrast =
            snapshot['enableProgressAutoContrast'] is bool
            ? snapshot['enableProgressAutoContrast'] as bool
            : true;
        AppState.enableOledTheme = snapshot['enableOledTheme'] is bool
            ? snapshot['enableOledTheme'] as bool
            : false;
        AppState.showPlaybackControls = snapshot['showPlaybackControls'] is bool
            ? snapshot['showPlaybackControls'] as bool
            : true;
        AppState.trackTextAnimationsEnabled =
            snapshot['trackTextAnimationsEnabled'] is bool
            ? snapshot['trackTextAnimationsEnabled'] as bool
            : true;
        AppState.coverTransitionStyle = _enumFromName(
          CoverTransitionStyle.values,
          snapshot['coverTransitionStyle'],
          CoverTransitionStyle.softSlide,
        );
        AppState.trackTextTransitionStyle = _enumFromName(
          TrackTextTransitionStyle.values,
          snapshot['trackTextTransitionStyle'],
          TrackTextTransitionStyle.particles,
        );
        AppState.trackTextAnimationsLinked =
            snapshot['trackTextAnimationsLinked'] is bool
            ? snapshot['trackTextAnimationsLinked'] as bool
            : true;
        AppState.trackTextExitStyle = _enumFromName(
          TrackTextExitStyle.values,
          snapshot['trackTextExitStyle'],
          TrackTextExitStyle.fade,
        );
        AppState.showPerformanceMonitor =
            snapshot['showPerformanceMonitor'] == true;
        AppState.performanceMetricsMask = PerformanceMetric.validMask(
          snapshot['performanceMetricsMask'],
        );
        AppState.performanceProcessExecutable =
            snapshot['performanceProcessExecutable'] as String? ?? '';
        AppState.selectedSourceAppId = snapshot['selectedSourceAppId'] is String
            ? snapshot['selectedSourceAppId'] as String
            : '';
        AppState.playlistFilePath = snapshot['playlistFilePath'] is String
            ? snapshot['playlistFilePath'] as String
            : '';
        AppState.qqPlaylistLink = snapshot['qqPlaylistLink'] is String
            ? snapshot['qqPlaylistLink'] as String
            : '';
        AppState.neteasePlaylistLink = snapshot['neteasePlaylistLink'] is String
            ? snapshot['neteasePlaylistLink'] as String
            : '';
        AppState.selectedQueueProviderId = _validQueueProvider(
          snapshot['selectedQueueProviderId'],
        );
        AppState.showNextUp = snapshot['showNextUp'] == true;
        AppState.lyricsCacheLimitMiB = _cacheLimit(
          snapshot['lyricsCacheLimitMiB'],
          16,
          256,
        );
        AppState.backgroundCacheLimitMiB = _cacheLimit(
          snapshot['backgroundCacheLimitMiB'],
          128,
          1024,
        );
        AppState.nextUpLeadSeconds = switch (snapshot['nextUpLeadSeconds']) {
          10 || 20 || 30 || 45 => snapshot['nextUpLeadSeconds'] as int,
          _ => 20,
        };
        AppState.enable3DCover = snapshot['enable3DCover'] is bool
            ? snapshot['enable3DCover'] as bool
            : true;
        AppState.enableCoverLayers = snapshot['enableCoverLayers'] is bool
            ? snapshot['enableCoverLayers'] as bool
            : true;
        AppState.currentFontFamily = snapshot['currentFontFamily'] is String
            ? snapshot['currentFontFamily'] as String
            : 'System Default';
        AppState.titleWeightValue = snapshot['titleWeightValue'] is num
            ? (snapshot['titleWeightValue'] as num).toDouble()
            : ((snapshot['titleWeightIndex'] is int
                          ? snapshot['titleWeightIndex'] as int
                          : 6) +
                      1) *
                  100.0;
        AppState.artistWeightValue = snapshot['artistWeightValue'] is num
            ? (snapshot['artistWeightValue'] as num).toDouble()
            : ((snapshot['artistWeightIndex'] is int
                          ? snapshot['artistWeightIndex'] as int
                          : 3) +
                      1) *
                  100.0;
        AppState.prevButtonShape = _enumFromName(
          MD3Shape.values,
          snapshot['prevButtonShape'],
          MD3Shape.circle,
        );
        AppState.playButtonShape = _enumFromName(
          MD3Shape.values,
          snapshot['playButtonShape'],
          MD3Shape.circle,
        );
        AppState.nextButtonShape = _enumFromName(
          MD3Shape.values,
          snapshot['nextButtonShape'],
          MD3Shape.circle,
        );
        AppState.widgetLayout = _enumFromName(
          WidgetLayout.values,
          snapshot['widgetLayout'],
          WidgetLayout.horizontal,
        );
        AppState.componentSizeMode = _enumFromName(
          ComponentSizeMode.values,
          snapshot['componentSizeMode'],
          ComponentSizeMode.standard,
        );
        AppState.customComponentScale = snapshot['customComponentScale'] is num
            ? (snapshot['customComponentScale'] as num).toDouble()
            : 1.0;
        AppState.isAlwaysOnTop = snapshot['isAlwaysOnTop'] is bool
            ? snapshot['isAlwaysOnTop'] as bool
            : true;
        AppState.isMousePassthrough = snapshot['isMousePassthrough'] is bool
            ? snapshot['isMousePassthrough'] as bool
            : false;
      } else {
        _loadLegacySettings(p);
      }

      double boundedArtworkSetting(
        String key,
        double fallback,
        double min,
        double max,
      ) {
        final value = snapshot != null ? snapshot[key] : p.get(key);
        if (value is! num || !value.isFinite) return fallback;
        return value.toDouble().clamp(min, max);
      }

      AppState.rightCoverDarkening = boundedArtworkSetting(
        'rightCoverDarkening',
        AppState.defaultRightCoverDarkening,
        0,
        0.85,
      );
      AppState.rightCoverFadeLength = boundedArtworkSetting(
        'rightCoverFadeLength',
        AppState.defaultRightCoverFadeLength,
        0.15,
        1,
      );
      final linkedFade = snapshot != null
          ? snapshot['rightCoverFadeLinked']
          : p.get('rightCoverFadeLinked');
      AppState.rightCoverFadeLinked = linkedFade is bool ? linkedFade : true;
      AppState.rightCoverFadeLengthX = boundedArtworkSetting(
        'rightCoverFadeLengthX',
        AppState.rightCoverFadeLength,
        0.15,
        1,
      );
      AppState.rightCoverFadeLengthY = boundedArtworkSetting(
        'rightCoverFadeLengthY',
        AppState.rightCoverFadeLength,
        0.15,
        1,
      );
      AppState.rightCoverBlur = boundedArtworkSetting(
        'rightCoverBlur',
        AppState.defaultRightCoverBlur,
        0,
        6,
      );
      AppState.notifyRightArtworkChanged();
      AppState.titleWeightValue = AppState._safeWeight(
        AppState.titleWeightValue,
        700.0,
      );
      AppState.artistWeightValue = AppState._safeWeight(
        AppState.artistWeightValue,
        400.0,
      );
      AppState.lyricsWeightValue = AppState._safeWeight(
        AppState.lyricsWeightValue,
        500.0,
      );
      AppState.lyricsFontSize = AppState.lyricsFontSize.isFinite
          ? AppState.lyricsFontSize.clamp(12.0, 17.0)
          : 14.0;
      AppState.customComponentScale = AppState.customComponentScale.clamp(
        AppState.minimumSizeRatio,
        AppState.maximumSizeRatio,
      );
      AppState.isMousePassthrough = false;
      final savedCacheDirectory =
          snapshot?['customCacheDirectory'] ??
          p.getString('customCacheDirectory');
      try {
        await AppState.setCacheDirectory(
          savedCacheDirectory is String ? savedCacheDirectory : '',
          persist: false,
          migrate: false,
        );
      } catch (_) {
        
        await AppState.setCacheDirectory('', persist: false, migrate: false);
      }
      AppState.refreshQueue(force: true);
      await _restoreCustomFonts();
    } catch (_) {}
  }

  static void _loadLegacySettings(SharedPreferences p) {
    AppState.themeVariant = _enumFromIndex(
      DynamicSchemeVariant.values,
      p.getInt('themeVariant'),
      DynamicSchemeVariant.tonalSpot,
    );
    AppState.enableGlow = p.getBool('enableGlow') ?? true;
    AppState.glowMode = _enumFromIndex(
      GlowMode.values,
      p.getInt('glowMode'),
      GlowMode.waterfall,
    );
    AppState.spectrumMode = _enumFromIndex(
      SpectrumMode.values,
      p.getInt('spectrumMode'),
      SpectrumMode.off,
    );
    AppState.showLyrics = p.getBool('showLyrics') ?? false;
    AppState.hideUnavailableLyrics =
        p.getBool('hideUnavailableLyrics') ?? false;
    AppState.wordLyricsEnabled = p.getBool('wordLyricsEnabled') ?? true;
    AppState.wordLyricsSmokeEnabled =
        p.getBool('wordLyricsSmokeEnabled') ?? false;
    AppState.lyricsHighlightStyle = _enumFromIndex(
      LyricsHighlightStyle.values,
      p.getInt('lyricsHighlightStyle'),
      LyricsHighlightStyle.sweep,
    );
    AppState.lyricsInactiveOpacity = _validLyricsNumber(
      p.getDouble('lyricsInactiveOpacity'),
      .46,
      .15,
      1,
    );
    AppState.lyricsOffsetMs = _validLyricsNumber(
      p.getDouble('lyricsOffsetMs'),
      0,
      -5000,
      5000,
    );
    AppState.spectrumThickness = _validSpectrumThickness(
      p.getDouble('spectrumThickness'),
    );
    AppState.automaticSpectrumColumns =
        p.getBool('automaticSpectrumColumns') ?? true;
    AppState.spectrumColumnCount = _validSpectrumColumns(
      p.getInt('spectrumColumnCount'),
    );
    AppState.lyricsUseThemeFont = p.getBool('lyricsUseThemeFont') ?? true;
    AppState.lyricsFontFamily =
        p.getString('lyricsFontFamily') ?? 'System Default';
    AppState.lyricsWeightValue = p.getDouble('lyricsWeightValue') ?? 500.0;
    AppState.lyricsFontSize = p.getDouble('lyricsFontSize') ?? 14.0;
    AppState.lyricsProviderChoice = _enumFromIndex(
      LyricsProviderChoice.values,
      p.getInt('lyricsProviderChoice'),
      LyricsProviderChoice.lrclib,
    );
    AppState.lyricsTransitionStyle = _enumFromIndex(
      LyricsTransitionStyle.values,
      p.getInt('lyricsTransitionStyle'),
      LyricsTransitionStyle.fade,
    );
    AppState.lyricsAnimationsLinked =
        p.getBool('lyricsAnimationsLinked') ?? true;
    AppState.lyricsExitTransitionStyle = _enumFromIndex(
      LyricsTransitionStyle.values,
      p.getInt('lyricsExitTransitionStyle'),
      AppState.lyricsTransitionStyle,
    );
    AppState.localLyricsDirectory = p.getString('localLyricsDirectory') ?? '';
    AppState.progressStyle = _enumFromIndex(
      MD3ProgressStyle.values,
      p.getInt('progressStyle'),
      MD3ProgressStyle.linear,
    );
    AppState.showPlaybackTime = p.getBool('showPlaybackTime') ?? false;
    AppState.settingsNavigationShape = _enumFromIndex(
      MD3Shape.values,
      p.getInt('settingsNavigationShape'),
      MD3Shape.roundedLarge,
    );
    AppState.enableProgressAutoContrast =
        p.getBool('enableProgressAutoContrast') ?? true;
    AppState.enableOledTheme = p.getBool('enableOledTheme') ?? false;
    AppState.enable3DCover = p.getBool('enable3DCover') ?? true;
    AppState.enableCoverLayers = p.getBool('enableCoverLayers') ?? true;
    AppState.coverTransitionStyle = _enumFromIndex(
      CoverTransitionStyle.values,
      p.getInt('coverTransitionStyle'),
      CoverTransitionStyle.softSlide,
    );
    AppState.showPlaybackControls = p.getBool('showPlaybackControls') ?? true;
    AppState.trackTextAnimationsEnabled =
        p.getBool('trackTextAnimationsEnabled') ?? true;
    AppState.trackTextTransitionStyle = _enumFromIndex(
      TrackTextTransitionStyle.values,
      p.getInt('trackTextTransitionStyle'),
      TrackTextTransitionStyle.particles,
    );
    AppState.trackTextAnimationsLinked =
        p.getBool('trackTextAnimationsLinked') ?? true;
    AppState.trackTextExitStyle = _enumFromIndex(
      TrackTextExitStyle.values,
      p.getInt('trackTextExitStyle'),
      TrackTextExitStyle.fade,
    );
    AppState.showPerformanceMonitor =
        p.getBool('showPerformanceMonitor') ?? false;
    AppState.performanceMetricsMask = PerformanceMetric.validMask(
      p.getInt('performanceMetricsMask'),
    );
    AppState.performanceProcessExecutable =
        p.getString('performanceProcessExecutable') ?? '';
    AppState.selectedSourceAppId = p.getString('selectedSourceAppId') ?? '';
    AppState.playlistFilePath = p.getString('playlistFilePath') ?? '';
    AppState.qqPlaylistLink = p.getString('qqPlaylistLink') ?? '';
    AppState.neteasePlaylistLink = p.getString('neteasePlaylistLink') ?? '';
    AppState.selectedQueueProviderId = _validQueueProvider(
      p.getString('selectedQueueProviderId'),
    );
    AppState.showNextUp = p.getBool('showNextUp') ?? false;
    AppState.lyricsCacheLimitMiB = _cacheLimit(
      p.getInt('lyricsCacheLimitMiB'),
      16,
      256,
    );
    AppState.backgroundCacheLimitMiB = _cacheLimit(
      p.getInt('backgroundCacheLimitMiB'),
      128,
      1024,
    );
    AppState.nextUpLeadSeconds = switch (p.getInt('nextUpLeadSeconds')) {
      10 || 20 || 30 || 45 => p.getInt('nextUpLeadSeconds')!,
      _ => 20,
    };

    AppState.currentFontFamily =
        p.getString('currentFontFamily') ?? 'System Default';
    AppState.titleWeightValue =
        p.getDouble('titleWeightValue') ??
        ((p.getInt('titleWeightIndex') ?? 6) + 1) * 100.0;
    AppState.artistWeightValue =
        p.getDouble('artistWeightValue') ??
        ((p.getInt('artistWeightIndex') ?? 3) + 1) * 100.0;

    AppState.prevButtonShape = _enumFromIndex(
      MD3Shape.values,
      p.getInt('prevButtonShape'),
      MD3Shape.circle,
    );
    AppState.playButtonShape = _enumFromIndex(
      MD3Shape.values,
      p.getInt('playButtonShape'),
      MD3Shape.circle,
    );
    AppState.nextButtonShape = _enumFromIndex(
      MD3Shape.values,
      p.getInt('nextButtonShape'),
      MD3Shape.circle,
    );
    AppState.widgetLayout = _enumFromIndex(
      WidgetLayout.values,
      p.getInt('widgetLayout'),
      WidgetLayout.horizontal,
    );
    AppState.componentSizeMode = _enumFromIndex(
      ComponentSizeMode.values,
      p.getInt('componentSizeMode'),
      ComponentSizeMode.standard,
    );
    AppState.customComponentScale =
        p
            .getDouble('customComponentScale')
            ?.clamp(AppState.minimumSizeRatio, AppState.maximumSizeRatio) ??
        1.0;
    AppState.isAlwaysOnTop = p.getBool('isAlwaysOnTop') ?? true;
    AppState.isMousePassthrough = p.getBool('isMousePassthrough') ?? false;
  }

  static Map<String, Object> _captureSettingsSnapshot() => <String, Object>{
    'customFontPaths': List<String>.from(AppState.customFontPaths),
    'themeIsDark': AppState.themeBrightness == Brightness.dark,
    'themeVariant': AppState.themeVariant.name,
    'enableGlow': AppState.enableGlow,
    'glowMode': AppState.glowMode.name,
    'rightCoverDarkening': AppState.rightCoverDarkening,
    'rightCoverFadeLength': AppState.rightCoverFadeLength,
    'rightCoverFadeLinked': AppState.rightCoverFadeLinked,
    'rightCoverFadeLengthX': AppState.rightCoverFadeLengthX,
    'rightCoverFadeLengthY': AppState.rightCoverFadeLengthY,
    'rightCoverBlur': AppState.rightCoverBlur,
    'spectrumMode': AppState.spectrumMode.name,
    'showLyrics': AppState.showLyrics,
    'hideUnavailableLyrics': AppState.hideUnavailableLyrics,
    'wordLyricsEnabled': AppState.wordLyricsEnabled,
    'wordLyricsSmokeEnabled': AppState.wordLyricsSmokeEnabled,
    'lyricsHighlightStyle': AppState.lyricsHighlightStyle.name,
    'lyricsInactiveOpacity': AppState.lyricsInactiveOpacity,
    'lyricsOffsetMs': AppState.lyricsOffsetMs,
    'spectrumThickness': AppState.spectrumThickness,
    'automaticSpectrumColumns': AppState.automaticSpectrumColumns,
    'spectrumColumnCount': AppState.spectrumColumnCount,
    'lyricsUseThemeFont': AppState.lyricsUseThemeFont,
    'lyricsFontFamily': AppState.lyricsFontFamily,
    'lyricsWeightValue': AppState.lyricsWeightValue,
    'lyricsFontSize': AppState.lyricsFontSize,
    'lyricsProviderChoice': AppState.lyricsProviderChoice.name,
    'lyricsTransitionStyle': AppState.lyricsTransitionStyle.name,
    'lyricsAnimationsLinked': AppState.lyricsAnimationsLinked,
    'lyricsExitTransitionStyle': AppState.lyricsExitTransitionStyle.name,
    'localLyricsDirectory': AppState.localLyricsDirectory,
    'progressStyle': AppState.progressStyle.name,
    'showPlaybackTime': AppState.showPlaybackTime,
    'settingsNavigationShape': AppState.settingsNavigationShape.name,
    'enableProgressAutoContrast': AppState.enableProgressAutoContrast,
    'enableOledTheme': AppState.enableOledTheme,
    'enable3DCover': AppState.enable3DCover,
    'enableCoverLayers': AppState.enableCoverLayers,
    'coverTransitionStyle': AppState.coverTransitionStyle.name,
    'showPlaybackControls': AppState.showPlaybackControls,
    'trackTextAnimationsEnabled': AppState.trackTextAnimationsEnabled,
    'trackTextTransitionStyle': AppState.trackTextTransitionStyle.name,
    'trackTextAnimationsLinked': AppState.trackTextAnimationsLinked,
    'trackTextExitStyle': AppState.trackTextExitStyle.name,
    'showPerformanceMonitor': AppState.showPerformanceMonitor,
    'performanceMetricsMask': AppState.performanceMetricsMask,
    'performanceProcessExecutable': AppState.performanceProcessExecutable,
    'selectedSourceAppId': AppState.selectedSourceAppId,
    'playlistFilePath': AppState.playlistFilePath,
    'qqPlaylistLink': AppState.qqPlaylistLink,
    'neteasePlaylistLink': AppState.neteasePlaylistLink,
    'selectedQueueProviderId': AppState.selectedQueueProviderId,
    'showNextUp': AppState.showNextUp,
    'lyricsCacheLimitMiB': AppState.lyricsCacheLimitMiB,
    'backgroundCacheLimitMiB': AppState.backgroundCacheLimitMiB,
    'customCacheDirectory': AppState.customCacheDirectory,
    'nextUpLeadSeconds': AppState.nextUpLeadSeconds,
    'currentFontFamily': AppState.currentFontFamily,
    'titleWeightValue': AppState.titleWeightValue,
    'artistWeightValue': AppState.artistWeightValue,
    'prevButtonShape': AppState.prevButtonShape.name,
    'playButtonShape': AppState.playButtonShape.name,
    'nextButtonShape': AppState.nextButtonShape.name,
    'widgetLayout': AppState.widgetLayout.name,
    'componentSizeMode': AppState.componentSizeMode.name,
    'customComponentScale': AppState.customComponentScale,
    'isAlwaysOnTop': AppState.isAlwaysOnTop,
    'isMousePassthrough': AppState.isMousePassthrough,
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

  static String _validQueueProvider(Object? value) => switch (value) {
    'qqMusicPlaylist' => 'qqMusicPlaylist',
    'neteasePlaylist' => 'neteasePlaylist',
    'localPlaylist' => 'localPlaylist',
    _ => '',
  };

  static int _cacheLimit(Object? value, int fallback, int maximum) =>
      value is num && value.isFinite
      ? value.toInt().clamp(0, maximum)
      : fallback;
  static double _validSpectrumThickness(Object? value) =>
      value is num && value.isFinite
      ? value.toDouble().clamp(0.35, 3.0)
      : AppState.defaultSpectrumThickness;
  static int _validSpectrumColumns(Object? value) =>
      value is num && value.isFinite ? value.toInt().clamp(1, 128) : 32;
  static double _validLyricsNumber(
    Object? value,
    double fallback,
    double min,
    double max,
  ) => value is num && value.isFinite
      ? value.toDouble().clamp(min, max)
      : fallback;
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
