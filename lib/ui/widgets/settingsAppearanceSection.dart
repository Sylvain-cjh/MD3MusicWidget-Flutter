part of 'settingsPanel.dart';


extension _SettingsAppearanceSection on _SettingsPanelState {
  Widget _buildThemeGroupSettings() => _buildCategoryCard(
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
          _updateState(() => AppState.themeVariant = val);
          widget.onThemeChanged();
        },
      ),
      _buildDivider(),
      _buildSwitchRow(
        SettingsLabels.darkMode,
        null,
        AppState.themeBrightness == Brightness.dark,
        (val) {
          _updateState(
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
          _updateState(() => AppState.settingsNavigationShape = value);
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
            AppState.themeBrightness == Brightness.dark && !AppState.enableGlow,
        child: Column(
          children: [
            _buildDivider(),
            _buildSwitchRow(
              SettingsLabels.oled,
              SettingsDescriptions.oled,
              AppState.enableOledTheme,
              (val) {
                _updateState(() => AppState.enableOledTheme = val);
                widget.onBackgroundChanged();
              },
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildBackgroundGroupSettings() => _buildCategoryCard(
    title: SettingsLabels.backgroundGroup,
    icon: Icons.animation_rounded,
    children: [
      _buildSwitchRow(
        SettingsLabels.glow,
        SettingsDescriptions.glow,
        AppState.enableGlow,
        (val) {
          _updateState(() => AppState.enableGlow = val);
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
                  label: Text(SettingsLabels.glowWaterfall),
                ),
                const ButtonSegment(
                  value: GlowMode.wallpaper,
                  label: Text(SettingsLabels.glowWallpaper),
                ),
              ],
              AppState.glowMode,
              (val) {
                _updateState(() => AppState.glowMode = val);
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
          _updateState(() => AppState.enable3DCover = val);
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
            _updateState(() => AppState.enableCoverLayers = val);
            widget.onVisualChanged();
          },
        ),
        if (AppState.enableCoverLayers) ...[
          _buildDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ValueListenableBuilder<String>(
              valueListenable: CoverLayerService.instance.status,
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
            _updateState(() => AppState.enableProgressAutoContrast = val);
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
                (AppState.spectrumMode == SpectrumMode.off) !=
                (val == SpectrumMode.off);
            _updateState(() => AppState.spectrumMode = val);
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
          subtitle: SettingsDescriptions.spectrumThickness,
          value: AppState.spectrumThickness,
          min: 0.35,
          max: 3,
          resetValue: AppState.defaultSpectrumThickness,
          valueLabel: (value) => '${value.toStringAsFixed(2)}×',
          inputFractionDigits: 2,
          inputSuffix: '×',
          sliderKey: const ValueKey('spectrum_thickness_slider'),
          onChanged: _updateSpectrumThickness,
          onChangeEnd: _finishSpectrumStyleChange,
        ),
      ),
      _buildOptionalSetting(
        visible:
            (AppState.spectrumMode == SpectrumMode.bars ||
                AppState.spectrumMode == SpectrumMode.mirror) &&
            MediaCapability.supports(
              AppState.mediaCapabilities,
              MediaCapability.spectrum,
            ),
        child: Column(
          children: [
            _buildSwitchRow(
              SettingsLabels.automaticSpectrumColumns,
              SettingsDescriptions.automaticSpectrumColumns,
              AppState.automaticSpectrumColumns,
              (value) => _updateSpectrumStyle(
                () => AppState.automaticSpectrumColumns = value,
              ),
            ),
            _buildOptionalSetting(
              visible: !AppState.automaticSpectrumColumns,
              child: _buildContinuousSliderRow(
                title: SettingsLabels.spectrumColumnCount,
                subtitle: SettingsDescriptions.spectrumColumnCount,
                value: AppState.spectrumColumnCount.toDouble(),
                min: 1,
                max: 128,
                divisions: 127,
                resetValue: 32,
                valueLabel: (value) => '${value.round()} 根',
                inputSuffix: '根',
                sliderKey: const ValueKey('spectrum_column_count_slider'),
                onChanged: (value) => _updateSpectrumStyle(
                  () => AppState.spectrumColumnCount = value.round().clamp(
                    1,
                    128,
                  ),
                ),
                onChangeEnd: _finishSpectrumStyleChange,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildRightCoverGroupSettings() => _buildCategoryCard(
    title: SettingsLabels.rightCoverGroup,
    icon: Icons.gradient_rounded,
    children: [
      _buildContinuousSliderRow(
        title: SettingsLabels.rightCoverDarkening,
        subtitle: SettingsDescriptions.rightCoverDarkening,
        value: AppState.rightCoverDarkening,
        min: 0,
        max: 0.85,
        resetValue: AppState.defaultRightCoverDarkening,
        valueLabel: (value) => '${(value * 100).round()}%',
        inputScale: 100,
        inputSuffix: '%',
        sliderKey: const ValueKey('right_cover_darkening_slider'),
        onChanged: (value) =>
            _updateRightArtwork(() => AppState.rightCoverDarkening = value),
        onChangeEnd: _finishRightArtworkChange,
      ),
      KeyedSubtree(
        key: const ValueKey('right_cover_fade_linked_switch'),
        child: _buildSwitchRow(
          SettingsLabels.rightCoverFadeLinked,
          SettingsDescriptions.rightCoverFadeLinked,
          AppState.rightCoverFadeLinked,
          (value) {
            _updateRightArtwork(() => AppState.setRightCoverFadeLinked(value));
            _finishRightArtworkChange();
          },
        ),
      ),
      _buildOptionalSetting(
        visible: AppState.rightCoverFadeLinked,
        child: _buildRightCoverFadeSlider(
          title: SettingsLabels.rightCoverFadeLength,
          subtitle: SettingsDescriptions.rightCoverFadeLength,
          value: AppState.rightCoverFadeLength,
          keyName: 'right_cover_fade_slider',
          onChanged: (value) => AppState.rightCoverFadeLength = value,
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
              onChanged: (value) => AppState.rightCoverFadeLengthX = value,
            ),
            _buildRightCoverFadeSlider(
              title: SettingsLabels.rightCoverFadeY,
              value: AppState.rightCoverFadeLengthY,
              keyName: 'right_cover_fade_y_slider',
              onChanged: (value) => AppState.rightCoverFadeLengthY = value,
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
        sliderKey: const ValueKey('right_cover_blur_slider'),
        onChanged: (value) =>
            _updateRightArtwork(() => AppState.rightCoverBlur = value),
        onChangeEnd: _finishRightArtworkChange,
      ),
    ],
  );

  Widget _buildPerformanceGroupSettings() => _buildCategoryCard(
    title: SettingsLabels.performanceGroup,
    icon: Icons.speed_rounded,
    children: [
      _buildSwitchRow(
        SettingsLabels.performanceMonitor,
        SettingsDescriptions.performanceMonitor,
        AppState.showPerformanceMonitor,
        (value) {
          final wasVisible = AppState.performanceMonitorVisible;
          _updateState(() => AppState.showPerformanceMonitor = value);
          AppState.notifyPerformanceChanged();
          if (value &&
              AppState.performanceMetricEnabled(PerformanceMetric.fps)) {
            unawaited(_refreshPerformanceProcesses());
          }
          if (AppState.spectrumMode == SpectrumMode.off &&
              wasVisible != AppState.performanceMonitorVisible) {
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
                key: ValueKey('performance_toggle_${metric.name}'),
                child: _buildSwitchRow(
                  _performanceMetricLabel(metric),
                  null,
                  AppState.performanceMetricEnabled(metric),
                  (value) => _setPerformanceMetric(metric, value),
                ),
              ),
            _buildOptionalSetting(
              visible: AppState.performanceMetricEnabled(PerformanceMetric.fps),
              child: ValueListenableBuilder<String>(
                valueListenable: SystemPerformanceProvider.fpsStatus,
                builder: (context, status, _) => Column(
                  children: [
                    _buildDropdownRow<String>(
                      SettingsLabels.performanceProcess,
                      SettingsDescriptions.performanceFpsStatus(status),
                      AppState.performanceProcessExecutable,
                      (value) {
                        _updateState(
                          () => AppState.performanceProcessExecutable = value,
                        );
                        AppState.notifyPerformanceChanged();
                        unawaited(AppState.saveSettings());
                      },
                      _performanceProcessEntries(),
                      fullWidth: true,
                      actionButton: IconButton(
                        tooltip: '刷新程序列表',
                        onPressed: _performanceProcessesLoading
                            ? null
                            : _refreshPerformanceProcesses,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ),
                    if (status == 'permissionDenied')
                      TextButton.icon(
                        onPressed: _restartMonitorElevated,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text(SettingsLabels.performanceAuthorize),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildStorageGroupSettings() => _buildCategoryCard(
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
        sliderKey: const ValueKey('lyrics_cache_limit_slider'),
        onChanged: (value) => _updateCacheLimit(
          () => AppState.lyricsCacheLimitMiB = value.round(),
        ),
        onChangeEnd: _finishCacheLimitChange,
      ),
      _buildDivider(),
      _buildContinuousSliderRow(
        title: SettingsLabels.backgroundCacheLimit,
        subtitle: SettingsDescriptions.backgroundCacheLimit,
        value: AppState.backgroundCacheLimitMiB.toDouble(),
        min: 0,
        max: 1024,
        divisions: 1024,
        resetValue: 128,
        valueLabel: SettingsLabels.cacheCapacity,
        inputSuffix: 'MiB',
        sliderKey: const ValueKey('background_cache_limit_slider'),
        onChanged: (value) => _updateCacheLimit(
          () => AppState.backgroundCacheLimitMiB = value.round(),
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
                    title: const Text(SettingsLabels.clearCaches),
                    content: const Text(
                      '只清理本程序保存的歌词和背景源图，不会删除你的歌单、LRC 文件或当前画面。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('清理'),
                      ),
                    ],
                  ),
                );
                if (clear == true) {
                  await AppState.clearPersistentCaches();
                  if (mounted) _updateState(() {});
                }
              },
              child: const Text(SettingsLabels.clearCaches),
            ),
          ],
        ),
      ),
    ],
  );
}
