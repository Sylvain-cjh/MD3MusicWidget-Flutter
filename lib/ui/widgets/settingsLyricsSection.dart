part of 'settingsPanel.dart';


extension _SettingsLyricsSection on _SettingsPanelState {
  Widget _buildLyricsGroupSettings() => _buildCategoryCard(
    title: SettingsLabels.lyricsGroup,
    icon: Icons.lyrics_rounded,
    children: [
      _buildSwitchRow(
        SettingsLabels.showLyrics,
        SettingsDescriptions.showLyrics,
        AppState.showLyrics,
        (value) {
          _updateState(() => AppState.showLyrics = value);
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
                _updateState(() => AppState.hideUnavailableLyrics = value);
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
                  SettingsDescriptions.lyricsProviderLrclib,
                LyricsProviderChoice.localLrc =>
                  SettingsDescriptions.lyricsProviderLocal,
                LyricsProviderChoice.qqMusic =>
                  SettingsDescriptions.lyricsProviderQqMusic,
                LyricsProviderChoice.neteaseCloud =>
                  SettingsDescriptions.lyricsProviderNetease,
                LyricsProviderChoice.amll =>
                  SettingsDescriptions.lyricsProviderAmll,
              },
              AppState.lyricsProviderChoice,
              (value) {
                _updateState(() => AppState.lyricsProviderChoice = value);
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
                  value: LyricsProviderChoice.neteaseCloud,
                  label: SettingsLabels.providerNetease,
                ),
                DropdownMenuEntry(
                  value: LyricsProviderChoice.amll,
                  label: SettingsLabels.providerAmll,
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
                      SettingsDescriptions.localTimedLyrics,
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
              (value) =>
                  _updateLyricsVisual(() => AppState.wordLyricsEnabled = value),
            ),
            _buildOptionalSetting(
              visible: _hasWordTiming && AppState.wordLyricsEnabled,
              child: Column(
                children: [
                  _buildSwitchRow(
                    SettingsLabels.wordLyricsSmoke,
                    SettingsDescriptions.wordLyricsSmoke,
                    AppState.wordLyricsSmokeEnabled,
                    (value) => _updateLyricsVisual(
                      () => AppState.wordLyricsSmokeEnabled = value,
                    ),
                  ),
                  _buildOptionalSetting(
                    visible: !AppState.wordLyricsSmokeEnabled,
                    child: Column(
                      children: [
                        _buildDropdownRow<LyricsHighlightStyle>(
                          SettingsLabels.wordLyricsStyle,
                          null,
                          AppState.lyricsHighlightStyle,
                          (value) => _updateLyricsVisual(
                            () => AppState.lyricsHighlightStyle = value,
                          ),
                          const [
                            DropdownMenuEntry(
                              value: LyricsHighlightStyle.sweep,
                              label: SettingsLabels.wordLyricsSweep,
                            ),
                            DropdownMenuEntry(
                              value: LyricsHighlightStyle.soft,
                              label: SettingsLabels.wordLyricsSoft,
                            ),
                            DropdownMenuEntry(
                              value: LyricsHighlightStyle.emphasis,
                              label: SettingsLabels.wordLyricsEmphasis,
                            ),
                          ],
                        ),
                        _buildContinuousSliderRow(
                          title: SettingsLabels.wordLyricsInactive,
                          subtitle: SettingsDescriptions.wordLyricsInactive,
                          value: AppState.lyricsInactiveOpacity,
                          min: .15,
                          max: 1,
                          resetValue: .46,
                          sliderKey: const ValueKey('lyrics_inactive_slider'),
                          valueLabel: (value) => '${(value * 100).round()}%',
                          inputScale: 100,
                          inputSuffix: '%',
                          onChanged: (value) => _updateLyricsVisual(
                            () => AppState.lyricsInactiveOpacity = value,
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
              sliderKey: const ValueKey('lyrics_offset_slider'),
              valueLabel: (value) =>
                  '${value > 0 ? '+' : ''}${value.toStringAsFixed(3)} 秒',
              inputFractionDigits: 3,
              inputSuffix: '秒',
              onChanged: (value) => _updateLyricsVisual(
                () => AppState.lyricsOffsetMs = (value * 1000).roundToDouble(),
              ),
            ),
            _buildDivider(),
            _buildSwitchRow(
              SettingsLabels.lyricsLinkAnimations,
              SettingsDescriptions.lyricsLinkAnimations,
              AppState.lyricsAnimationsLinked,
              (value) {
                _updateState(() => AppState.lyricsAnimationsLinked = value);
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
                _updateState(() {
                  AppState.lyricsTransitionStyle = value;
                  if (AppState.lyricsAnimationsLinked) {
                    AppState.lyricsExitTransitionStyle = value;
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
                    SettingsLabels.lyricsExitTransition,
                    SettingsDescriptions.lyricsExitTransition,
                    AppState.lyricsExitTransitionStyle,
                    (value) {
                      _updateState(
                        () => AppState.lyricsExitTransitionStyle = value,
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
              SettingsLabels.lyricsUseThemeFont,
              SettingsDescriptions.lyricsUseThemeFont,
              AppState.lyricsUseThemeFont,
              (value) {
                _updateTypography(() => AppState.lyricsUseThemeFont = value);
              },
              onReset: AppState.lyricsUseThemeFont
                  ? null
                  : () {
                      _updateTypography(
                        () => AppState.lyricsUseThemeFont = true,
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
                (value) =>
                    _updateTypography(() => AppState.lyricsFontFamily = value),
                AppState.loadedSystemFonts
                    .map(
                      (font) => DropdownMenuEntry<String>(
                        value: font,
                        label: font == 'System Default'
                            ? SettingsLabels.systemDefaultFont
                            : font,
                      ),
                    )
                    .toList(),
                actionButton: IconButton(
                  tooltip: '导入歌词字体文件',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () async {
                    final success = await AppState.importCustomFont(
                      forLyrics: true,
                    );
                    if (!mounted || !success) return;
                    _updateState(() {});
                    AppState.notifyTypographyChanged();
                    widget.onVisualChanged();
                  },
                ),
                onReset: AppState.lyricsFontFamily == AppState.defaultFontFamily
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
              title: SettingsLabels.lyricsWeight,
              subtitle: SettingsDescriptions.lyricsWeight,
              value: AppState.lyricsWeightValue,
              min: 100,
              max: 900,
              valueLabel: (value) => 'W${value.round()}',
              inputPrefix: 'W',
              sliderKey: const ValueKey('lyrics_weight_slider'),
              resetValue: AppState.defaultLyricsWeightValue,
              onChanged: (value) =>
                  _updateTypography(() => AppState.lyricsWeightValue = value),
            ),
            _buildDivider(),
            _buildContinuousSliderRow(
              title: SettingsLabels.lyricsSize,
              subtitle: SettingsDescriptions.lyricsSize,
              value: AppState.lyricsFontSize,
              min: 12,
              max: 17,
              valueLabel: (value) => '${value.toStringAsFixed(1)} px',
              inputFractionDigits: 1,
              inputSuffix: 'px',
              sliderKey: const ValueKey('lyrics_size_slider'),
              resetValue: AppState.defaultLyricsFontSize,
              onChanged: (value) =>
                  _updateTypography(() => AppState.lyricsFontSize = value),
            ),
            _buildTypographyPreview(
              title: SettingsLabels.lyricsPreview,
              sample: '此刻播放的音乐，值得被看见。',
              style: AppState.lyricsTextStyle(AppState.currentScheme.onSurface),
            ),
          ],
        ),
      ),
    ],
  );
}
