import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/app_state.dart';
import '../../core/media_provider.dart';
import '../../core/music_source_service.dart';
import '../../core/qq_music_playlist_queue_provider.dart';
import 'md3_anchored_select.dart';
import 'settings_descriptions.dart';
import 'settings_section_navigation.dart';

enum _SettingsSection { window, appearance, playback, lyrics, typography }

extension on _SettingsSection {
  String get label => switch (this) {
    _SettingsSection.window => '窗口',
    _SettingsSection.appearance => '外观',
    _SettingsSection.playback => '播放',
    _SettingsSection.lyrics => '歌词',
    _SettingsSection.typography => '字体',
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

  void _updateTypography(VoidCallback change) {
    setState(change);
    AppState.notifyTypographyChanged();
    _typographySaveTimer?.cancel();
    _typographySaveTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(AppState.saveSettings()),
    );
  }

  void _finishTypographyChange() {
    _typographySaveTimer?.cancel();
    _typographySaveTimer = null;
    unawaited(AppState.saveSettings());
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
          title: const Text('QQ 音乐歌单'),
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
                    labelText: '歌单链接或 ID',
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
      AppState.showNextUp = true;
    });
    AppState.refreshQueue(force: true);
    widget.onLayoutChanged();
  }

  List<DropdownMenuEntry<String>> _sourceEntries() {
    final selected = AppState.selectedSourceAppId;
    return [
      const DropdownMenuEntry(value: '', label: '自动 · 系统当前播放器'),
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
    _sourceRequestSerial++;
    _sectionEntryController.dispose();
    if (_typographySaveTimer?.isActive == true) _finishTypographyChange();
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
  }

  Widget _buildSectionNavigation() {
    final sections = _SettingsSection.values;
    return SettingsSectionNavigation(
      destinations: [
        for (final section in sections)
          SettingsSectionDestination(section.name, section.label, section.icon),
      ],
      selectedIndex: _selectedSection.index,
      shape: AppState.settingsNavigationShape,
      onSelected: (index) => _selectSection(sections[index]),
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
                Text(
                  "偏好设置",
                  style: textTheme.headlineSmall?.copyWith(
                    color: headingColor,
                    shadows: headingShadows,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  SettingsDescriptions.overview,
                  style: textTheme.bodySmall?.copyWith(
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
            child: ScrollConfiguration(
              key: ValueKey(_selectedSection),
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40, right: 8),
                children: [
                  if (_selectedSection == _SettingsSection.window)
                    _buildCategoryCard(
                      title: "窗口与布局",
                      icon: Icons.dashboard_customize_rounded,
                      children: [
                        _buildSegmentedRow(
                          "布局形态",
                          null,
                          [
                            const ButtonSegment(
                              value: WidgetLayout.horizontal,
                              icon: Icon(Icons.view_stream_rounded),
                              label: Text("横版"),
                            ),
                            const ButtonSegment(
                              value: WidgetLayout.vertical,
                              icon: Icon(Icons.view_carousel_rounded),
                              label: Text("竖版"),
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
                          "组件大小",
                          AppState.isCustomComponentSize
                              ? SettingsDescriptions.customComponentSize(
                                  (AppState.customComponentScale * 100).round(),
                                )
                              : SettingsDescriptions.componentSize,
                          AppState.componentSizeMode,
                          (val) {
                            if (val == ComponentSizeMode.custom &&
                                !AppState.isCustomComponentSize) {
                              AppState.customComponentScale =
                                  AppState.componentScale;
                            }
                            setState(() => AppState.componentSizeMode = val);
                            widget.onLayoutChanged();
                          },
                          _componentSizeEntries(),
                        ),
                        _buildDivider(),
                        _buildSwitchRow(
                          "总在最前",
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
                            "鼠标穿透",
                            SettingsDescriptions.mousePassthrough,
                            AppState.isMousePassthrough,
                            (val) {
                              setState(() => AppState.isMousePassthrough = val);
                              widget.onWindowBehaviorChanged();
                            },
                          ),
                        ],
                      ],
                    ),

                  if (_selectedSection == _SettingsSection.appearance)
                    _buildCategoryCard(
                      title: "主题与颜色",
                      icon: Icons.palette_rounded,
                      children: [
                        _buildSegmentedRow(
                          "色彩主题",
                          SettingsDescriptions.colorTheme,
                          [
                            const ButtonSegment(
                              value: DynamicSchemeVariant.tonalSpot,
                              label: Text("柔和"),
                            ),
                            const ButtonSegment(
                              value: DynamicSchemeVariant.vibrant,
                              label: Text("艳丽"),
                            ),
                            const ButtonSegment(
                              value: DynamicSchemeVariant.fidelity,
                              label: Text("真实"),
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
                          "深色模式",
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
                          '设置导航形状',
                          SettingsDescriptions.settingsNavigationShape,
                          AppState.settingsNavigationShape,
                          (value) {
                            setState(
                              () => AppState.settingsNavigationShape = value,
                            );
                            widget.onVisualChanged();
                          },
                          const [
                            DropdownMenuEntry(
                              value: MD3Shape.stadium,
                              label: '胶囊形',
                            ),
                            DropdownMenuEntry(
                              value: MD3Shape.roundedExtraSmall,
                              label: '极小圆角 · 4',
                            ),
                            DropdownMenuEntry(
                              value: MD3Shape.roundedSmall,
                              label: '小圆角 · 8',
                            ),
                            DropdownMenuEntry(
                              value: MD3Shape.roundedMedium,
                              label: '中圆角 · 12',
                            ),
                            DropdownMenuEntry(
                              value: MD3Shape.roundedLarge,
                              label: '大圆角 · 20',
                            ),
                            DropdownMenuEntry(
                              value: MD3Shape.roundedExtraLarge,
                              label: '超大圆角 · 28',
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
                                "纯黑底色 (OLED)",
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
                      title: "背景与交互",
                      icon: Icons.animation_rounded,
                      children: [
                        _buildSwitchRow(
                          "流光背景",
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
                                "背景渲染模式",
                                SettingsDescriptions.glowMode,
                                [
                                  const ButtonSegment(
                                    value: GlowMode.waterfall,
                                    label: Text("瀑布"),
                                  ),
                                  const ButtonSegment(
                                    value: GlowMode.wallpaper,
                                    label: Text("全屏"),
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
                          "3D 悬浮交互",
                          SettingsDescriptions.coverParallax,
                          AppState.enable3DCover,
                          (val) {
                            setState(() => AppState.enable3DCover = val);
                            widget.onVisualChanged();
                          },
                        ),
                        if (_hasTimeline) _buildDivider(),
                        if (_hasTimeline)
                          _buildSwitchRow(
                            "进度自动反色",
                            SettingsDescriptions.progressAutoContrast,
                            AppState.enableProgressAutoContrast,
                            (val) {
                              setState(
                                () => AppState.enableProgressAutoContrast = val,
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
                            "音乐频谱",
                            SettingsDescriptions.spectrum,
                            AppState.spectrumMode,
                            (val) {
                              final bool visibilityChanged =
                                  (AppState.spectrumMode == SpectrumMode.off) !=
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
                      ],
                    ),

                  if (_selectedSection == _SettingsSection.playback)
                    _buildCategoryCard(
                      title: "播放显示与控件",
                      icon: Icons.widgets_rounded,
                      children: [
                        _buildDropdownRow<String>(
                          '采集程序',
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
                            onPressed: _sourcesLoading ? null : _refreshSources,
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
                          "显示播放控制",
                          SettingsDescriptions.playbackControls,
                          AppState.showPlaybackControls,
                          (val) {
                            setState(() => AppState.showPlaybackControls = val);
                            widget.onLayoutChanged();
                          },
                        ),
                        _buildDivider(),
                        if (MediaCapability.supports(
                          AppState.mediaCapabilities,
                          MediaCapability.timeline,
                        ))
                          _buildDropdownRow<MD3ProgressStyle>(
                            "进度条样式",
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
                          _buildDivider(),
                        _buildOptionalSetting(
                          visible: AppState.showPlaybackControls,
                          child: Column(
                            children: [
                              _buildDropdownRow<MD3Shape>(
                                "播放按钮",
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
                                "上一首按钮",
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
                                "下一首按钮",
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
                      title: '下一首预告',
                      icon: Icons.queue_music_rounded,
                      children: [
                        _buildSwitchRow(
                          '显示下一首预告',
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
                              _buildPlaylistFileRow(),
                              _buildDivider(),
                              _buildQqPlaylistRow(),
                              _buildDivider(),
                              _buildDropdownRow<int>(
                                '预告提前量',
                                SettingsDescriptions.nextUpLead,
                                AppState.nextUpLeadSeconds,
                                (value) {
                                  setState(
                                    () => AppState.nextUpLeadSeconds = value,
                                  );
                                  AppState.playbackRevision.value++;
                                  widget.onVisualChanged();
                                },
                                const [
                                  DropdownMenuEntry(value: 10, label: '10 秒'),
                                  DropdownMenuEntry(value: 20, label: '20 秒'),
                                  DropdownMenuEntry(value: 30, label: '30 秒'),
                                  DropdownMenuEntry(value: 45, label: '45 秒'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                  if (_selectedSection == _SettingsSection.lyrics)
                    _buildCategoryCard(
                      title: '歌词',
                      icon: Icons.lyrics_rounded,
                      children: [
                        _buildSwitchRow(
                          '显示歌词',
                          SettingsDescriptions.showLyrics,
                          AppState.showLyrics,
                          (value) {
                            setState(() => AppState.showLyrics = value);
                            AppState.refreshLyrics();
                            widget.onLayoutChanged();
                          },
                        ),
                        _buildOptionalSetting(
                          visible: AppState.showLyrics,
                          child: Column(
                            children: [
                              _buildDivider(),
                              _buildDropdownRow<LyricsProviderChoice>(
                                '歌词提供商',
                                switch (AppState.lyricsProviderChoice) {
                                  LyricsProviderChoice.lrclib =>
                                    SettingsDescriptions.lyricsProviderLrclib,
                                  LyricsProviderChoice.localLrc =>
                                    SettingsDescriptions.lyricsProviderLocal,
                                  LyricsProviderChoice.qqMusic =>
                                    SettingsDescriptions.lyricsProviderQqMusic,
                                },
                                AppState.lyricsProviderChoice,
                                (value) {
                                  setState(
                                    () => AppState.lyricsProviderChoice = value,
                                  );
                                  AppState.refreshLyrics();
                                  widget.onVisualChanged();
                                },
                                const [
                                  DropdownMenuEntry(
                                    value: LyricsProviderChoice.lrclib,
                                    label: 'LRCLIB · 在线',
                                  ),
                                  DropdownMenuEntry(
                                    value: LyricsProviderChoice.localLrc,
                                    label: '本地 LRC',
                                  ),
                                  DropdownMenuEntry(
                                    value: LyricsProviderChoice.qqMusic,
                                    label: 'QQ 音乐 · 实验性',
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
                                  ],
                                ),
                              ),
                              _buildDivider(),
                              _buildSwitchRow(
                                '进出动画使用同一预设',
                                SettingsDescriptions.lyricsLinkAnimations,
                                AppState.lyricsAnimationsLinked,
                                (value) {
                                  setState(
                                    () =>
                                        AppState.lyricsAnimationsLinked = value,
                                  );
                                  AppState.notifyLyricsVisualChanged();
                                  widget.onVisualChanged();
                                },
                              ),
                              _buildDivider(),
                              _buildDropdownRow<LyricsTransitionStyle>(
                                AppState.lyricsAnimationsLinked
                                    ? '歌词切换动画'
                                    : '歌词进入动画',
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
                                    _buildDropdownRow<LyricsTransitionStyle>(
                                      '上一句退出动画',
                                      SettingsDescriptions.lyricsExitTransition,
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
                                      _lyricsTransitionEntries(exiting: true),
                                    ),
                                  ],
                                ),
                              ),
                              _buildDivider(),
                              _buildSwitchRow(
                                '跟随主题字体',
                                SettingsDescriptions.lyricsUseThemeFont,
                                AppState.lyricsUseThemeFont,
                                (value) {
                                  _updateTypography(
                                    () => AppState.lyricsUseThemeFont = value,
                                  );
                                },
                                onReset: AppState.lyricsUseThemeFont
                                    ? null
                                    : () {
                                        _updateTypography(
                                          () => AppState.lyricsUseThemeFont =
                                              true,
                                        );
                                        _finishTypographyChange();
                                      },
                              ),
                              _buildOptionalSetting(
                                visible: !AppState.lyricsUseThemeFont,
                                child: _buildDropdownRow<String>(
                                  '歌词字体',
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
                                              ? '系统默认'
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
                                            () => AppState.lyricsFontFamily =
                                                AppState.defaultFontFamily,
                                          );
                                          _finishTypographyChange();
                                        },
                                ),
                              ),
                              _buildDivider(),
                              _buildContinuousSliderRow(
                                title: '歌词字重',
                                subtitle: SettingsDescriptions.lyricsWeight,
                                value: AppState.lyricsWeightValue,
                                min: 100,
                                max: 900,
                                valueLabel: (value) => 'W${value.round()}',
                                sliderKey: const ValueKey(
                                  'lyrics_weight_slider',
                                ),
                                resetValue: AppState.defaultLyricsWeightValue,
                                onChanged: (value) => _updateTypography(
                                  () => AppState.lyricsWeightValue = value,
                                ),
                              ),
                              _buildDivider(),
                              _buildContinuousSliderRow(
                                title: '歌词字号',
                                subtitle: SettingsDescriptions.lyricsSize,
                                value: AppState.lyricsFontSize,
                                min: 12,
                                max: 17,
                                valueLabel: (value) =>
                                    '${value.toStringAsFixed(1)} px',
                                sliderKey: const ValueKey('lyrics_size_slider'),
                                resetValue: AppState.defaultLyricsFontSize,
                                onChanged: (value) => _updateTypography(
                                  () => AppState.lyricsFontSize = value,
                                ),
                              ),
                              _buildTypographyPreview(
                                title: '歌词实时预览',
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
                      title: "字体与排版",
                      icon: Icons.text_fields_rounded,
                      children: [
                        _buildDropdownRow<String>(
                          "全局文本字体",
                          SettingsDescriptions.globalFont,
                          AppState.currentFontFamily,
                          (val) {
                            setState(() => AppState.currentFontFamily = val);
                            widget.onVisualChanged();
                          },
                          AppState.loadedSystemFonts
                              .map(
                                (fontName) => DropdownMenuEntry<String>(
                                  value: fontName,
                                  label: fontName,
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
                          title: '歌曲名字重',
                          subtitle: SettingsDescriptions.titleWeight,
                          value: AppState.titleWeightValue,
                          min: 100,
                          max: 900,
                          valueLabel: (value) => 'W${value.round()}',
                          sliderKey: const ValueKey('title_weight_slider'),
                          resetValue: AppState.defaultTitleWeightValue,
                          onChanged: (value) => _updateTypography(
                            () => AppState.titleWeightValue = value,
                          ),
                        ),
                        _buildDivider(),
                        _buildContinuousSliderRow(
                          title: '歌手名字重',
                          subtitle: SettingsDescriptions.artistWeight,
                          value: AppState.artistWeightValue,
                          min: 100,
                          max: 900,
                          valueLabel: (value) => 'W${value.round()}',
                          sliderKey: const ValueKey('artist_weight_slider'),
                          resetValue: AppState.defaultArtistWeightValue,
                          onChanged: (value) => _updateTypography(
                            () => AppState.artistWeightValue = value,
                          ),
                        ),
                        _buildTypographyPreview(
                          title: '播放信息实时预览',
                          sample: '歌曲名称',
                          style: TextStyle(
                            fontFamily:
                                AppState.currentFontFamily == 'System Default'
                                ? null
                                : AppState.currentFontFamily,
                            fontFamilyFallback: AppState.textFontFallback,
                            color: AppState.currentScheme.onSurface,
                            fontWeight: AppState.titleWeight,
                            fontVariations: AppState.variationsFor(
                              AppState.titleWeightValue,
                            ),
                          ),
                          secondaryStyle: TextStyle(
                            fontFamily:
                                AppState.currentFontFamily == 'System Default'
                                ? null
                                : AppState.currentFontFamily,
                            fontFamilyFallback: AppState.textFontFallback,
                            color: AppState.currentScheme.onSurfaceVariant,
                            fontWeight: AppState.artistWeight,
                            fontVariations: AppState.variationsFor(
                              AppState.artistWeightValue,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
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
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      color: headingOverArtwork
                          ? Colors.white
                          : AppState.currentScheme.onSurface,
                      shadows: headingOverArtwork
                          ? [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.38),
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
            child: ClipRRect(
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
              Text(
                valueLabel(displayedValue),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppState.currentScheme.primary,
                ),
              ),
              if ((value - resetValue).abs() > 0.001)
                IconButton(
                  key: ValueKey('reset_${title}_slider'),
                  tooltip: '重置$title',
                  icon: const Icon(Icons.restart_alt_rounded),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    onChanged(resetValue);
                    _finishTypographyChange();
                  },
                ),
            ],
          ),
          Text(subtitle, style: _settingSubtitleStyle()),
          Slider(
            key: sliderKey,
            value: displayedValue,
            min: min,
            max: max,
            label: valueLabel(displayedValue),
            semanticFormatterCallback: valueLabel,
            onChanged: onChanged,
            onChangeEnd: (_) => _finishTypographyChange(),
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
    DropdownMenuEntry(value: MD3Shape.circle, label: '圆形'),
    DropdownMenuEntry(value: MD3Shape.stadium, label: '胶囊形'),
    DropdownMenuEntry(value: MD3Shape.roundedExtraSmall, label: '极小圆角 · 4'),
    DropdownMenuEntry(value: MD3Shape.roundedSmall, label: '小圆角 · 8'),
    DropdownMenuEntry(value: MD3Shape.roundedMedium, label: '中圆角 · 12'),
    DropdownMenuEntry(value: MD3Shape.roundedLarge, label: '大圆角 · 20'),
    DropdownMenuEntry(value: MD3Shape.roundedExtraLarge, label: '超大圆角 · 28'),
  ];

  List<DropdownMenuEntry<SpectrumMode>> _spectrumEntries() => const [
    DropdownMenuEntry(value: SpectrumMode.off, label: '关闭'),
    DropdownMenuEntry(value: SpectrumMode.bars, label: '均衡柱状'),
    DropdownMenuEntry(value: SpectrumMode.mirror, label: '镜像频谱'),
    DropdownMenuEntry(value: SpectrumMode.waveform, label: '波形线条'),
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
                Text('本地歌词目录', style: _settingTitleStyle()),
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
                Text('导入播放列表', style: _settingTitleStyle()),
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

  Widget _buildQqPlaylistRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('QQ 音乐歌单', style: _settingTitleStyle()),
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
                setState(() => AppState.qqPlaylistLink = '');
                AppState.refreshQueue(force: true);
                widget.onLayoutChanged();
              },
              icon: const Icon(Icons.close_rounded),
            ),
          FilledButton.tonal(
            onPressed: _editQqPlaylist,
            child: Text(AppState.qqPlaylistLink.isEmpty ? '连接' : '修改'),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuEntry<MD3ProgressStyle>> _progressStyleEntries() => const [
    DropdownMenuEntry(value: MD3ProgressStyle.linear, label: '标准线性 · MD3'),
    DropdownMenuEntry(value: MD3ProgressStyle.pill, label: '圆角胶囊'),
    DropdownMenuEntry(value: MD3ProgressStyle.segmented, label: '动态分段'),
  ];

  List<DropdownMenuEntry<LyricsTransitionStyle>> _lyricsTransitionEntries({
    bool exiting = false,
  }) => exiting
      ? const [
          DropdownMenuEntry(value: LyricsTransitionStyle.fade, label: '柔和淡出'),
          DropdownMenuEntry(value: LyricsTransitionStyle.rise, label: '向上飞出'),
          DropdownMenuEntry(
            value: LyricsTransitionStyle.descend,
            label: '向下飞出',
          ),
          DropdownMenuEntry(
            value: LyricsTransitionStyle.sideways,
            label: '向左滑出',
          ),
          DropdownMenuEntry(value: LyricsTransitionStyle.zoom, label: '放大离开'),
          DropdownMenuEntry(value: LyricsTransitionStyle.none, label: '直接切换'),
        ]
      : const [
          DropdownMenuEntry(value: LyricsTransitionStyle.fade, label: '柔和淡入'),
          DropdownMenuEntry(value: LyricsTransitionStyle.rise, label: '轻轻上浮'),
          DropdownMenuEntry(
            value: LyricsTransitionStyle.descend,
            label: '轻轻落下',
          ),
          DropdownMenuEntry(
            value: LyricsTransitionStyle.sideways,
            label: '侧向滑入',
          ),
          DropdownMenuEntry(value: LyricsTransitionStyle.zoom, label: '微微放大'),
          DropdownMenuEntry(value: LyricsTransitionStyle.none, label: '关闭动画'),
        ];

  List<DropdownMenuEntry<ComponentSizeMode>> _componentSizeEntries() => const [
    DropdownMenuEntry(value: ComponentSizeMode.small, label: '小 · 82%'),
    DropdownMenuEntry(value: ComponentSizeMode.standard, label: '标准 · 100%'),
    DropdownMenuEntry(value: ComponentSizeMode.large, label: '大 · 122%'),
    DropdownMenuEntry(value: ComponentSizeMode.custom, label: '自由缩放'),
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
            alpha: disabled ? 0.38 : 0.88,
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
