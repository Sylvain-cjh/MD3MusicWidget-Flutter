part of 'settingsPanel.dart';


extension _SettingsRows on _SettingsPanelState {
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
