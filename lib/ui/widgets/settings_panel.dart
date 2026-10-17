import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/app_state.dart';
import '../../core/media_provider.dart';
import '../../core/music_source_service.dart';
import '../../core/system_performance_provider.dart';
import '../../core/qq_music_playlist_queue_provider.dart';
import '../../core/netease_playlist_queue_provider.dart';
import '../../core/platform_provider.dart';
import 'md3_anchored_select.dart';
import 'settings_descriptions.dart';
import 'settings_labels.dart';
import 'settings_section_navigation.dart';
import 'settings_scroll_viewport.dart';
import 'adaptive_media_text.dart';
import 'jelly_slider.dart';
import 'editable_slider_value.dart';
import 'smooth_rounded_clip.dart';
import '../../core/cover_layers.dart';

enum _SettingsSection { window, appearance, playback, lyrics, typography }

extension on _SettingsSection {
  String get label => switch (this) {
    _SettingsSection.window => SettingsLabels.windowTab,
    _SettingsSection.appearance => SettingsLabels.appearanceTab,
    _SettingsSection.playback => SettingsLabels.playbackTab,
    _SettingsSection.lyrics => SettingsLabels.lyricsTab,
    _SettingsSection.typography => SettingsLabels.typographyTab,
  };

  IconData get icon => switch (this) {
    _SettingsSection.window => Icons.dashboard_customize_rounded,
    _SettingsSection.appearance => Icons.palette_rounded,
    _SettingsSection.playback => Icons.music_note_rounded,
    _SettingsSection.lyrics => Icons.lyrics_rounded,
    _SettingsSection.typography => Icons.text_fields_rounded,
  };
}

class SettingsPanel extends StatefulWidget {
  final VoidCallback onThemeChanged;
  final VoidCallback onVisualChanged;
  final VoidCallback onBackgroundChanged;
  final VoidCallback onLayoutChanged;
  final VoidCallback onWindowBehaviorChanged;
  final bool isMousePassthroughAvailable;
  final Future<String?> Function(String)? resolveQqPlaylistLink;

  const SettingsPanel({
    super.key,
    required this.onThemeChanged,
    required this.onVisualChanged,
    required this.onBackgroundChanged,
    required this.onLayoutChanged,
    required this.onWindowBehaviorChanged,
    required this.isMousePassthroughAvailable,
    this.resolveQqPlaylistLink,
  });

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel>
    with SingleTickerProviderStateMixin {
  late bool _hasTimeline;
  bool _hasWordTiming = false;
  _SettingsSection _selectedSection = _SettingsSection.window;
  int _sectionEntryDirection = 1;
  double _sectionEntryTravel = 50;
  late final AnimationController _sectionEntryController;
  int _entrySlot = 0;
  List<MusicSource> _sources = const [];
  bool _sourcesLoading = false;
  String? _sourceError;
  int _sourceRequestSerial = 0;
  Timer? _typographySaveTimer;
  Timer? _rightArtworkSaveTimer;
  Timer? _cacheLimitSaveTimer;
  Timer? _spectrumStyleSaveTimer;
  List<PerformanceProcess> _performanceProcesses = const [];
  bool _performanceProcessesLoading = false;
  bool _cacheDirectoryChanging = false;
  String? _cacheDirectoryError;

  Future<void> _changeCacheDirectory({bool reset = false}) async {
    if (_cacheDirectoryChanging) return;
    try {
      final path = reset ? '' : await FilePicker.getDirectoryPath();
      if (path == null || !mounted) return;
      setState(() {
        _cacheDirectoryChanging = true;
        _cacheDirectoryError = null;
      });
      await AppState.setCacheDirectory(path);
    } catch (_) {
      if (mounted) {
        setState(() => _cacheDirectoryError = '这个位置暂时无法写入，已保留原来的缓存位置');
      }
    } finally {
      if (mounted) setState(() => _cacheDirectoryChanging = false);
    }
  }

  Widget _buildCacheDirectoryRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(SettingsLabels.cacheDirectory, style: _settingTitleStyle()),
        const SizedBox(height: 4),
        Text(
          _cacheDirectoryError ?? SettingsDescriptions.cacheDirectory,
          style: _settingSubtitleStyle(),
        ),
        const SizedBox(height: 6),
        Tooltip(
          message: AppState.cacheDirectoryPath,
          child: Text(
            AppState.cacheDirectoryPath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _settingSubtitleStyle(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('choose_cache_directory'),
              onPressed: _cacheDirectoryChanging ? null : _changeCacheDirectory,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: Text(
                _cacheDirectoryChanging
                    ? SettingsLabels.cacheDirectoryChanging
                    : SettingsLabels.chooseCacheDirectory,
              ),
            ),
            if (AppState.customCacheDirectory.isNotEmpty)
              TextButton(
                onPressed: _cacheDirectoryChanging
                    ? null
                    : () => _changeCacheDirectory(reset: true),
                child: const Text(SettingsLabels.resetCacheDirectory),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _refreshPerformanceProcesses() async {
    if (_performanceProcessesLoading) return;
    setState(() => _performanceProcessesLoading = true);
    final processes = await SystemPerformanceProvider.processes();
    if (!mounted) return;
    setState(() {
      _performanceProcesses = processes;
      _performanceProcessesLoading = false;
    });
  }

  List<DropdownMenuEntry<String>> _performanceProcessEntries() {
    final selected = AppState.performanceProcessExecutable;
    return [
      const DropdownMenuEntry(
        value: '',
        label: SettingsLabels.performanceProcessNone,
      ),
      if (selected.isNotEmpty &&
          !_performanceProcesses.any(
            (entry) => entry.executable.toLowerCase() == selected.toLowerCase(),
          ))
        DropdownMenuEntry(value: selected, label: '$selected · 未运行'),
      for (final entry in _performanceProcesses)
        DropdownMenuEntry(
          value: entry.executable.toLowerCase() == selected.toLowerCase()
              ? selected
              : entry.executable,
          label: entry.executable,
        ),
    ];
  }

  Future<void> _restartMonitorElevated() async {
    await AppState.saveSettings();
    await AppState.flushSettings();
    if (await SystemPerformanceProvider.restartElevated()) {
      await AppState.exitApp();
    }
  }

  void _setPerformanceMetric(PerformanceMetric metric, bool enabled) {
    final wasVisible = AppState.performanceMonitorVisible;
    setState(() {
      AppState.performanceMetricsMask = enabled
          ? AppState.performanceMetricsMask | metric.bit
          : AppState.performanceMetricsMask & ~metric.bit;
    });
    AppState.notifyPerformanceChanged();
    unawaited(AppState.saveSettings());
    if (metric == PerformanceMetric.fps && enabled) {
      unawaited(_refreshPerformanceProcesses());
    }
    if (AppState.spectrumMode == SpectrumMode.off &&
        wasVisible != AppState.performanceMonitorVisible) {
      widget.onLayoutChanged();
    } else {
      widget.onVisualChanged();
    }
  }

  String _performanceMetricLabel(PerformanceMetric metric) => switch (metric) {
    PerformanceMetric.fps => SettingsLabels.performanceFps,
    PerformanceMetric.cpu => SettingsLabels.performanceCpu,
    PerformanceMetric.gpu => SettingsLabels.performanceGpu,
    PerformanceMetric.memory => SettingsLabels.performanceMemory,
  };

  void _updateTypography(VoidCallback change) {
    setState(change);
    AppState.notifyTypographyChanged();
    _typographySaveTimer?.cancel();
    _typographySaveTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(AppState.saveSettings()),
    );
  }

  void _updateLyricsVisual(VoidCallback change) {
    setState(change);
    AppState.lyrics.setPositionMs(AppState.lyricsPlaybackPositionMs);
    AppState.notifyLyricsVisualChanged();
    unawaited(AppState.saveSettings());
  }

  void _handleWordTiming() {
    final next = AppState.lyrics.state.document?.isWordTimed == true;
    if (mounted && next != _hasWordTiming) {
      setState(() => _hasWordTiming = next);
    }
  }

  void _updateSpectrumThickness(double value) {
    _updateSpectrumStyle(() => AppState.spectrumThickness = value);
  }

  void _updateSpectrumStyle(VoidCallback change) {
    setState(change);
    AppState.notifySpectrumStyleChanged();
    _spectrumStyleSaveTimer?.cancel();
    _spectrumStyleSaveTimer = Timer(
      const Duration(milliseconds: 450),
      _finishSpectrumStyleChange,
    );
  }

  void _finishSpectrumStyleChange() {
    _spectrumStyleSaveTimer?.cancel();
    _spectrumStyleSaveTimer = null;
    unawaited(AppState.saveSettings());
  }

  void _finishTypographyChange() {
    _typographySaveTimer?.cancel();
    _typographySaveTimer = null;
    unawaited(AppState.saveSettings());
  }

  void _updateRightArtwork(VoidCallback change) {
    setState(change);
    AppState.notifyRightArtworkChanged();
    _rightArtworkSaveTimer?.cancel();
    _rightArtworkSaveTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(AppState.saveSettings()),
    );
  }

  Widget _buildRightCoverFadeSlider({
    required String title,
    String subtitle = '',
    required double value,
    required String keyName,
    required ValueChanged<double> onChanged,
  }) => _buildContinuousSliderRow(
    title: title,
    subtitle: subtitle,
    value: value,
    min: 0.15,
    max: 1,
    resetValue: AppState.defaultRightCoverFadeLength,
    valueLabel: (value) => '${(value * 100).round()}%',
    inputScale: 100,
    inputSuffix: '%',
    sliderKey: ValueKey(keyName),
    onChanged: (value) => _updateRightArtwork(() => onChanged(value)),
    onChangeEnd: _finishRightArtworkChange,
  );

  void _finishRightArtworkChange() {
    _rightArtworkSaveTimer?.cancel();
    _rightArtworkSaveTimer = null;
    unawaited(AppState.saveSettings());
  }

  void _updateCacheLimit(VoidCallback change) {
    setState(change);
    _cacheLimitSaveTimer?.cancel();
    _cacheLimitSaveTimer = Timer(
      const Duration(milliseconds: 450),
      _finishCacheLimitChange,
    );
  }

  void _finishCacheLimitChange() {
    _cacheLimitSaveTimer?.cancel();
    _cacheLimitSaveTimer = null;
    unawaited(AppState.saveSettings());
    unawaited(AppState.applyCacheLimits());
  }

  @override
  void initState() {
    super.initState();
    _sectionEntryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
    _hasTimeline = AppState.playbackDurationMs > 0;
    _hasWordTiming = AppState.lyrics.state.document?.isWordTimed == true;
    AppState.lyrics.addListener(_handleWordTiming);
    AppState.playbackRevision.addListener(_handleTimelineAvailability);
    AppState.fontsRevision.addListener(_handleFontsChanged);
  }

  void _handleFontsChanged() {
    if (mounted) setState(() {});
  }

  void _handleTimelineAvailability() {
    final bool nextHasTimeline = AppState.playbackDurationMs > 0;
    if (!mounted || nextHasTimeline == _hasTimeline) return;
    setState(() => _hasTimeline = nextHasTimeline);
  }

  Future<void> _refreshSources() async {
    if (_sourcesLoading) return;
    final int request = ++_sourceRequestSerial;
    setState(() {
      _sourcesLoading = true;
      _sourceError = null;
    });
    try {
      final snapshot = await MusicSourceService.fetchSources();
      if (!mounted || request != _sourceRequestSerial) return;
      setState(() {
        _sources = snapshot.sources;
        _sourcesLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _sourceRequestSerial) return;
      setState(() {
        _sourcesLoading = false;
        _sourceError = '无法读取播放程序，请检查 MusicFetcher';
      });
    }
  }

  Future<void> _selectSource(String id) async {
    try {
      await MusicSourceService.selectSource(id);
      if (!mounted) return;
      setState(() {
        AppState.selectedSourceAppId = id;
        _sourceError = null;
      });
      AppState.clearSpectrum();
      unawaited(AppState.saveSettings());
      unawaited(_refreshSources());
    } catch (_) {
      if (!mounted) return;
      setState(() => _sourceError = '切换失败；请检查 MusicFetcher 后重试');
    }
  }

  Future<void> _choosePlaylistFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m3u', 'm3u8', 'json'],
      );
      final path = result?.files.single.path;
      if (!mounted || path == null || path.isEmpty) return;
      setState(() {
        AppState.playlistFilePath = path;
        AppState.selectedQueueProviderId = 'localPlaylist';
        AppState.showNextUp = true;
      });
      AppState.refreshQueue(force: true);
      widget.onLayoutChanged();
    } catch (_) {}
  }

