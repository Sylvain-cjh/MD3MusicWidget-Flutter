part of 'settingsPanel.dart';


extension _SettingsWindowSection on _SettingsPanelState {
  Widget _buildWindowGroupSettings() => _buildCategoryCard(
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
          _updateState(() => AppState.widgetLayout = val);
          widget.onLayoutChanged();
        },
      ),
      _buildDivider(),
      _buildDropdownRow<ComponentSizeMode>(
        SettingsLabels.componentSize,
        AppState.isCustomComponentSize
            ? SettingsDescriptions.customComponentSize(
                (AppState.customComponentScale * 100).round(),
              )
            : SettingsDescriptions.componentSize,
        AppState.componentSizeMode,
        (val) {
          if (val == ComponentSizeMode.custom &&
              !AppState.isCustomComponentSize) {
            AppState.customComponentScale = AppState.componentScale;
          }
          _updateState(() => AppState.componentSizeMode = val);
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
          _updateState(() => AppState.isAlwaysOnTop = val);
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
            _updateState(() => AppState.isMousePassthrough = val);
            widget.onWindowBehaviorChanged();
          },
        ),
      ],
    ],
  );
}
