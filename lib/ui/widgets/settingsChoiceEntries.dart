part of 'settingsPanel.dart';


extension _SettingsChoiceEntries on _SettingsPanelState {
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
}
