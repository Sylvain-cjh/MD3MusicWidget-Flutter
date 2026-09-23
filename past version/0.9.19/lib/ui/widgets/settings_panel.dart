import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../core/media_provider.dart';
import 'md3_anchored_select.dart';

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

  @override
  void dispose() {
    AppState.playbackRevision.removeListener(_handleTimelineAvailability);
    AppState.fontsRevision.removeListener(_handleFontsChanged);
    super.dispose();
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
          const SizedBox(height: 20),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40, right: 8),
                children: [
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
                            setState(() => AppState.isMousePassthrough = val);
                            widget.onWindowBehaviorChanged();
                          },
                        ),
                      ],
                    ],
                  ),

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
                                setState(() => AppState.enableOledTheme = val);
                                widget.onBackgroundChanged();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

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
                          "在播放器底部显示独立的动态频谱控件",
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

                  _buildCategoryCard(
                    title: "播放控件形状",
                    icon: Icons.widgets_rounded,
                    children: [
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
                      _buildDropdownRow<MD3Shape>(
                        "播放按钮",
                        "中心播放键的 Material 3 形状",
                        AppState.playButtonShape,
                        (val) {
                          setState(() => AppState.playButtonShape = val);
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
                          setState(() => AppState.prevButtonShape = val);
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
                          setState(() => AppState.nextButtonShape = val);
                          widget.onVisualChanged();
                        },
                        _shapeEntries(),
                      ),
                    ],
                  ),

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
                      _buildDropdownRow<int>(
                        "歌曲名字重",
                        "调节主标题的视觉层级",
                        AppState.titleWeightIndex,
                        (val) {
                          setState(() => AppState.titleWeightIndex = val);
                          widget.onVisualChanged();
                        },
                        List.generate(
                          9,
                          (index) => DropdownMenuEntry(
                            value: index,
                            label:
                                'W${(index + 1) * 100} ${index == 3 ? "(常规)" : (index == 6 ? "(粗体)" : "")}',
                          ),
                        ),
                      ),
                      _buildDivider(),
                      _buildDropdownRow<int>(
                        "歌手名字重",
                        "调节副标题的视觉层级",
                        AppState.artistWeightIndex,
                        (val) {
                          setState(() => AppState.artistWeightIndex = val);
                          widget.onVisualChanged();
                        },
                        List.generate(
                          9,
                          (index) => DropdownMenuEntry(
                            value: index,
                            label:
                                'W${(index + 1) * 100} ${index == 3 ? "(常规)" : (index == 6 ? "(粗体)" : "")}',
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
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubicEmphasized,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
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
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = (constraints.maxWidth - 36).clamp(
          0.0,
          double.infinity,
        );
        final double controlWidth = AppState.isVertical
            ? (availableWidth * 0.52).clamp(148.0, 176.0)
            : (availableWidth * 0.38).clamp(148.0, 168.0);
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

        if (AppState.isVertical) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [?actionButton, control],
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

    if (AppState.isVertical) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleBlock,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: control),
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
  }
}
