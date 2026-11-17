part of 'settingsPanel.dart';


extension _SettingsPlaybackSection on _SettingsPanelState {
  Widget _buildPlaybackGroupSettings() => _buildCategoryCard(
    title: SettingsLabels.playbackGroup,
    icon: Icons.widgets_rounded,
    children: [
      _buildDropdownRow<String>(
        SettingsLabels.sourceApp,
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ),
      if (Platform.isWindows) ...[
        _buildDivider(),
        _buildAudioOutputSelector(),
        _buildDivider(),
        MergeSemantics(
          child: _buildSwitchRow(
            SettingsLabels.showHomeAudioOutput,
            SettingsDescriptions.showHomeAudioOutput,
            AppState.showHomeAudioOutput,
            (value) {
              _updateState(() => AppState.showHomeAudioOutput = value);
              widget.onVisualChanged();
            },
          ),
        ),
      ],
      _buildDivider(),
      _buildSwitchRow(
        SettingsLabels.trackTextAnimations,
        SettingsDescriptions.trackTextAnimations,
        AppState.trackTextAnimationsEnabled,
        (value) {
          _updateState(() => AppState.trackTextAnimationsEnabled = value);
          widget.onVisualChanged();
        },
      ),
      _buildOptionalSetting(
        visible: AppState.trackTextAnimationsEnabled,
        child: Column(
          children: [
            _buildDivider(),
            _buildDropdownRow<TrackTextTransitionStyle>(
              SettingsLabels.trackTextTransition,
              SettingsDescriptions.trackTextTransition,
              AppState.trackTextTransitionStyle,
              (value) {
                _updateState(() => AppState.trackTextTransitionStyle = value);
                widget.onVisualChanged();
              },
              _trackTextTransitionEntries(),
            ),
            _buildDivider(),
            _buildSwitchRow(
              SettingsLabels.trackTextAnimationsLinked,
              SettingsDescriptions.trackTextAnimationsLinked,
              AppState.trackTextAnimationsLinked,
              (value) {
                _updateState(() => AppState.trackTextAnimationsLinked = value);
                widget.onVisualChanged();
              },
            ),
            _buildOptionalSetting(
              visible: !AppState.trackTextAnimationsLinked,
              child: Column(
                children: [
                  _buildDivider(),
                  _buildDropdownRow<TrackTextExitStyle>(
                    SettingsLabels.trackTextExitTransition,
                    SettingsDescriptions.trackTextExitTransition,
                    AppState.trackTextExitStyle,
                    (value) {
                      _updateState(() => AppState.trackTextExitStyle = value);
                      widget.onVisualChanged();
                    },
                    _trackTextExitEntries(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _buildDivider(),
      _buildDropdownRow<CoverTransitionStyle>(
        SettingsLabels.coverTransition,
        SettingsDescriptions.coverTransition,
        AppState.coverTransitionStyle,
        (value) {
          _updateState(() => AppState.coverTransitionStyle = value);
          widget.onVisualChanged();
        },
        _coverTransitionEntries(),
      ),
      _buildDivider(),
      _buildSwitchRow(
        SettingsLabels.coverVolumeEnabled,
        SettingsDescriptions.coverVolumeEnabled,
        AppState.coverVolumeEnabled,
        (value) {
          _updateState(() => AppState.coverVolumeEnabled = value);
          widget.onVisualChanged();
        },
      ),
      _buildOptionalSetting(
        visible: AppState.coverVolumeEnabled,
        child: _buildContinuousSliderRow(
          title: SettingsLabels.coverVolumeStep,
          subtitle: SettingsDescriptions.coverVolumeStep,
          value: AppState.coverVolumeStep.toDouble(),
          min: 1,
          max: AppState.maxCoverVolumeStep.toDouble(),
          divisions: AppState.maxCoverVolumeStep - 1,
          resetValue: AppState.defaultCoverVolumeStep.toDouble(),
          sliderKey: const ValueKey('cover_volume_step'),
          valueLabel: (value) => '${value.round()}%',
          inputSuffix: '%',
          onChanged: (value) =>
              _updateState(() => AppState.coverVolumeStep = value.round()),
          onChangeEnd: widget.onVisualChanged,
        ),
      ),
      _buildDivider(),
      _buildSwitchRow(
        SettingsLabels.playbackControls,
        SettingsDescriptions.playbackControls,
        AppState.showPlaybackControls,
        (val) {
          _updateState(() => AppState.showPlaybackControls = val);
          widget.onLayoutChanged();
        },
      ),
      _buildDivider(),
      if (MediaCapability.supports(
        AppState.mediaCapabilities,
        MediaCapability.timeline,
      ))
        _buildDropdownRow<MD3ProgressStyle>(
          SettingsLabels.progressStyle,
          null,
          AppState.progressStyle,
          (val) {
            _updateState(() => AppState.progressStyle = val);
            widget.onVisualChanged();
          },
          _progressStyleEntries(),
        ),
      if (MediaCapability.supports(
        AppState.mediaCapabilities,
        MediaCapability.timeline,
      ))
        KeyedSubtree(
          key: const ValueKey('playback_time_switch'),
          child: _buildSwitchRow(
            SettingsLabels.playbackTime,
            SettingsDescriptions.playbackTime,
            AppState.showPlaybackTime,
            (value) {
              _updateState(() => AppState.showPlaybackTime = value);
              widget.onVisualChanged();
            },
          ),
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
              SettingsLabels.playButton,
              null,
              AppState.playButtonShape,
              (val) {
                _updateState(() => AppState.playButtonShape = val);
                widget.onVisualChanged();
              },
              _shapeEntries(),
            ),
            _buildDivider(),
            _buildDropdownRow<MD3Shape>(
              SettingsLabels.previousButton,
              null,
              AppState.prevButtonShape,
              (val) {
                _updateState(() => AppState.prevButtonShape = val);
                widget.onVisualChanged();
              },
              _shapeEntries(),
            ),
            _buildDivider(),
            _buildDropdownRow<MD3Shape>(
              SettingsLabels.nextButton,
              null,
              AppState.nextButtonShape,
              (val) {
                _updateState(() => AppState.nextButtonShape = val);
                widget.onVisualChanged();
              },
              _shapeEntries(),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildAudioOutputSelector() {
    final audio = AppState.audioOutputs;
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final devices = audio.outputs;
        final current = devices.any((device) => device.id == audio.defaultId)
            ? audio.defaultId
            : '';
        return _buildDropdownRow<String>(
          SettingsLabels.audioOutputDevice,
          audio.switching
              ? SettingsDescriptions.audioOutputChanging
              : audio.selectFailed
              ? SettingsDescriptions.audioOutputSelectFailed
              : audio.available
              ? SettingsDescriptions.audioOutputDevice
              : SettingsDescriptions.audioOutputUnavailable,
          current,
          (id) => unawaited(audio.select(id)),
          [
            if (current.isEmpty)
              DropdownMenuEntry(
                value: '',
                enabled: false,
                label: devices.isEmpty
                    ? SettingsLabels.noAudioOutput
                    : SettingsLabels.currentAudioOutputUnknown,
              ),
            for (final device in devices)
              DropdownMenuEntry(
                value: device.id,
                label: device.name.isEmpty
                    ? SettingsLabels.unknownAudioOutput
                    : device.name,
                enabled: !audio.switching,
                leadingIcon: Icon(
                  device.bluetoothGroup.isNotEmpty
                      ? Icons.bluetooth_audio_rounded
                      : Icons.speaker_rounded,
                  size: 17,
                ),
              ),
          ],
          fullWidth: true,
          actionButton: IconButton(
            tooltip: SettingsLabels.openWindowsSoundSettings,
            onPressed: () => unawaited(audio.openWindowsSettings()),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
          ),
        );
      },
    );
  }

  Widget _buildNextUpGroupSettings() => _buildCategoryCard(
    title: SettingsLabels.nextUpGroup,
    icon: Icons.queue_music_rounded,
    children: [
      _buildSwitchRow(
        SettingsLabels.showNextUp,
        SettingsDescriptions.showPlaylist,
        AppState.showNextUp,
        (value) {
          _updateState(() => AppState.showNextUp = value);
          AppState.refreshQueue(force: true);
          widget.onLayoutChanged();
        },
      ),
      _buildOptionalSetting(
        visible: AppState.showNextUp,
        child: Column(
          children: [
            _buildDivider(),
            _buildPlaylistSourceSelector(),
            _buildDivider(),
            _buildSelectedPlaylistRow(),
            _buildDivider(),
            _buildDropdownRow<int>(
              SettingsLabels.nextUpLead,
              SettingsDescriptions.nextUpLead,
              AppState.nextUpLeadSeconds,
              (value) {
                _updateState(() => AppState.nextUpLeadSeconds = value);
                AppState.playbackRevision.value++;
                widget.onVisualChanged();
              },
              const [
                DropdownMenuEntry(
                  value: 10,
                  label: SettingsLabels.lead10Seconds,
                ),
                DropdownMenuEntry(
                  value: 20,
                  label: SettingsLabels.lead20Seconds,
                ),
                DropdownMenuEntry(
                  value: 30,
                  label: SettingsLabels.lead30Seconds,
                ),
                DropdownMenuEntry(
                  value: 45,
                  label: SettingsLabels.lead45Seconds,
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}