  Future<void> _editQqPlaylist() async {
    String input = AppState.qqPlaylistLink;
    String? error;
    bool resolving = false;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text(SettingsLabels.qqPlaylist),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(SettingsDescriptions.qqPlaylistDialog),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: input,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: SettingsLabels.qqPlaylistLink,
                    hintText: 'https://y.qq.com/n/ryqq/playlist/…',
                    errorText: error,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    input = value;
                    if (error != null) updateDialog(() => error = null);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: resolving
                  ? null
                  : () async {
                      final trimmed = input.trim();
                      updateDialog(() {
                        resolving = true;
                        error = null;
                      });
                      try {
                        final id =
                            await (widget.resolveQqPlaylistLink?.call(
                                  trimmed,
                                ) ??
                                resolveQqPlaylistId(trimmed));
                        if (!context.mounted) return;
                        if (id == null) {
                          updateDialog(() {
                            resolving = false;
                            error = '没有找到歌单 ID，请粘贴 QQ 音乐歌单分享链接或数字 ID';
                          });
                          return;
                        }
                        Navigator.pop(context, id);
                      } catch (_) {
                        if (!context.mounted) return;
                        updateDialog(() {
                          resolving = false;
                          error = '打开分享链接失败，请检查网络后重试';
                        });
                      }
                    },
              child: Text(resolving ? '正在识别…' : '保存'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      AppState.qqPlaylistLink = selected;
      AppState.selectedQueueProviderId = 'qqMusicPlaylist';
      AppState.showNextUp = true;
    });
    AppState.refreshQueue(force: true);
    widget.onLayoutChanged();
  }

  List<DropdownMenuEntry<String>> _sourceEntries() {
    final selected = AppState.selectedSourceAppId;
    return [
      const DropdownMenuEntry(value: '', label: SettingsLabels.sourceAutomatic),
      if (selected.isNotEmpty &&
          !_sources.any(
            (source) => source.id.toLowerCase() == selected.toLowerCase(),
          ))
        DropdownMenuEntry(value: selected, label: '未运行 · $selected'),
      for (final source in _sources)
        DropdownMenuEntry(
          value: source.id,
          label: source.isPlaying ? '${source.label} · 播放中' : source.label,
        ),
    ];
  }

  @override
  void dispose() {
    AppState.lyrics.removeListener(_handleWordTiming);
    _sourceRequestSerial++;
    _sectionEntryController.dispose();
    if (_typographySaveTimer?.isActive == true) _finishTypographyChange();
    if (_rightArtworkSaveTimer?.isActive == true) _finishRightArtworkChange();
    if (_cacheLimitSaveTimer?.isActive == true) _finishCacheLimitChange();
    if (_spectrumStyleSaveTimer?.isActive == true) _finishSpectrumStyleChange();
    AppState.playbackRevision.removeListener(_handleTimelineAvailability);
    AppState.fontsRevision.removeListener(_handleFontsChanged);
    super.dispose();
  }

  void _selectSection(_SettingsSection section) {
    if (_selectedSection == section) return;
    setState(() {
      final delta = section.index - _selectedSection.index;
      _sectionEntryDirection = delta.isNegative ? -1 : 1;
      _sectionEntryTravel = (38.0 + delta.abs() * 10).clamp(48.0, 78.0);
      _selectedSection = section;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _sectionEntryController.value = 1;
    } else {
      _sectionEntryController.forward(from: 0);
    }
    if (section == _SettingsSection.playback) unawaited(_refreshSources());
    if (section == _SettingsSection.appearance) {
      unawaited(_refreshPerformanceProcesses());
    }
  }

  Widget _buildSectionNavigation() {
    final sections = _SettingsSection.values;
    return RepaintBoundary(
      key: const ValueKey('settings_navigation_repaint'),
      child: SettingsSectionNavigation(
        destinations: [
          for (final section in sections)
            SettingsSectionDestination(
              section.name,
              section.label,
              section.icon,
            ),
        ],
        selectedIndex: _selectedSection.index,
        shape: AppState.settingsNavigationShape,
        onSelected: (index) => _selectSection(sections[index]),
      ),
    );
  }

  Widget _buildStaggeredEntry(Widget child) {
    final slot = _entrySlot++;
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final start = (slot * 0.10).clamp(0.0, 0.50);
    final curve = Interval(start, 1, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: _sectionEntryController,
      child: child,
      builder: (context, child) {
        final progress = curve.transform(_sectionEntryController.value);
        return Opacity(
          key: ValueKey('settings_entry_$slot'),
          opacity: progress,
          child: Transform.translate(
            key: ValueKey('settings_entry_motion_$slot'),
            offset: Offset(
              (_sectionEntryTravel + slot.clamp(0, 6) * 2) *
                  _sectionEntryDirection *
                  (1 - progress),
              0,
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _entrySlot = 0;
    final textTheme = Theme.of(context).textTheme;
    final bool headingsOverArtwork = AppState.enableGlow;
    final Color headingColor = headingsOverArtwork
        ? Colors.white
        : AppState.currentScheme.onSurface;
    final Color headingSupportingColor = headingsOverArtwork
        ? Colors.white.withValues(alpha: 0.78)
        : AppState.currentScheme.onSurfaceVariant;
    final List<Shadow>? headingShadows = headingsOverArtwork
        ? [
            Shadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ]
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdaptiveMediaText(
                  SettingsLabels.heading,
                  style:
                      (textTheme.headlineSmall ?? const TextStyle(fontSize: 24))
                          .copyWith(
                            color: headingColor,
                            shadows: headingShadows,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.0,
                          ),
                ),
                const SizedBox(height: 3),
                AdaptiveMediaText(
                  SettingsDescriptions.overview,
                  style: (textTheme.bodySmall ?? const TextStyle(fontSize: 12))
                      .copyWith(
                        color: headingSupportingColor,
                        shadows: headingShadows,
                        letterSpacing: 0.0,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildSectionNavigation(),
          const SizedBox(height: 12),
          Expanded(
            child: RepaintBoundary(
              key: const ValueKey('settings_scroll_surface'),
              child: SettingsScrollViewport(
                key: ValueKey(_selectedSection),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    
                    
                    
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 40),
                    children: [
                      if (_selectedSection == _SettingsSection.window)
                        _buildCategoryCard(
                          title: SettingsLabels.windowGroup,
                          icon: Icons.dashboard_customize_rounded,
                          children: [
                            _buildSegmentedRow(
                              SettingsLabels.layout,
                              null,
                              [
                                const ButtonSegment(
                                  value: WidgetLayout.horizontal,
                                  icon: Icon(Icons.view_stream_rounded),
                                  label: Text(SettingsLabels.horizontal),
                                ),
                                const ButtonSegment(
                                  value: WidgetLayout.vertical,
                                  icon: Icon(Icons.view_carousel_rounded),
                                  label: Text(SettingsLabels.vertical),
                                ),
                              ],
                              AppState.widgetLayout,
                              (val) {
                                setState(() => AppState.widgetLayout = val);
                                widget.onLayoutChanged();
                              },
                            ),
                            _buildDivider(),
                            _buildDropdownRow<ComponentSizeMode>(
                              SettingsLabels.componentSize,
                              AppState.isCustomComponentSize
                                  ? SettingsDescriptions.customComponentSize(
                                      (AppState.customComponentScale * 100)
                                          .round(),
                                    )
                                  : SettingsDescriptions.componentSize,
                              AppState.componentSizeMode,
                              (val) {
                                if (val == ComponentSizeMode.custom &&
                                    !AppState.isCustomComponentSize) {
                                  AppState.customComponentScale =
                                      AppState.componentScale;
                                }
                                setState(
                                  () => AppState.componentSizeMode = val,
                                );
                                widget.onLayoutChanged();
                              },
                              _componentSizeEntries(),
                            ),
                            _buildDivider(),
                            _buildSwitchRow(
                              SettingsLabels.alwaysOnTop,
                              SettingsDescriptions.alwaysOnTop,
                              AppState.isAlwaysOnTop,
                              (val) {
                                setState(() => AppState.isAlwaysOnTop = val);
                                widget.onWindowBehaviorChanged();
                              },
                            ),
                            if (widget.isMousePassthroughAvailable) ...[
                              _buildDivider(),
                              _buildSwitchRow(
                                SettingsLabels.mousePassthrough,
                                SettingsDescriptions.mousePassthrough,
                                AppState.isMousePassthrough,
                                (val) {
                                  setState(
                                    () => AppState.isMousePassthrough = val,
                                  );
                                  widget.onWindowBehaviorChanged();
                                },
                              ),
                            ],
                          ],
                        ),

                      if (_selectedSection == _SettingsSection.appearance)
                        _buildCategoryCard(
                          title: SettingsLabels.themeGroup,
                          icon: Icons.palette_rounded,
                          children: [
                            _buildSegmentedRow(
                              SettingsLabels.colorTheme,
                              SettingsDescriptions.colorTheme,
                              [
                                const ButtonSegment(
                                  value: DynamicSchemeVariant.tonalSpot,
                                  label: Text(SettingsLabels.themeSoft),
                                ),
                                const ButtonSegment(
                                  value: DynamicSchemeVariant.vibrant,
                                  label: Text(SettingsLabels.themeVibrant),
                                ),
                                const ButtonSegment(
                                  value: DynamicSchemeVariant.fidelity,
                                  label: Text(SettingsLabels.themeFidelity),
                                ),
                              ],
                              AppState.themeVariant,
                              (val) {
                                setState(() => AppState.themeVariant = val);
                                widget.onThemeChanged();
                              },
                            ),
                            _buildDivider(),
                            _buildSwitchRow(
                              SettingsLabels.darkMode,
                              null,
                              AppState.themeBrightness == Brightness.dark,
                              (val) {
                                setState(
                                  () => AppState.themeBrightness = val
                                      ? Brightness.dark
                                      : Brightness.light,
                                );
                                widget.onThemeChanged();
                              },
                            ),
                            _buildDivider(),
                            _buildDropdownRow<MD3Shape>(
                              SettingsLabels.settingsNavigationShape,
                              SettingsDescriptions.settingsNavigationShape,
                              AppState.settingsNavigationShape,
                              (value) {
                                setState(
                                  () =>
                                      AppState.settingsNavigationShape = value,
                                );
                                widget.onVisualChanged();
                              },
                              const [
                                DropdownMenuEntry(
                                  value: MD3Shape.stadium,
                                  label: SettingsLabels.shapeStadium,
                                ),
                                DropdownMenuEntry(
                                  value: MD3Shape.roundedExtraSmall,
                                  label: SettingsLabels.shapeExtraSmall,
                                ),
                                DropdownMenuEntry(
                                  value: MD3Shape.roundedSmall,
                                  label: SettingsLabels.shapeSmall,
                                ),
                                DropdownMenuEntry(
                                  value: MD3Shape.roundedMedium,
                                  label: SettingsLabels.shapeMedium,
                                ),
                                DropdownMenuEntry(
                                  value: MD3Shape.roundedLarge,
                                  label: SettingsLabels.shapeLarge,
                                ),
                                DropdownMenuEntry(
                                  value: MD3Shape.roundedExtraLarge,
                                  label: SettingsLabels.shapeExtraLarge,
                                ),
                              ],
                            ),
                            _buildOptionalSetting(
                              visible:
                                  AppState.themeBrightness == Brightness.dark &&
                                  !AppState.enableGlow,
                              child: Column(
                                children: [
                                  _buildDivider(),
                                  _buildSwitchRow(
                                    SettingsLabels.oled,
                                    SettingsDescriptions.oled,
                                    AppState.enableOledTheme,
                                    (val) {
                                      setState(
                                        () => AppState.enableOledTheme = val,
                                      );
                                      widget.onBackgroundChanged();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      if (_selectedSection == _SettingsSection.appearance)
                        _buildCategoryCard(
                          title: SettingsLabels.backgroundGroup,
                          icon: Icons.animation_rounded,
                          children: [
                            _buildSwitchRow(
                              SettingsLabels.glow,
                              SettingsDescriptions.glow,
                              AppState.enableGlow,
                              (val) {
                                setState(() => AppState.enableGlow = val);
                                widget.onBackgroundChanged();
                              },
                            ),
                            _buildOptionalSetting(
                              visible: AppState.enableGlow,
                              child: Column(
                                children: [
                                  _buildDivider(),
                                  _buildSegmentedRow(
                                    SettingsLabels.glowMode,
                                    SettingsDescriptions.glowMode,
                                    [
                                      const ButtonSegment(
                                        value: GlowMode.waterfall,
                                        label: Text(
                                          SettingsLabels.glowWaterfall,
                                        ),
                                      ),
                                      const ButtonSegment(
                                        value: GlowMode.wallpaper,
                                        label: Text(
                                          SettingsLabels.glowWallpaper,
                                        ),
                                      ),
                                    ],
                                    AppState.glowMode,
                                    (val) {
                                      setState(() => AppState.glowMode = val);
                                      widget.onBackgroundChanged();
                                    },
                                  ),
                                ],
                              ),
                            ),
                            _buildDivider(),
                            _buildSwitchRow(
                              SettingsLabels.coverParallax,
                              SettingsDescriptions.coverParallax,
                              AppState.enable3DCover,
                              (val) {
                                setState(() => AppState.enable3DCover = val);
                                widget.onVisualChanged();
                              },
                            ),
                            if (AppState.enable3DCover) ...[
                              _buildDivider(),
                              _buildSwitchRow(
                                SettingsLabels.coverLayers,
                                SettingsDescriptions.coverLayers,
                                AppState.enableCoverLayers,
                                (val) {
                                  setState(
                                    () => AppState.enableCoverLayers = val,
                                  );
                                  widget.onVisualChanged();
                                },
                              ),
                              if (AppState.enableCoverLayers) ...[
                                _buildDivider(),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    12,
                                  ),
                                  child: ValueListenableBuilder<String>(
                                    valueListenable:
                                        CoverLayerService.instance.status,
                                    builder: (context, status, _) => Text(
                                      '${SettingsLabels.coverLayerStatus}：$status',
                                      style: _settingSubtitleStyle(),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                            if (_hasTimeline) _buildDivider(),
                            if (_hasTimeline)
                              _buildSwitchRow(
                                SettingsLabels.progressAutoContrast,
                                SettingsDescriptions.progressAutoContrast,
                                AppState.enableProgressAutoContrast,
                                (val) {
                                  setState(
                                    () => AppState.enableProgressAutoContrast =
                                        val,
                                  );
                                  widget.onVisualChanged();
                                },
                              ),
                            if (MediaCapability.supports(
                              AppState.mediaCapabilities,
                              MediaCapability.spectrum,
                            ))
                              _buildDivider(),
                            if (MediaCapability.supports(
                              AppState.mediaCapabilities,
                              MediaCapability.spectrum,
                            ))
                              _buildDropdownRow<SpectrumMode>(
                                SettingsLabels.spectrum,
                                SettingsDescriptions.spectrum,
                                AppState.spectrumMode,
                                (val) {
                                  final bool visibilityChanged =
                                      (AppState.spectrumMode ==
                                          SpectrumMode.off) !=
                                      (val == SpectrumMode.off);
                                  setState(() => AppState.spectrumMode = val);
                                  if (visibilityChanged) {
                                    widget.onLayoutChanged();
                                  } else {
                                    widget.onVisualChanged();
                                  }
                                },
                                _spectrumEntries(),
                              ),
                            _buildOptionalSetting(
                              visible:
                                  AppState.spectrumMode != SpectrumMode.off &&
                                  MediaCapability.supports(
                                    AppState.mediaCapabilities,
                                    MediaCapability.spectrum,
                                  ),
                              child: _buildContinuousSliderRow(
                                title: SettingsLabels.spectrumThickness,
                                subtitle:
                                    SettingsDescriptions.spectrumThickness,
                                value: AppState.spectrumThickness,
                                min: 0.35,
                                max: 3,
                                resetValue: AppState.defaultSpectrumThickness,
                                valueLabel: (value) =>
                                    '${value.toStringAsFixed(2)}×',
                                inputFractionDigits: 2,
                                inputSuffix: '×',
                                sliderKey: const ValueKey(
                                  'spectrum_thickness_slider',
                                ),
                                onChanged: _updateSpectrumThickness,
                                onChangeEnd: _finishSpectrumStyleChange,
                              ),
                            ),
                            _buildOptionalSetting(
                              visible:
                                  (AppState.spectrumMode == SpectrumMode.bars ||
                                      AppState.spectrumMode ==
                                          SpectrumMode.mirror) &&
                                  MediaCapability.supports(
                                    AppState.mediaCapabilities,
                                    MediaCapability.spectrum,
                                  ),
                              child: Column(
                                children: [
                                  _buildSwitchRow(
                                    SettingsLabels.automaticSpectrumColumns,
                                    SettingsDescriptions
                                        .automaticSpectrumColumns,
                                    AppState.automaticSpectrumColumns,
                                    (value) => _updateSpectrumStyle(
                                      () => AppState.automaticSpectrumColumns =
                                          value,
                                    ),
                                  ),
                                  _buildOptionalSetting(
                                    visible: !AppState.automaticSpectrumColumns,
                                    child: _buildContinuousSliderRow(
                                      title: SettingsLabels.spectrumColumnCount,
                                      subtitle: SettingsDescriptions
                                          .spectrumColumnCount,
                                      value: AppState.spectrumColumnCount
                                          .toDouble(),
                                      min: 1,
                                      max: 128,
                                      divisions: 127,
                                      resetValue: 32,
                                      valueLabel: (value) =>
                                          '${value.round()} 根',
                                      inputSuffix: '根',
                                      sliderKey: const ValueKey(
                                        'spectrum_column_count_slider',
                                      ),
                                      onChanged: (value) =>
                                          _updateSpectrumStyle(
                                            () => AppState.spectrumColumnCount =
                                                value.round().clamp(1, 128),
                                          ),
                                      onChangeEnd: _finishSpectrumStyleChange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      if (_selectedSection == _SettingsSection.appearance &&
                          !AppState.isVertical)
                        _buildCategoryCard(
                          title: SettingsLabels.rightCoverGroup,
                          icon: Icons.gradient_rounded,
                          children: [
                            _buildContinuousSliderRow(
                              title: SettingsLabels.rightCoverDarkening,
                              subtitle:
                                  SettingsDescriptions.rightCoverDarkening,
                              value: AppState.rightCoverDarkening,
                              min: 0,
                              max: 0.85,
                              resetValue: AppState.defaultRightCoverDarkening,
                              valueLabel: (value) =>
                                  '${(value * 100).round()}%',
                              inputScale: 100,
                              inputSuffix: '%',
                              sliderKey: const ValueKey(
                                'right_cover_darkening_slider',
                              ),
                              onChanged: (value) => _updateRightArtwork(
                                () => AppState.rightCoverDarkening = value,
                              ),
                              onChangeEnd: _finishRightArtworkChange,
                            ),
                            KeyedSubtree(
                              key: const ValueKey(
                                'right_cover_fade_linked_switch',
                              ),
                              child: _buildSwitchRow(
                                SettingsLabels.rightCoverFadeLinked,
                                SettingsDescriptions.rightCoverFadeLinked,
                                AppState.rightCoverFadeLinked,
                                (value) {
                                  _updateRightArtwork(
                                    () =>
                                        AppState.setRightCoverFadeLinked(value),
                                  );
                                  _finishRightArtworkChange();
                                },
                              ),
                            ),
                            _buildOptionalSetting(
                              visible: AppState.rightCoverFadeLinked,
                              child: _buildRightCoverFadeSlider(
                                title: SettingsLabels.rightCoverFadeLength,
                                subtitle:
                                    SettingsDescriptions.rightCoverFadeLength,
                                value: AppState.rightCoverFadeLength,
                                keyName: 'right_cover_fade_slider',
                                onChanged: (value) =>
                                    AppState.rightCoverFadeLength = value,
                              ),
                            ),
                            _buildOptionalSetting(
                              visible: !AppState.rightCoverFadeLinked,
                              child: Column(
                                children: [
                                  _buildRightCoverFadeSlider(
                                    title: SettingsLabels.rightCoverFadeX,
                                    value: AppState.rightCoverFadeLengthX,
                                    keyName: 'right_cover_fade_x_slider',
                                    onChanged: (value) =>
                                        AppState.rightCoverFadeLengthX = value,
                                  ),
                                  _buildRightCoverFadeSlider(
                                    title: SettingsLabels.rightCoverFadeY,
                                    value: AppState.rightCoverFadeLengthY,
                                    keyName: 'right_cover_fade_y_slider',
                                    onChanged: (value) =>
                                        AppState.rightCoverFadeLengthY = value,
                                  ),
                                ],
                              ),
                            ),
                            _buildContinuousSliderRow(
                              title: SettingsLabels.rightCoverBlur,
                              subtitle: SettingsDescriptions.rightCoverBlur,
                              value: AppState.rightCoverBlur,
                              min: 0,
                              max: 6,
                              resetValue: AppState.defaultRightCoverBlur,
                              valueLabel: (value) => value.toStringAsFixed(1),
                              inputFractionDigits: 1,
                              sliderKey: const ValueKey(
                                'right_cover_blur_slider',
                              ),
                              onChanged: (value) => _updateRightArtwork(
                                () => AppState.rightCoverBlur = value,
                              ),
                              onChangeEnd: _finishRightArtworkChange,
                            ),
                          ],
                        ),
                      if (_selectedSection == _SettingsSection.appearance)
                        _buildCategoryCard(
                          title: SettingsLabels.performanceGroup,
                          icon: Icons.speed_rounded,
                          children: [
                            _buildSwitchRow(
                              SettingsLabels.performanceMonitor,
                              SettingsDescriptions.performanceMonitor,
                              AppState.showPerformanceMonitor,
                              (value) {
                                final wasVisible =
                                    AppState.performanceMonitorVisible;
                                setState(
                                  () => AppState.showPerformanceMonitor = value,
                                );
                                AppState.notifyPerformanceChanged();
                                if (value &&
                                    AppState.performanceMetricEnabled(
                                      PerformanceMetric.fps,
                                    )) {
                                  unawaited(_refreshPerformanceProcesses());
                                }
                                if (AppState.spectrumMode == SpectrumMode.off &&
                                    wasVisible !=
                                        AppState.performanceMonitorVisible) {
                                  widget.onLayoutChanged();
                                } else {
                                  widget.onVisualChanged();
                                }
                              },
                            ),
                            _buildOptionalSetting(
                              visible: AppState.showPerformanceMonitor,
                              child: Column(
                                children: [
                                  _buildDivider(),
                                  for (final metric in PerformanceMetric.values)
                                    KeyedSubtree(
                                      key: ValueKey(
                                        'performance_toggle_${metric.name}',
                                      ),
                                      child: _buildSwitchRow(
                                        _performanceMetricLabel(metric),
                                        null,
                                        AppState.performanceMetricEnabled(
                                          metric,
                                        ),
                                        (value) => _setPerformanceMetric(
                                          metric,
                                          value,
                                        ),
                                      ),
                                    ),
                                  _buildOptionalSetting(
                                    visible: AppState.performanceMetricEnabled(
                                      PerformanceMetric.fps,
                                    ),
                                    child: ValueListenableBuilder<String>(
                                      valueListenable:
                                          SystemPerformanceProvider.fpsStatus,
                                      builder: (context, status, _) => Column(
                                        children: [
                                          _buildDropdownRow<String>(
                                            SettingsLabels.performanceProcess,
                                            SettingsDescriptions.performanceFpsStatus(
                                              status,
                                            ),
                                            AppState
                                                .performanceProcessExecutable,
                                            (value) {
                                              setState(
                                                () =>
                                                    AppState.performanceProcessExecutable =
                                                        value,
                                              );
                                              AppState.notifyPerformanceChanged();
                                              unawaited(
                                                AppState.saveSettings(),
                                              );
                                            },
                                            _performanceProcessEntries(),
                                            fullWidth: true,
                                            actionButton: IconButton(
                                              tooltip: '刷新程序列表',
                                              onPressed:
                                                  _performanceProcessesLoading
                                                  ? null
                                                  : _refreshPerformanceProcesses,
                                              icon: const Icon(
                                                Icons.refresh_rounded,
                                              ),
                                            ),
                                          ),
                                          if (status == 'permissionDenied')
                                            TextButton.icon(
                                              onPressed:
                                                  _restartMonitorElevated,
                                              icon: const Icon(
                                                Icons
                                                    .admin_panel_settings_outlined,
                                              ),
                                              label: const Text(
                                                SettingsLabels
                                                    .performanceAuthorize,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      if (_selectedSection == _SettingsSection.appearance)
                        _buildCategoryCard(
                          title: SettingsLabels.storageGroup,
                          icon: Icons.storage_rounded,
                          children: [
                            _buildCacheDirectoryRow(),
                            _buildDivider(),
                            _buildContinuousSliderRow(
                              title: SettingsLabels.lyricsCacheLimit,
                              subtitle: SettingsDescriptions.lyricsCacheLimit,
                              value: AppState.lyricsCacheLimitMiB.toDouble(),
                              min: 0,
                              max: 256,
                              divisions: 256,
                              resetValue: 16,
                              valueLabel: SettingsLabels.cacheCapacity,
                              inputSuffix: 'MiB',
                              sliderKey: const ValueKey(
                                'lyrics_cache_limit_slider',
                              ),
                              onChanged: (value) => _updateCacheLimit(
                                () => AppState.lyricsCacheLimitMiB = value
                                    .round(),
                              ),
                              onChangeEnd: _finishCacheLimitChange,
                            ),
                            _buildDivider(),
                            _buildContinuousSliderRow(
                              title: SettingsLabels.backgroundCacheLimit,
                              subtitle:
                                  SettingsDescriptions.backgroundCacheLimit,
                              value: AppState.backgroundCacheLimitMiB
                                  .toDouble(),
                              min: 0,
                              max: 1024,
                              divisions: 1024,
                              resetValue: 128,
                              valueLabel: SettingsLabels.cacheCapacity,
                              inputSuffix: 'MiB',
                              sliderKey: const ValueKey(
                                'background_cache_limit_slider',
                              ),
                              onChanged: (value) => _updateCacheLimit(
                                () => AppState.backgroundCacheLimitMiB = value
                                    .round(),
                              ),
                              onChangeEnd: _finishCacheLimitChange,
                            ),
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    SettingsDescriptions.cacheDiskOnly,
                                    style: _settingSubtitleStyle(),
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton.tonal(
                                    onPressed: () async {
                                      final clear = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text(
                                            SettingsLabels.clearCaches,
                                          ),
                                          content: const Text(
                                            '只清理本程序保存的歌词和背景源图，不会删除你的歌单、LRC 文件或当前画面。',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('取消'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('清理'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (clear == true) {
                                        await AppState.clearPersistentCaches();
                                        if (mounted) setState(() {});
                                      }
                                    },
                                    child: const Text(
                                      SettingsLabels.clearCaches,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      if (_selectedSection == _SettingsSection.playback)
                        _buildCategoryCard(
                          title: SettingsLabels.playbackGroup,
                          icon: Icons.widgets_rounded,
                          children: [
                            _buildDropdownRow<String>(
                              SettingsLabels.sourceApp,
                              _sourceError ??
                                  (AppState.selectedSourceAppId.isEmpty
                                      ? SettingsDescriptions.sourceAutomatic
                                      : SettingsDescriptions.sourceSelected),
                              AppState.selectedSourceAppId,
                              (id) => unawaited(_selectSource(id)),
                              _sourceEntries(),
                              fullWidth: true,
                              actionButton: IconButton(
                                tooltip: '刷新播放程序列表',
                                onPressed: _sourcesLoading
                                    ? null
                                    : _refreshSources,
                                icon: _sourcesLoading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh_rounded),
                              ),
                            ),
                            _buildDivider(),
                            _buildSwitchRow(
                              SettingsLabels.trackTextAnimations,
                              SettingsDescriptions.trackTextAnimations,
                              AppState.trackTextAnimationsEnabled,
                              (value) {
                                setState(
                                  () => AppState.trackTextAnimationsEnabled =
                                      value,
                                );
                                widget.onVisualChanged();
                              },
                            ),
                            _buildOptionalSetting(
                              visible: AppState.trackTextAnimationsEnabled,
                              child: Column(
                                children: [
                                  _buildDivider(),
                                  _buildDropdownRow<TrackTextTransitionStyle>(
                                    SettingsLabels.trackTextTransition,
                                    SettingsDescriptions.trackTextTransition,
                                    AppState.trackTextTransitionStyle,
                                    (value) {
                                      setState(
                                        () =>
                                            AppState.trackTextTransitionStyle =
                                                value,
                                      );
                                      widget.onVisualChanged();
                                    },
                                    _trackTextTransitionEntries(),
                                  ),
                                  _buildDivider(),
                                  _buildSwitchRow(
                                    SettingsLabels.trackTextAnimationsLinked,
                                    SettingsDescriptions
                                        .trackTextAnimationsLinked,
                                    AppState.trackTextAnimationsLinked,
                                    (value) {
                                      setState(
                                        () =>
                                            AppState.trackTextAnimationsLinked =
                                                value,
                                      );
                                      widget.onVisualChanged();
                                    },
                                  ),
                                  _buildOptionalSetting(
                                    visible:
                                        !AppState.trackTextAnimationsLinked,
                                    child: Column(
                                      children: [
                                        _buildDivider(),
                                        _buildDropdownRow<TrackTextExitStyle>(
                                          SettingsLabels
                                              .trackTextExitTransition,
                                          SettingsDescriptions
                                              .trackTextExitTransition,
                                          AppState.trackTextExitStyle,
                                          (value) {
                                            setState(
                                              () =>
                                                  AppState.trackTextExitStyle =
                                                      value,
                                            );
                                            widget.onVisualChanged();
                                          },
                                          _trackTextExitEntries(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildDivider(),
                            _buildDropdownRow<CoverTransitionStyle>(
                              SettingsLabels.coverTransition,
                              SettingsDescriptions.coverTransition,
                              AppState.coverTransitionStyle,
                              (value) {
                                setState(
                                  () => AppState.coverTransitionStyle = value,
                                );
                                widget.onVisualChanged();
                              },
                              _coverTransitionEntries(),
                            ),
                            _buildDivider(),
                            _buildSwitchRow(
                              SettingsLabels.playbackControls,
                              SettingsDescriptions.playbackControls,
                              AppState.showPlaybackControls,
                              (val) {
                                setState(
                                  () => AppState.showPlaybackControls = val,
                                );
                                widget.onLayoutChanged();
                              },
                            ),
                            _buildDivider(),
                            if (MediaCapability.supports(
                              AppState.mediaCapabilities,
                              MediaCapability.timeline,
                            ))
                              _buildDropdownRow<MD3ProgressStyle>(
                                SettingsLabels.progressStyle,
                                null,
                                AppState.progressStyle,
                                (val) {
                                  setState(() => AppState.progressStyle = val);
                                  widget.onVisualChanged();
                                },
                                _progressStyleEntries(),
                              ),
                            if (MediaCapability.supports(
                              AppState.mediaCapabilities,
                              MediaCapability.timeline,
                            ))
                              KeyedSubtree(
                                key: const ValueKey('playback_time_switch'),
                                child: _buildSwitchRow(
                                  SettingsLabels.playbackTime,
                                  SettingsDescriptions.playbackTime,
                                  AppState.showPlaybackTime,
                                  (value) {
                                    setState(
                                      () => AppState.showPlaybackTime = value,
                                    );
                                    widget.onVisualChanged();
                                  },
                                ),
                              ),
                            if (MediaCapability.supports(
                              AppState.mediaCapabilities,
                              MediaCapability.timeline,
                            ))
                              _buildDivider(),
                            _buildOptionalSetting(
                              visible: AppState.showPlaybackControls,
                              child: Column(
                                children: [
                                  _buildDropdownRow<MD3Shape>(
                                    SettingsLabels.playButton,
                                    null,
                                    AppState.playButtonShape,
                                    (val) {
                                      setState(
                                        () => AppState.playButtonShape = val,
                                      );
                                      widget.onVisualChanged();
                                    },
                                    _shapeEntries(),
                                  ),
                                  _buildDivider(),
                                  _buildDropdownRow<MD3Shape>(
                                    SettingsLabels.previousButton,
                                    null,
                                    AppState.prevButtonShape,
                                    (val) {
                                      setState(
                                        () => AppState.prevButtonShape = val,
                                      );
                                      widget.onVisualChanged();
                                    },
                                    _shapeEntries(),
                                  ),
                                  _buildDivider(),
                                  _buildDropdownRow<MD3Shape>(
                                    SettingsLabels.nextButton,
                                    null,
                                    AppState.nextButtonShape,
                                    (val) {
                                      setState(
                                        () => AppState.nextButtonShape = val,
                                      );
                                      widget.onVisualChanged();
                                    },
                                    _shapeEntries(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      if (_selectedSection == _SettingsSection.playback)
                        _buildCategoryCard(
                          title: SettingsLabels.nextUpGroup,
                          icon: Icons.queue_music_rounded,
                          children: [
                            _buildSwitchRow(
                              SettingsLabels.showNextUp,
                              SettingsDescriptions.showPlaylist,
                              AppState.showNextUp,
                              (value) {
                                setState(() => AppState.showNextUp = value);
                                AppState.refreshQueue(force: true);
                                widget.onLayoutChanged();
                              },
                            ),
                            _buildOptionalSetting(
                              visible: AppState.showNextUp,
                              child: Column(
                                children: [
                                  _buildDivider(),
                                  _buildPlaylistSourceSelector(),
                                  _buildDivider(),
                                  _buildSelectedPlaylistRow(),
                                  _buildDivider(),
                                  _buildDropdownRow<int>(
                                    SettingsLabels.nextUpLead,
                                    SettingsDescriptions.nextUpLead,
                                    AppState.nextUpLeadSeconds,
                                    (value) {
                                      setState(
                                        () =>
                                            AppState.nextUpLeadSeconds = value,
                                      );
                                      AppState.playbackRevision.value++;
                                      widget.onVisualChanged();
                                    },
                                    const [
                                      DropdownMenuEntry(
                                        value: 10,
                                        label: SettingsLabels.lead10Seconds,
                                      ),
                                      DropdownMenuEntry(
                                        value: 20,
                                        label: SettingsLabels.lead20Seconds,
                                      ),
                                      DropdownMenuEntry(
                                        value: 30,
                                        label: SettingsLabels.lead30Seconds,
                                      ),
                                      DropdownMenuEntry(
                                        value: 45,
                                        label: SettingsLabels.lead45Seconds,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      if (_selectedSection == _SettingsSection.lyrics)
                        _buildCategoryCard(
                          title: SettingsLabels.lyricsGroup,
                          icon: Icons.lyrics_rounded,
                          children: [
                            _buildSwitchRow(
                              SettingsLabels.showLyrics,
                              SettingsDescriptions.showLyrics,
                              AppState.showLyrics,
                              (value) {
                                setState(() => AppState.showLyrics = value);
                                AppState.refreshLyrics();
                                AppState.notifyLyricsVisualChanged();
                                widget.onLayoutChanged();
                              },
                            ),
                            _buildOptionalSetting(
                              visible: AppState.showLyrics,
                              child: Column(
                                children: [
                                  _buildSwitchRow(
                                    SettingsLabels.hideUnavailableLyrics,
                                    SettingsDescriptions.hideUnavailableLyrics,
                                    AppState.hideUnavailableLyrics,
                                    (value) {
                                      setState(
                                        () => AppState.hideUnavailableLyrics =
                                            value,
                                      );
                                      AppState.notifyLyricsVisualChanged();
                                      unawaited(AppState.saveSettings());
                                      widget.onVisualChanged();
                                    },
                                  ),
                                  _buildDivider(),
                                  _buildDropdownRow<LyricsProviderChoice>(
                                    SettingsLabels.lyricsProvider,
                                    switch (AppState.lyricsProviderChoice) {
                                      LyricsProviderChoice.lrclib =>
                                        SettingsDescriptions
                                            .lyricsProviderLrclib,
                                      LyricsProviderChoice.localLrc =>
                                        SettingsDescriptions
                                            .lyricsProviderLocal,
                                      LyricsProviderChoice.qqMusic =>
                                        SettingsDescriptions
                                            .lyricsProviderQqMusic,
                                      LyricsProviderChoice.neteaseCloud =>
                                        SettingsDescriptions
                                            .lyricsProviderNetease,
                                    },
                                    AppState.lyricsProviderChoice,
                                    (value) {
                                      setState(
                                        () => AppState.lyricsProviderChoice =
                                            value,
                                      );
                                      AppState.refreshLyrics();
                                      widget.onVisualChanged();
                                    },
                                    const [
                                      DropdownMenuEntry(
                                        value: LyricsProviderChoice.lrclib,
                                        label: SettingsLabels.providerLrclib,
                                      ),
                                      DropdownMenuEntry(
                                        value: LyricsProviderChoice.localLrc,
                                        label: SettingsLabels.providerLocal,
                                      ),
                                      DropdownMenuEntry(
                                        value: LyricsProviderChoice.qqMusic,
                                        label: SettingsLabels.providerQqMusic,
                                      ),
                                      DropdownMenuEntry(
                                        value:
                                            LyricsProviderChoice.neteaseCloud,
                                        label: SettingsLabels.providerNetease,
                                      ),
                                    ],
                                  ),
                                  _buildOptionalSetting(
                                    visible:
                                        AppState.lyricsProviderChoice ==
                                        LyricsProviderChoice.localLrc,
                                    child: Column(
                                      children: [
                                        _buildDivider(),
                                        _buildLocalLyricsFolderRow(),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            SettingsDescriptions
                                                .localTimedLyrics,
                                            style: _settingSubtitleStyle(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildDivider(),
                                  _buildSwitchRow(
                                    SettingsLabels.wordLyrics,
                                    SettingsDescriptions.wordLyrics,
                                    AppState.wordLyricsEnabled,
                                    (value) => _updateLyricsVisual(
                                      () => AppState.wordLyricsEnabled = value,
                                    ),
                                  ),
                                  _buildOptionalSetting(
                                    visible:
                                        _hasWordTiming &&
                                        AppState.wordLyricsEnabled,
                                    child: Column(
                                      children: [
                                        _buildSwitchRow(
                                          SettingsLabels.wordLyricsSmoke,
                                          SettingsDescriptions.wordLyricsSmoke,
                                          AppState.wordLyricsSmokeEnabled,
                                          (value) => _updateLyricsVisual(
                                            () =>
                                                AppState.wordLyricsSmokeEnabled =
                                                    value,
                                          ),
                                        ),
                                        _buildOptionalSetting(
                                          visible:
                                              !AppState.wordLyricsSmokeEnabled,
                                          child: Column(
                                            children: [
                                              _buildDropdownRow<
                                                LyricsHighlightStyle
                                              >(
                                                SettingsLabels.wordLyricsStyle,
                                                null,
                                                AppState.lyricsHighlightStyle,
                                                (value) => _updateLyricsVisual(
                                                  () =>
                                                      AppState.lyricsHighlightStyle =
                                                          value,
                                                ),
                                                const [
                                                  DropdownMenuEntry(
                                                    value: LyricsHighlightStyle
                                                        .sweep,
                                                    label: SettingsLabels
                                                        .wordLyricsSweep,
                                                  ),
                                                  DropdownMenuEntry(
                                                    value: LyricsHighlightStyle
                                                        .soft,
                                                    label: SettingsLabels
                                                        .wordLyricsSoft,
                                                  ),
                                                  DropdownMenuEntry(
                                                    value: LyricsHighlightStyle
                                                        .emphasis,
                                                    label: SettingsLabels
                                                        .wordLyricsEmphasis,
                                                  ),
                                                ],
                                              ),
                                              _buildContinuousSliderRow(
                                                title: SettingsLabels
                                                    .wordLyricsInactive,
                                                subtitle: SettingsDescriptions
                                                    .wordLyricsInactive,
                                                value: AppState
                                                    .lyricsInactiveOpacity,
                                                min: .15,
                                                max: 1,
                                                resetValue: .46,
                                                sliderKey: const ValueKey(
                                                  'lyrics_inactive_slider',
                                                ),
                                                valueLabel: (value) =>
                                                    '${(value * 100).round()}%',
                                                inputScale: 100,
                                                inputSuffix: '%',
                                                onChanged: (value) =>
                                                    _updateLyricsVisual(
                                                      () =>
                                                          AppState.lyricsInactiveOpacity =
                                                              value,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildContinuousSliderRow(
                                    title: SettingsLabels.lyricsOffset,
                                    subtitle: SettingsDescriptions.lyricsOffset,
                                    value: AppState.lyricsOffsetMs / 1000,
                                    min: -5,
                                    max: 5,
                                    divisions: 200,
                                    resetValue: 0,
                                    sliderKey: const ValueKey(
                                      'lyrics_offset_slider',
                                    ),
                                    valueLabel: (value) =>
                                        '${value > 0 ? '+' : ''}${value.toStringAsFixed(3)} 秒',
                                    inputFractionDigits: 3,
                                    inputSuffix: '秒',
                                    onChanged: (value) => _updateLyricsVisual(
                                      () => AppState.lyricsOffsetMs =
                                          (value * 1000).roundToDouble(),
                                    ),
                                  ),
                                  _buildDivider(),
                                  _buildSwitchRow(
                                    SettingsLabels.lyricsLinkAnimations,
                                    SettingsDescriptions.lyricsLinkAnimations,
                                    AppState.lyricsAnimationsLinked,
                                    (value) {
                                      setState(
                                        () => AppState.lyricsAnimationsLinked =
                                            value,
                                      );
                                      AppState.notifyLyricsVisualChanged();
                                      widget.onVisualChanged();
                                    },
                                  ),
                                  _buildDivider(),
                                  _buildDropdownRow<LyricsTransitionStyle>(
                                    AppState.lyricsAnimationsLinked
                                        ? SettingsLabels.lyricsTransition
                                        : SettingsLabels.lyricsEnterTransition,
                                    SettingsDescriptions.lyricsTransition,
                                    AppState.lyricsTransitionStyle,
                                    (value) {
                                      setState(() {
                                        AppState.lyricsTransitionStyle = value;
                                        if (AppState.lyricsAnimationsLinked) {
                                          AppState.lyricsExitTransitionStyle =
                                              value;
                                        }
                                      });
                                      AppState.notifyLyricsVisualChanged();
                                      widget.onVisualChanged();
                                    },
                                    _lyricsTransitionEntries(),
                                  ),
                                  _buildOptionalSetting(
                                    visible: !AppState.lyricsAnimationsLinked,
                                    child: Column(
                                      children: [
                                        _buildDivider(),
                                        _buildDropdownRow<
                                          LyricsTransitionStyle
                                        >(
                                          SettingsLabels.lyricsExitTransition,
                                          SettingsDescriptions
                                              .lyricsExitTransition,
                                          AppState.lyricsExitTransitionStyle,
                                          (value) {
                                            setState(
                                              () =>
                                                  AppState.lyricsExitTransitionStyle =
                                                      value,
                                            );
                                            AppState.notifyLyricsVisualChanged();
                                            widget.onVisualChanged();
                                          },
                                          _lyricsTransitionEntries(
                                            exiting: true,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildDivider(),
                                  _buildSwitchRow(
                                    SettingsLabels.lyricsUseThemeFont,
                                    SettingsDescriptions.lyricsUseThemeFont,
                                    AppState.lyricsUseThemeFont,
                                    (value) {
                                      _updateTypography(
                                        () =>
                                            AppState.lyricsUseThemeFont = value,
                                      );
                                    },
                                    onReset: AppState.lyricsUseThemeFont
                                        ? null
                                        : () {
                                            _updateTypography(
                                              () =>
                                                  AppState.lyricsUseThemeFont =
                                                      true,
                                            );
                                            _finishTypographyChange();
                                          },
                                  ),
                                  _buildOptionalSetting(
                                    visible: !AppState.lyricsUseThemeFont,
                                    child: _buildDropdownRow<String>(
                                      SettingsLabels.lyricsFont,
                                      null,
                                      AppState.lyricsFontFamily,
                                      (value) => _updateTypography(
                                        () => AppState.lyricsFontFamily = value,
                                      ),
                                      AppState.loadedSystemFonts
                                          .map(
                                            (font) => DropdownMenuEntry<String>(
                                              value: font,
                                              label: font == 'System Default'
                                                  ? SettingsLabels
                                                        .systemDefaultFont
                                                  : font,
                                            ),
                                          )
                                          .toList(),
                                      actionButton: IconButton(
                                        tooltip: '导入歌词字体文件',
                                        icon: const Icon(
                                          Icons.add_circle_outline_rounded,
                                        ),
                                        onPressed: () async {
                                          final success =
                                              await AppState.importCustomFont(
                                                forLyrics: true,
                                              );
                                          if (!mounted || !success) return;
                                          setState(() {});
                                          AppState.notifyTypographyChanged();
                                          widget.onVisualChanged();
                                        },
                                      ),
                                      onReset:
                                          AppState.lyricsFontFamily ==
                                              AppState.defaultFontFamily
                                          ? null
                                          : () {
                                              _updateTypography(
                                                () =>
                                                    AppState.lyricsFontFamily =
                                                        AppState
                                                            .defaultFontFamily,
                                              );
                                              _finishTypographyChange();
                                            },
                                    ),
                                  ),
                                  _buildDivider(),
                                  _buildContinuousSliderRow(
                                    title: SettingsLabels.lyricsWeight,
                                    subtitle: SettingsDescriptions.lyricsWeight,
                                    value: AppState.lyricsWeightValue,
                                    min: 100,
                                    max: 900,
                                    valueLabel: (value) => 'W${value.round()}',
                                    inputPrefix: 'W',
                                    sliderKey: const ValueKey(
                                      'lyrics_weight_slider',
                                    ),
                                    resetValue:
                                        AppState.defaultLyricsWeightValue,
                                    onChanged: (value) => _updateTypography(
                                      () => AppState.lyricsWeightValue = value,
                                    ),
                                  ),
                                  _buildDivider(),
                                  _buildContinuousSliderRow(
                                    title: SettingsLabels.lyricsSize,
                                    subtitle: SettingsDescriptions.lyricsSize,
                                    value: AppState.lyricsFontSize,
                                    min: 12,
                                    max: 17,
                                    valueLabel: (value) =>
                                        '${value.toStringAsFixed(1)} px',
                                    inputFractionDigits: 1,
                                    inputSuffix: 'px',
                                    sliderKey: const ValueKey(
                                      'lyrics_size_slider',
                                    ),
                                    resetValue: AppState.defaultLyricsFontSize,
                                    onChanged: (value) => _updateTypography(
                                      () => AppState.lyricsFontSize = value,
                                    ),
                                  ),
                                  _buildTypographyPreview(
                                    title: SettingsLabels.lyricsPreview,
                                    sample: '此刻播放的音乐，值得被看见。',
                                    style: AppState.lyricsTextStyle(
                                      AppState.currentScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      if (_selectedSection == _SettingsSection.typography)
                        _buildCategoryCard(
                          title: SettingsLabels.typographyGroup,
                          icon: Icons.text_fields_rounded,
                          children: [
                            _buildDropdownRow<String>(
                              SettingsLabels.globalFont,
                              SettingsDescriptions.globalFont,
                              AppState.currentFontFamily,
                              (val) {
                                setState(
                                  () => AppState.currentFontFamily = val,
                                );
                                widget.onVisualChanged();
                              },
                              AppState.loadedSystemFonts
                                  .map(
                                    (fontName) => DropdownMenuEntry<String>(
                                      value: fontName,
                                      label:
                                          fontName == AppState.defaultFontFamily
                                          ? SettingsLabels.systemDefaultFont
                                          : fontName,
                                    ),
                                  )
                                  .toList(),
                              actionButton: IconButton(
                                tooltip: "导入本地 .ttf 字体文件",
                                icon: Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: AppState.currentScheme.primary,
                                ),
                                onPressed: () async {
                                  final bool success =
                                      await AppState.importCustomFont();
                                  if (success) {
                                    setState(() {});
                                    widget.onVisualChanged();
                                  }
                                },
                              ),
                              onReset:
                                  AppState.currentFontFamily ==
                                      AppState.defaultFontFamily
                                  ? null
                                  : () {
                                      _updateTypography(
                                        () => AppState.currentFontFamily =
                                            AppState.defaultFontFamily,
                                      );
                                      _finishTypographyChange();
                                      widget.onVisualChanged();
                                    },
                            ),
                            _buildDivider(),
                            _buildContinuousSliderRow(
                              title: SettingsLabels.titleWeight,
                              subtitle: SettingsDescriptions.titleWeight,
                              value: AppState.titleWeightValue,
                              min: 100,
                              max: 900,
                              valueLabel: (value) => 'W${value.round()}',
                              inputPrefix: 'W',
                              sliderKey: const ValueKey('title_weight_slider'),
                              resetValue: AppState.defaultTitleWeightValue,
                              onChanged: (value) => _updateTypography(
                                () => AppState.titleWeightValue = value,
                              ),
                            ),
                            _buildDivider(),
                            _buildContinuousSliderRow(
                              title: SettingsLabels.artistWeight,
                              subtitle: SettingsDescriptions.artistWeight,
                              value: AppState.artistWeightValue,
                              min: 100,
                              max: 900,
                              valueLabel: (value) => 'W${value.round()}',
                              inputPrefix: 'W',
                              sliderKey: const ValueKey('artist_weight_slider'),
                              resetValue: AppState.defaultArtistWeightValue,
                              onChanged: (value) => _updateTypography(
                                () => AppState.artistWeightValue = value,
                              ),
                            ),
                            _buildTypographyPreview(
                              title: SettingsLabels.playbackPreview,
                              sample: '歌曲名称',
                              style: TextStyle(
                                fontFamily: AppState.effectiveGlobalFontFamily,
                                fontSize: 18,
                                fontFamilyFallback: AppState.textFontFallback,
                                color: AppState.currentScheme.onSurface,
                                fontWeight: AppState.titleWeight,
                                fontVariations: AppState.variationsFor(
                                  AppState.titleWeightValue,
                                  fontSize: 18,
                                ),
                              ),
                              secondaryStyle: TextStyle(
                                fontFamily: AppState.effectiveGlobalFontFamily,
                                fontSize: 13,
                                fontFamilyFallback: AppState.textFontFallback,
                                color: AppState.currentScheme.onSurfaceVariant,
                                fontWeight: AppState.artistWeight,
                                fontVariations: AppState.variationsFor(
                                  AppState.artistWeightValue,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                ),
                                label: const Text(SettingsLabels.fontCredits),
                                onPressed: () => showLicensePage(
                                  context: context,
                                  applicationName: 'MD3 Music Widget',
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final bool headingOverArtwork = AppState.enableGlow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStaggeredEntry(
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: [
                  Container(
                    key: ValueKey('settings_category_badge_$title'),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppState.currentScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      size: 18,
                      color: AppState.currentScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  AdaptiveMediaText(
                    title,
                    style:
                        (textTheme.titleSmall ?? const TextStyle(fontSize: 14))
                            .copyWith(
                              color: headingOverArtwork
                                  ? Colors.white
                                  : AppState.currentScheme.onSurface,
                              shadows: headingOverArtwork
                                  ? [
                                      Shadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.38,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.0,
                            ),
                  ),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppState.currentScheme.surfaceContainerLow.withValues(
                alpha: 0.82,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: SmoothRoundedClip(
              composite: false,
              borderRadius: BorderRadius.circular(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final child in children)
                    if (child is SizedBox && child.height == 2)
                      child
                    else
                      _buildStaggeredEntry(child),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => const SizedBox(height: 2);

  Widget _buildContinuousSliderRow({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required String Function(double) valueLabel,
    required ValueChanged<double> onChanged,
    required Key sliderKey,
    required double resetValue,
    int? divisions,
    VoidCallback? onChangeEnd,
    double inputScale = 1,
    int inputFractionDigits = 0,
    String inputPrefix = '',
    String inputSuffix = '',
  }) {
    final displayedValue = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: _settingTitleStyle())),
              EditableSliderValue(
                key: ValueKey('value_$sliderKey'),
                title: title,
                label: valueLabel(displayedValue),
                value: displayedValue,
                min: min,
                max: max,
                inputScale: inputScale,
                fractionDigits: inputFractionDigits,
                prefix: inputPrefix,
                suffix: inputSuffix,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd ?? _finishTypographyChange,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppState.currentScheme.primary,
                ),
              ),
              SizedBox(
                width: 48,
                height: 48,
                child: (value - resetValue).abs() > 0.001
                    ? IconButton(
                        key: ValueKey('reset_${title}_slider'),
                        tooltip: '重置$title',
                        icon: const Icon(Icons.restart_alt_rounded),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          onChanged(resetValue);
                          (onChangeEnd ?? _finishTypographyChange)();
                        },
                      )
                    : null,
              ),
            ],
          ),
          Text(subtitle, style: _settingSubtitleStyle()),
          JellySlider(
            sliderKey: sliderKey,
            value: displayedValue,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel(displayedValue),
            semanticFormatterCallback: valueLabel,
            onChanged: onChanged,
            onChangeEnd: (_) => (onChangeEnd ?? _finishTypographyChange)(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypographyPreview({
    required String title,
    required String sample,
    required TextStyle style,
    TextStyle? secondaryStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppState.currentScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _settingSubtitleStyle()),
              const SizedBox(height: 8),
              Text(
                sample,
                key: ValueKey('preview_$title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
              if (secondaryStyle != null) ...[
                const SizedBox(height: 2),
                Text('歌手名称', style: secondaryStyle),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<DropdownMenuEntry<MD3Shape>> _shapeEntries() => const [
    DropdownMenuEntry(
      value: MD3Shape.circle,
      label: SettingsLabels.shapeCircle,
    ),
    DropdownMenuEntry(
      value: MD3Shape.stadium,
      label: SettingsLabels.shapeStadium,
    ),
    DropdownMenuEntry(
      value: MD3Shape.roundedExtraSmall,
      label: SettingsLabels.shapeExtraSmall,
    ),
    DropdownMenuEntry(
      value: MD3Shape.roundedSmall,
      label: SettingsLabels.shapeSmall,
    ),
    DropdownMenuEntry(
      value: MD3Shape.roundedMedium,
      label: SettingsLabels.shapeMedium,
    ),
    DropdownMenuEntry(
      value: MD3Shape.roundedLarge,
      label: SettingsLabels.shapeLarge,
    ),
    DropdownMenuEntry(
      value: MD3Shape.roundedExtraLarge,
      label: SettingsLabels.shapeExtraLarge,
    ),
  ];

  List<DropdownMenuEntry<SpectrumMode>> _spectrumEntries() => const [
    DropdownMenuEntry(
      value: SpectrumMode.off,
      label: SettingsLabels.spectrumOff,
    ),
    DropdownMenuEntry(
      value: SpectrumMode.bars,
      label: SettingsLabels.spectrumBars,
    ),
    DropdownMenuEntry(
      value: SpectrumMode.mirror,
      label: SettingsLabels.spectrumMirror,
    ),
    DropdownMenuEntry(
      value: SpectrumMode.waveform,
      label: SettingsLabels.spectrumWaveform,
    ),
  ];

  Widget _buildLocalLyricsFolderRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SettingsLabels.localLyricsDirectory,
                  style: _settingTitleStyle(),
                ),
                Text(
                  AppState.localLyricsDirectory.isEmpty
                      ? SettingsDescriptions.localLyricsEmpty
                      : AppState.localLyricsDirectory,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _settingSubtitleStyle(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () async {
              try {
                final path = await FilePicker.getDirectoryPath();
                if (path == null || !mounted) return;
                setState(() => AppState.setLocalLyricsDirectory(path));
                widget.onVisualChanged();
              } catch (_) {}
            },
            child: const Text('选择'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistFileRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(SettingsLabels.playlistFile, style: _settingTitleStyle()),
                Text(
                  AppState.playlistFilePath.isEmpty
                      ? SettingsDescriptions.playlistFileEmpty
                      : AppState.playlistFilePath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _settingSubtitleStyle(),
                ),
              ],
            ),
          ),
          if (AppState.playlistFilePath.isNotEmpty)
            IconButton(
              tooltip: '重新读取播放列表',
              onPressed: () => AppState.refreshQueue(force: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (AppState.playlistFilePath.isNotEmpty)
            IconButton(
              tooltip: '移除播放列表',
              onPressed: () {
                setState(() {
                  AppState.playlistFilePath = '';
                  AppState.showNextUp = false;
                });
                AppState.refreshQueue(force: true);
                widget.onLayoutChanged();
              },
              icon: const Icon(Icons.close_rounded),
            ),
          FilledButton.tonal(
            onPressed: _choosePlaylistFile,
            child: const Text('选择'),
          ),
        ],
      ),
    );
  }

  String get _displayQueueProviderId {
    if (AppState.selectedQueueProviderId.isNotEmpty) {
      return AppState.selectedQueueProviderId;
    }
    if (AppState.qqPlaylistLink.isNotEmpty &&
        (AppState.currentPlatformTrack == null ||
            AppState.currentPlatformTrack?.platform == MusicPlatform.qqMusic)) {
      return 'qqMusicPlaylist';
    }
    if (AppState.neteasePlaylistLink.isNotEmpty) return 'neteasePlaylist';
    if (AppState.playlistFilePath.isNotEmpty) return 'localPlaylist';
    return 'qqMusicPlaylist';
  }

  Widget _buildPlaylistSourceSelector() => KeyedSubtree(
    key: const ValueKey('playlist_source_selector'),
    child: _buildDropdownRow<String>(
      SettingsLabels.playlistSource,
      null,
      _displayQueueProviderId,
      (value) {
        setState(() => AppState.selectedQueueProviderId = value);
        AppState.refreshQueue();
        widget.onVisualChanged();
      },
      const [
        DropdownMenuEntry(value: 'qqMusicPlaylist', label: 'QQ 音乐'),
        DropdownMenuEntry(value: 'neteasePlaylist', label: '网易云音乐'),
        DropdownMenuEntry(value: 'localPlaylist', label: '本地歌单'),
      ],
    ),
  );

  Widget _buildSelectedPlaylistRow() {
    final id = _displayQueueProviderId;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
      curve: AppState.layoutSwitchCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: IgnorePointer(
            ignoring: child.key != ValueKey(id),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(id),
          child: switch (id) {
            'neteasePlaylist' => _buildNeteasePlaylistRow(),
            'localPlaylist' => _buildPlaylistFileRow(),
            _ => _buildQqPlaylistRow(),
          },
        ),
      ),
    );
  }

  Future<void> _editNeteasePlaylist() async {
    String input = AppState.neteasePlaylistLink;
    String? error;
    final id = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text(SettingsLabels.neteasePlaylist),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('仅支持公开歌单链接或数字 ID，不读取账号。预告按歌单顺序推算，不代表播放器实际队列。'),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: input,
                  autofocus: true,
                  onChanged: (value) => input = value,
                  decoration: InputDecoration(
                    labelText: SettingsLabels.qqPlaylistLink,
                    hintText: 'https://music.163.com/#/playlist?id=…',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final id = parseNeteasePlaylistId(input);
                if (id == null) {
                  update(() => error = '请粘贴网易云公开歌单链接或数字 ID');
                  return;
                }
                Navigator.pop(context, id);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || id == null) return;
    setState(() {
      AppState.neteasePlaylistLink = id;
      AppState.selectedQueueProviderId = 'neteasePlaylist';
      AppState.showNextUp = true;
    });
    AppState.refreshQueue(force: true);
    widget.onLayoutChanged();
  }

  Widget _buildNeteasePlaylistRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                SettingsLabels.neteasePlaylist,
                key: const ValueKey('netease_playlist_title'),
                style: _settingTitleStyle(),
              ),
              Text(
                AppState.neteasePlaylistLink.isEmpty
                    ? SettingsDescriptions.neteasePlaylist
                    : '已连接歌单 ${AppState.neteasePlaylistLink}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _settingSubtitleStyle(),
              ),
            ],
          ),
        ),
        if (AppState.neteasePlaylistLink.isNotEmpty) ...[
          IconButton(
            tooltip: '重新读取网易云歌单',
            onPressed: () => AppState.refreshQueue(force: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '移除网易云歌单',
            onPressed: () {
              setState(() {
                AppState.neteasePlaylistLink = '';
              });
              AppState.refreshQueue(force: true);
              widget.onLayoutChanged();
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
        FilledButton.tonal(
          key: const ValueKey('netease_playlist_connect'),
          onPressed: _editNeteasePlaylist,
          child: Text(AppState.neteasePlaylistLink.isEmpty ? '连接' : '修改'),
        ),
      ],
    ),
  );

  Widget _buildQqPlaylistRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SettingsLabels.qqPlaylist,
                  key: const ValueKey('qq_playlist_title'),
                  style: _settingTitleStyle(),
                ),
                Text(
                  AppState.qqPlaylistLink.isEmpty
                      ? SettingsDescriptions.qqPlaylistEmpty
                      : SettingsDescriptions.qqPlaylistConnected(
                          parseQqPlaylistId(AppState.qqPlaylistLink) ?? '',
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _settingSubtitleStyle(),
                ),
              ],
            ),
          ),
          if (AppState.qqPlaylistLink.isNotEmpty)
            IconButton(
              tooltip: '重新读取 QQ 音乐歌单',
              onPressed: () => AppState.refreshQueue(force: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (AppState.qqPlaylistLink.isNotEmpty)
            IconButton(
              tooltip: '移除 QQ 音乐歌单',
              onPressed: () {
                setState(() {
                  AppState.qqPlaylistLink = '';
                });
                AppState.refreshQueue(force: true);
                widget.onLayoutChanged();
              },
              icon: const Icon(Icons.close_rounded),
            ),
          FilledButton.tonal(
            key: const ValueKey('qq_playlist_connect'),
            onPressed: _editQqPlaylist,
            child: Text(AppState.qqPlaylistLink.isEmpty ? '连接' : '修改'),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuEntry<MD3ProgressStyle>> _progressStyleEntries() => const [
    DropdownMenuEntry(
      value: MD3ProgressStyle.linear,
      label: SettingsLabels.progressLinear,
    ),
    DropdownMenuEntry(
      value: MD3ProgressStyle.pill,
      label: SettingsLabels.progressPill,
    ),
    DropdownMenuEntry(
      value: MD3ProgressStyle.segmented,
      label: SettingsLabels.progressSegmented,
    ),
  ];

  List<DropdownMenuEntry<TrackTextTransitionStyle>>
  _trackTextTransitionEntries() => const [
    DropdownMenuEntry(
      value: TrackTextTransitionStyle.particles,
      label: SettingsLabels.trackTextParticles,
    ),
    DropdownMenuEntry(
      value: TrackTextTransitionStyle.fade,
      label: SettingsLabels.trackTextFade,
    ),
    DropdownMenuEntry(
      value: TrackTextTransitionStyle.rise,
      label: SettingsLabels.trackTextRise,
    ),
    DropdownMenuEntry(
      value: TrackTextTransitionStyle.sideways,
      label: SettingsLabels.trackTextSideways,
    ),
    DropdownMenuEntry(
      value: TrackTextTransitionStyle.zoom,
      label: SettingsLabels.trackTextZoom,
    ),
    DropdownMenuEntry(
      value: TrackTextTransitionStyle.descend,
      label: SettingsLabels.trackTextDescend,
    ),
    DropdownMenuEntry(
      value: TrackTextTransitionStyle.settle,
      label: SettingsLabels.trackTextSettle,
    ),
    DropdownMenuEntry(
      value: TrackTextTransitionStyle.sweep,
      label: SettingsLabels.trackTextSweep,
    ),
  ];

  List<DropdownMenuEntry<TrackTextExitStyle>> _trackTextExitEntries() => const [
    DropdownMenuEntry(
      value: TrackTextExitStyle.fade,
      label: SettingsLabels.trackTextExitFade,
    ),
    DropdownMenuEntry(
      value: TrackTextExitStyle.rise,
      label: SettingsLabels.trackTextExitRise,
    ),
    DropdownMenuEntry(
      value: TrackTextExitStyle.descend,
      label: SettingsLabels.trackTextExitDescend,
    ),
    DropdownMenuEntry(
      value: TrackTextExitStyle.sideways,
      label: SettingsLabels.trackTextExitSideways,
    ),
    DropdownMenuEntry(
      value: TrackTextExitStyle.shrink,
      label: SettingsLabels.trackTextExitShrink,
    ),
  ];

  List<DropdownMenuEntry<LyricsTransitionStyle>> _lyricsTransitionEntries({
    bool exiting = false,
  }) => [
    for (final style in LyricsTransitionStyle.values)
      DropdownMenuEntry(
        value: style,
        label: switch (style) {
          LyricsTransitionStyle.fade =>
            exiting
                ? SettingsLabels.lyricsFadeOut
                : SettingsLabels.lyricsFadeIn,
          LyricsTransitionStyle.rise =>
            exiting
                ? SettingsLabels.lyricsRiseOut
                : SettingsLabels.lyricsRiseIn,
          LyricsTransitionStyle.descend =>
            exiting
                ? SettingsLabels.lyricsDescendOut
                : SettingsLabels.lyricsDescendIn,
          LyricsTransitionStyle.sideways =>
            exiting
                ? SettingsLabels.lyricsSidewaysOut
                : SettingsLabels.lyricsSidewaysIn,
          LyricsTransitionStyle.zoom =>
            exiting
                ? SettingsLabels.lyricsZoomOut
                : SettingsLabels.lyricsZoomIn,
          LyricsTransitionStyle.none =>
            exiting
                ? SettingsLabels.lyricsNoExitAnimation
                : SettingsLabels.lyricsNoEnterAnimation,
          LyricsTransitionStyle.film =>
            exiting
                ? SettingsLabels.lyricsFilmOut
                : SettingsLabels.lyricsFilmIn,
          LyricsTransitionStyle.flip =>
            exiting
                ? SettingsLabels.lyricsFlipOut
                : SettingsLabels.lyricsFlipIn,
          LyricsTransitionStyle.settle =>
            exiting
                ? SettingsLabels.lyricsSettleOut
                : SettingsLabels.lyricsSettleIn,
          LyricsTransitionStyle.wipe =>
            exiting
                ? SettingsLabels.lyricsWipeOut
                : SettingsLabels.lyricsWipeIn,
        },
      ),
  ];

  List<DropdownMenuEntry<CoverTransitionStyle>> _coverTransitionEntries() =>
      const [
        DropdownMenuEntry(
          value: CoverTransitionStyle.softSlide,
          label: SettingsLabels.coverSoftSlide,
        ),
        DropdownMenuEntry(
          value: CoverTransitionStyle.fade,
          label: SettingsLabels.coverFade,
        ),
        DropdownMenuEntry(
          value: CoverTransitionStyle.filmVertical,
          label: SettingsLabels.coverFilmVertical,
        ),
        DropdownMenuEntry(
          value: CoverTransitionStyle.filmHorizontal,
          label: SettingsLabels.coverFilmHorizontal,
        ),
        DropdownMenuEntry(
          value: CoverTransitionStyle.flipHorizontal,
          label: SettingsLabels.coverFlipHorizontal,
        ),
        DropdownMenuEntry(
          value: CoverTransitionStyle.flipVertical,
          label: SettingsLabels.coverFlipVertical,
        ),
        DropdownMenuEntry(
          value: CoverTransitionStyle.stack,
          label: SettingsLabels.coverStack,
        ),
        DropdownMenuEntry(
          value: CoverTransitionStyle.none,
          label: SettingsLabels.coverNoAnimation,
        ),
      ];

  List<DropdownMenuEntry<ComponentSizeMode>> _componentSizeEntries() => const [
    DropdownMenuEntry(
      value: ComponentSizeMode.small,
      label: SettingsLabels.componentSmall,
    ),
    DropdownMenuEntry(
      value: ComponentSizeMode.standard,
      label: SettingsLabels.componentStandard,
    ),
    DropdownMenuEntry(
      value: ComponentSizeMode.large,
      label: SettingsLabels.componentLarge,
    ),
    DropdownMenuEntry(
      value: ComponentSizeMode.custom,
      label: SettingsLabels.componentCustom,
    ),
  ];

  Widget _buildOptionalSetting({required bool visible, required Widget child}) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubicEmphasized,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: AnimatedOpacity(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          opacity: visible ? 1.0 : 0.0,
          child: visible ? child : const SizedBox(width: double.infinity),
        ),
      ),
    );
  }

  TextStyle _settingTitleStyle({bool disabled = false}) {
    return (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
        .copyWith(
          color: AppState.currentScheme.onSurface.withValues(
            alpha: disabled ? 0.38 : 1.0,
          ),
          fontFamilyFallback: AppState.textFontFallback,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.0,
          height: 1.25,
        );
  }

  TextStyle _settingSubtitleStyle({bool disabled = false}) {
    return (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
        .copyWith(
          color: AppState.currentScheme.onSurfaceVariant.withValues(
            alpha: disabled ? 0.38 : 1.0,
          ),
          fontFamilyFallback: AppState.textFontFallback,
          letterSpacing: 0.0,
          height: 1.35,
        );
  }

  Widget _buildDropdownRow<T>(
    String title,
    String? subtitle,
    T current,
    ValueChanged<T> onChanged,
    List<DropdownMenuEntry<T>> items, {
    Widget? actionButton,
    VoidCallback? onReset,
    bool fullWidth = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = (constraints.maxWidth - 36).clamp(
          0.0,
          double.infinity,
        );
        final bool stacked =
            fullWidth || AppState.isVertical || constraints.maxWidth < 520;
        final Widget? resetButton = onReset == null
            ? null
            : IconButton(
                key: ValueKey('reset_${title}_font'),
                tooltip: '重置$title',
                icon: const Icon(Icons.restart_alt_rounded),
                onPressed: onReset,
              );
        final double actionWidth =
            (actionButton == null ? 0 : 48) + (resetButton == null ? 0 : 48);
        final double controlWidth = stacked
            ? (availableWidth - actionWidth).clamp(0.0, double.infinity)
            : (availableWidth * 0.44).clamp(180.0, 300.0);
        final Widget titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _settingTitleStyle()),
            if (subtitle != null && subtitle.isNotEmpty)
              Text(subtitle, style: _settingSubtitleStyle()),
          ],
        );
        final Widget control = Md3AnchoredSelect<T>(
          key: ValueKey<String>('dropdown_${T.toString()}_$current'),
          value: current,
          width: controlWidth,
          entries: items,
          onSelected: onChanged,
        );

        if (stacked) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 8),
                Row(
                  children: [
                    ?actionButton,
                    ?resetButton,
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: control,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: titleBlock),
              ?actionButton,
              ?resetButton,
              const SizedBox(width: 8),
              control,
            ],
          ),
        );
      },
    );
  }

  Widget _buildSwitchRow(
    String title,
    String? subtitle,
    bool value,
    ValueChanged<bool> onChanged, {
    bool disabled = false,
    VoidCallback? onReset,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _settingTitleStyle(disabled: disabled)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: _settingSubtitleStyle(disabled: disabled),
                  ),
              ],
            ),
          ),
          if (onReset != null)
            IconButton(
              key: ValueKey('reset_${title}_switch'),
              tooltip: '重置$title',
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: onReset,
            ),
          Switch(
            value: value,
            onChanged: disabled ? null : onChanged,
            activeThumbColor: AppState.currentScheme.onPrimary,
            activeTrackColor: AppState.currentScheme.primary,
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedRow<T>(
    String title,
    String? subtitle,
    List<ButtonSegment<T>> segments,
    T current,
    ValueChanged<T> onSelected, {
    bool disabled = false,
  }) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _settingTitleStyle(disabled: disabled)),
        if (subtitle != null && subtitle.isNotEmpty)
          Text(subtitle, style: _settingSubtitleStyle(disabled: disabled)),
      ],
    );

    final Widget control = IgnorePointer(
      ignoring: disabled,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: SegmentedButton<T>(
          segments: segments,
          selected: <T>{current},
          onSelectionChanged: (Set<T> newSelection) =>
              onSelected(newSelection.first),
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 300),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: const WidgetStatePropertyAll(BorderSide.none),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? AppState.currentScheme.secondaryContainer
                  : AppState.currentScheme.surfaceContainerHighest.withValues(
                      alpha: 0.56,
                    );
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? AppState.currentScheme.onSecondaryContainer
                  : AppState.currentScheme.onSurfaceVariant;
            }),
            textStyle: WidgetStatePropertyAll(
              Theme.of(context).textTheme.labelLarge?.copyWith(
                fontFamilyFallback: AppState.textFontFallback,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (AppState.isVertical || constraints.maxWidth < 520) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: control,
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: titleBlock),
              control,
            ],
          ),
        );
      },
    );
  }
}
