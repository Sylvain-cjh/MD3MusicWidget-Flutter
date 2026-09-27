import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/app_state.dart';
import '../../core/media_provider.dart';
import '../../core/music_source_service.dart';
import '../../core/qq_music_playlist_queue_provider.dart';
import 'md3_anchored_select.dart';

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

  const SettingsPanel({
    super.key,
    required this.onThemeChanged,
    required this.onVisualChanged,
    required this.onBackgroundChanged,
    required this.onLayoutChanged,
    required this.onWindowBehaviorChanged,
    required this.isMousePassthroughAvailable,
  });

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late bool _hasTimeline;
  _SettingsSection _selectedSection = _SettingsSection.window;
  int _sectionDirection = 1;
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
                const Text('粘贴公开歌单链接或数字 ID。预告依据歌单顺序，不代表客户端临时播放队列。'),
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
              onPressed: () {
                final trimmed = input.trim();
                if (parseQqPlaylistId(trimmed) == null) {
                  updateDialog(() => error = '请输入有效的 QQ 音乐公开歌单链接或数字 ID');
                  return;
                }
                Navigator.pop(context, trimmed);
              },
              child: const Text('保存'),
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
    if (_typographySaveTimer?.isActive == true) _finishTypographyChange();
    AppState.playbackRevision.removeListener(_handleTimelineAvailability);
    AppState.fontsRevision.removeListener(_handleFontsChanged);
    super.dispose();
  }

  void _selectSection(_SettingsSection section) {
    if (_selectedSection == section) return;
    setState(() {
      _sectionDirection = section.index > _selectedSection.index ? 1 : -1;
      _selectedSection = section;
    });
    if (section == _SettingsSection.playback) unawaited(_refreshSources());
  }

  Widget _buildSectionNavigation() {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final sections = _SettingsSection.values;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 450;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
            child: SizedBox(
              height: compact ? 56 : 48,
              child: Stack(
                children: [
                  AnimatedAlign(
                    key: const ValueKey('settings_section_indicator'),
                    alignment: Alignment(
                      -1 + 2 * _selectedSection.index / (sections.length - 1),
                      0,
                    ),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubicEmphasized,
                    child: FractionallySizedBox(
                      widthFactor: 1 / sections.length,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final section in sections)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: _selectedSection == section,
                            child: InkWell(
                              key: ValueKey('settings_section_${section.name}'),
                              onTap: () => _selectSection(section),
                              child: compact
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(section.icon, size: 17),
                                        const SizedBox(height: 2),
                                        Text(
                                          section.label,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(section.icon, size: 17),
                                        const SizedBox(width: 5),
                                        Text(
                                          section.label,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelMedium,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  "布局、视觉与播放体验",
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
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              layoutBuilder: (currentChild, previousChildren) =>
                  currentChild ?? const SizedBox.shrink(),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0.06 * _sectionDirection, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
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
                            "水平经典 / 垂直拟物",
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
                                ? "边框拖动并锁定比例 · 当前 ${(AppState.customComponentScale * 100).round()}%"
                                : "三种固定尺寸，或锁定比例自由缩放",
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
                            "将挂件置于其他窗口之上",
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
                              "左键托盘图标可立即恢复鼠标交互",
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
                        title: "主题与颜色",
                        icon: Icons.palette_rounded,
                        children: [
                          _buildSegmentedRow(
                            "色彩主题",
                            "提取封面主色的算法",
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
                            "强制使用暗色调UI",
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
                          _buildOptionalSetting(
                            visible:
                                AppState.themeBrightness == Brightness.dark &&
                                !AppState.enableGlow,
                            child: Column(
                              children: [
                                _buildDivider(),
                                _buildSwitchRow(
                                  "纯黑底色 (OLED)",
                                  "提升对比度，适合暗光环境",
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
                            "跟随封面色彩的全局光晕",
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
                                  "瀑布流或全虚化壁纸",
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
                            "封面跟随鼠标产生 3D 偏转",
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
                              "根据流光背景逐像素保持进度与频谱清晰可见",
                              AppState.enableProgressAutoContrast,
                              (val) {
                                setState(
                                  () =>
                                      AppState.enableProgressAutoContrast = val,
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
                              "在播放器底部显示独立的动态频谱控件",
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
                                    ? '自动跟随系统当前播放器'
                                    : '仅显示所选程序；独立音频不可用时不混入系统声音'),
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
                            "显示播放控制",
                            "关闭后隐藏三个播放按钮，适合直播歌曲展示",
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
                              "进度条样式",
                              "Material 3 线性、胶囊或分段轨道",
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
                                  "中心播放键的 Material 3 形状",
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
                                  "左侧切歌键的 Material 3 形状",
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
                                  "右侧切歌键的 Material 3 形状",
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
                        title: '播放列表与下一首',
                        icon: Icons.queue_music_rounded,
                        children: [
                          _buildSwitchRow(
                            '显示播放列表',
                            '接近歌曲结束时显示预计下一首；默认关闭',
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
                                  '仅在歌曲末尾的这段时间内切换为下一首信息',
                                  AppState.nextUpLeadSeconds,
                                  (value) {
                                    setState(
                                      () => AppState.nextUpLeadSeconds = value,
                                    );
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
                            '在频谱下方显示歌词；默认关闭',
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
                                      '在线查询会发送歌名、歌手和时长',
                                    LyricsProviderChoice.localLrc =>
                                      '仅从本地 LRC 文件夹读取，支持 UTF-8/UTF-16',
                                    LyricsProviderChoice.qqMusic =>
                                      '实验性网页接口；失败时回退 LRCLIB',
                                  },
                                  AppState.lyricsProviderChoice,
                                  (value) {
                                    setState(
                                      () =>
                                          AppState.lyricsProviderChoice = value,
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
                                  '跟随主题字体',
                                  '只同步字体家族；歌词字重和字号仍可单独调节',
                                  AppState.lyricsUseThemeFont,
                                  (value) {
                                    _updateTypography(
                                      () => AppState.lyricsUseThemeFont = value,
                                    );
                                  },
                                ),
                                _buildOptionalSetting(
                                  visible: !AppState.lyricsUseThemeFont,
                                  child: _buildDropdownRow<String>(
                                    '歌词字体',
                                    '与歌曲名、歌手名独立设置',
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
                                  ),
                                ),
                                _buildDivider(),
                                _buildContinuousSliderRow(
                                  title: '歌词字重',
                                  subtitle: 'W100–W900；可变字体支持更细腻的过渡',
                                  value: AppState.lyricsWeightValue,
                                  min: 100,
                                  max: 900,
                                  valueLabel: (value) => 'W${value.round()}',
                                  sliderKey: const ValueKey(
                                    'lyrics_weight_slider',
                                  ),
                                  onChanged: (value) => _updateTypography(
                                    () => AppState.lyricsWeightValue = value,
                                  ),
                                ),
                                _buildDivider(),
                                _buildContinuousSliderRow(
                                  title: '歌词字号',
                                  subtitle: '调整歌词大小，保持组件内完整显示',
                                  value: AppState.lyricsFontSize,
                                  min: 12,
                                  max: 17,
                                  valueLabel: (value) =>
                                      '${value.toStringAsFixed(1)} px',
                                  sliderKey: const ValueKey(
                                    'lyrics_size_slider',
                                  ),
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
                            "自动读取系统或手动添加",
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
                          ),
                          _buildDivider(),
                          _buildContinuousSliderRow(
                            title: '歌曲名字重',
                            subtitle: '无级调节主标题的视觉层级',
                            value: AppState.titleWeightValue,
                            min: 100,
                            max: 900,
                            valueLabel: (value) => 'W${value.round()}',
                            sliderKey: const ValueKey('title_weight_slider'),
                            onChanged: (value) => _updateTypography(
                              () => AppState.titleWeightValue = value,
                            ),
                          ),
                          _buildDivider(),
                          _buildContinuousSliderRow(
                            title: '歌手名字重',
                            subtitle: '无级调节副标题的视觉层级',
                            value: AppState.artistWeightValue,
                            min: 100,
                            max: 900,
                            valueLabel: (value) => 'W${value.round()}',
                            sliderKey: const ValueKey('artist_weight_slider'),
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
                children: children,
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
                      ? '支持“歌手 - 歌名.lrc”或“歌名.lrc”'
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
                      ? '支持 M3U / M3U8 / JSON；按歌名和歌手匹配当前歌曲'
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
                Text('QQ 音乐公开歌单', style: _settingTitleStyle()),
                Text(
                  AppState.qqPlaylistLink.isEmpty
                      ? '粘贴歌单链接或 ID；优先用于 QQ 音乐'
                      : '已连接歌单 ${parseQqPlaylistId(AppState.qqPlaylistLink) ?? ''} · 按顺序估算',
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
    String subtitle,
    T current,
    ValueChanged<T> onChanged,
    List<DropdownMenuEntry<T>> items, {
    Widget? actionButton,
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
        final double controlWidth = stacked
            ? (availableWidth - (actionButton == null ? 0 : 48)).clamp(
                0.0,
                double.infinity,
              )
            : (availableWidth * 0.44).clamp(180.0, 300.0);
        final Widget titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _settingTitleStyle()),
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
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged, {
    bool disabled = false,
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
                Text(
                  subtitle,
                  style: _settingSubtitleStyle(disabled: disabled),
                ),
              ],
            ),
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
    String subtitle,
    List<ButtonSegment<T>> segments,
    T current,
    ValueChanged<T> onSelected, {
    bool disabled = false,
  }) {
    final Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: _settingTitleStyle(disabled: disabled)),
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
