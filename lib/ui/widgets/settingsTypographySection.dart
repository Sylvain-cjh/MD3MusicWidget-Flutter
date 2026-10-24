part of 'settingsPanel.dart';


extension _SettingsTypographySection on _SettingsPanelState {
  Widget _buildTypographyGroupSettings() => _buildCategoryCard(
    title: SettingsLabels.typographyGroup,
    icon: Icons.text_fields_rounded,
    children: [
      _buildDropdownRow<String>(
        SettingsLabels.globalFont,
        SettingsDescriptions.globalFont,
        AppState.currentFontFamily,
        (val) {
          _updateState(() => AppState.currentFontFamily = val);
          widget.onVisualChanged();
        },
        AppState.loadedSystemFonts
            .map(
              (fontName) => DropdownMenuEntry<String>(
                value: fontName,
                label: fontName == AppState.defaultFontFamily
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
            final bool success = await AppState.importCustomFont();
            if (success) {
              _updateState(() {});
              widget.onVisualChanged();
            }
          },
        ),
        onReset: AppState.currentFontFamily == AppState.defaultFontFamily
            ? null
            : () {
                _updateTypography(
                  () => AppState.currentFontFamily = AppState.defaultFontFamily,
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
        onChanged: (value) =>
            _updateTypography(() => AppState.titleWeightValue = value),
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
        onChanged: (value) =>
            _updateTypography(() => AppState.artistWeightValue = value),
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
          icon: const Icon(Icons.info_outline_rounded, size: 18),
          label: const Text(SettingsLabels.fontCredits),
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'MD3 Music Widget',
          ),
        ),
      ),
    ],
  );
}
