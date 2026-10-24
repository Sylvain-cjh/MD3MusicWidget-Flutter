import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/appState.dart';
import '../../core/mediaProvider.dart';
import '../../core/musicSourceService.dart';
import '../../core/systemPerformanceProvider.dart';
import '../../core/qqMusicPlaylistQueueProvider.dart';
import '../../core/neteasePlaylistQueueProvider.dart';
import '../../core/platformProvider.dart';
import 'md3AnchoredSelect.dart';
import 'settingsDescriptions.dart';
import 'settingsLabels.dart';
import 'settingsSectionNavigation.dart';
import 'settingsScrollViewport.dart';
import 'adaptiveMediaText.dart';
import 'jellySlider.dart';
import 'editableSliderValue.dart';
import 'smoothRoundedClip.dart';
import '../../core/coverLayers.dart';

part 'settingsWindowSection.dart';
part 'settingsAppearanceSection.dart';
part 'settingsPlaybackSection.dart';
part 'settingsLyricsSection.dart';
part 'settingsTypographySection.dart';
part 'settingsActions.dart';
part 'settingsChoiceEntries.dart';
part 'settingsMediaOptions.dart';
part 'settingsRows.dart';

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
                        _buildWindowGroupSettings(),

                      if (_selectedSection == _SettingsSection.appearance)
                        _buildThemeGroupSettings(),

                      if (_selectedSection == _SettingsSection.appearance)
                        _buildBackgroundGroupSettings(),

                      if (_selectedSection == _SettingsSection.appearance &&
                          !AppState.isVertical)
                        _buildRightCoverGroupSettings(),
                      if (_selectedSection == _SettingsSection.appearance)
                        _buildPerformanceGroupSettings(),

                      if (_selectedSection == _SettingsSection.appearance)
                        _buildStorageGroupSettings(),

                      if (_selectedSection == _SettingsSection.playback)
                        _buildPlaybackGroupSettings(),

                      if (_selectedSection == _SettingsSection.playback)
                        _buildNextUpGroupSettings(),

                      if (_selectedSection == _SettingsSection.lyrics)
                        _buildLyricsGroupSettings(),

                      if (_selectedSection == _SettingsSection.typography)
                        _buildTypographyGroupSettings(),
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

  void _updateState(VoidCallback change) => setState(change);
}
