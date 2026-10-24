part of 'settingsPanel.dart';


extension _SettingsActions on _SettingsPanelState {
  Future<void> _changeCacheDirectory({bool reset = false}) async {
    if (_cacheDirectoryChanging) return;
    try {
      final path = reset ? '' : await FilePicker.getDirectoryPath();
      if (path == null || !mounted) return;
      _updateState(() {
        _cacheDirectoryChanging = true;
        _cacheDirectoryError = null;
      });
      await AppState.setCacheDirectory(path);
    } catch (_) {
      if (mounted) {
        _updateState(() => _cacheDirectoryError = '这个位置暂时无法写入，已保留原来的缓存位置');
      }
    } finally {
      if (mounted) _updateState(() => _cacheDirectoryChanging = false);
    }
  }

  Widget _buildCacheDirectoryRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(SettingsLabels.cacheDirectory, style: _settingTitleStyle()),
        const SizedBox(height: 4),
        Text(
          _cacheDirectoryError ?? SettingsDescriptions.cacheDirectory,
          style: _settingSubtitleStyle(),
        ),
        const SizedBox(height: 6),
        Tooltip(
          message: AppState.cacheDirectoryPath,
          child: Text(
            AppState.cacheDirectoryPath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _settingSubtitleStyle(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('choose_cache_directory'),
              onPressed: _cacheDirectoryChanging ? null : _changeCacheDirectory,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: Text(
                _cacheDirectoryChanging
                    ? SettingsLabels.cacheDirectoryChanging
                    : SettingsLabels.chooseCacheDirectory,
              ),
            ),
            if (AppState.customCacheDirectory.isNotEmpty)
              TextButton(
                onPressed: _cacheDirectoryChanging
                    ? null
                    : () => _changeCacheDirectory(reset: true),
                child: const Text(SettingsLabels.resetCacheDirectory),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _refreshPerformanceProcesses() async {
    if (_performanceProcessesLoading) return;
    _updateState(() => _performanceProcessesLoading = true);
    final processes = await SystemPerformanceProvider.processes();
    if (!mounted) return;
    _updateState(() {
      _performanceProcesses = processes;
      _performanceProcessesLoading = false;
    });
  }

  Future<void> _restartMonitorElevated() async {
    await AppState.saveSettings();
    await AppState.flushSettings();
    if (await SystemPerformanceProvider.restartElevated()) {
      await AppState.exitApp();
    }
  }

  void _setPerformanceMetric(PerformanceMetric metric, bool enabled) {
    final wasVisible = AppState.performanceMonitorVisible;
    _updateState(() {
      AppState.performanceMetricsMask = enabled
          ? AppState.performanceMetricsMask | metric.bit
          : AppState.performanceMetricsMask & ~metric.bit;
    });
    AppState.notifyPerformanceChanged();
    unawaited(AppState.saveSettings());
    if (metric == PerformanceMetric.fps && enabled) {
      unawaited(_refreshPerformanceProcesses());
    }
    if (AppState.spectrumMode == SpectrumMode.off &&
        wasVisible != AppState.performanceMonitorVisible) {
      widget.onLayoutChanged();
    } else {
      widget.onVisualChanged();
    }
  }

  String _performanceMetricLabel(PerformanceMetric metric) => switch (metric) {
    PerformanceMetric.fps => SettingsLabels.performanceFps,
    PerformanceMetric.cpu => SettingsLabels.performanceCpu,
    PerformanceMetric.gpu => SettingsLabels.performanceGpu,
    PerformanceMetric.memory => SettingsLabels.performanceMemory,
  };

  void _updateTypography(VoidCallback change) {
    _updateState(change);
    AppState.notifyTypographyChanged();
    _typographySaveTimer?.cancel();
    _typographySaveTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(AppState.saveSettings()),
    );
  }

  void _updateLyricsVisual(VoidCallback change) {
    _updateState(change);
    AppState.lyrics.setPositionMs(AppState.lyricsPlaybackPositionMs);
    AppState.notifyLyricsVisualChanged();
    unawaited(AppState.saveSettings());
  }

  void _handleWordTiming() {
    final next = AppState.lyrics.state.document?.isWordTimed == true;
    if (mounted && next != _hasWordTiming) {
      _updateState(() => _hasWordTiming = next);
    }
  }

  void _updateSpectrumThickness(double value) {
    _updateSpectrumStyle(() => AppState.spectrumThickness = value);
  }

  void _updateSpectrumStyle(VoidCallback change) {
    _updateState(change);
    AppState.notifySpectrumStyleChanged();
    _spectrumStyleSaveTimer?.cancel();
    _spectrumStyleSaveTimer = Timer(
      const Duration(milliseconds: 450),
      _finishSpectrumStyleChange,
    );
  }

  void _finishSpectrumStyleChange() {
    _spectrumStyleSaveTimer?.cancel();
    _spectrumStyleSaveTimer = null;
    unawaited(AppState.saveSettings());
  }

  void _finishTypographyChange() {
    _typographySaveTimer?.cancel();
    _typographySaveTimer = null;
    unawaited(AppState.saveSettings());
  }

  void _updateRightArtwork(VoidCallback change) {
    _updateState(change);
    AppState.notifyRightArtworkChanged();
    _rightArtworkSaveTimer?.cancel();
    _rightArtworkSaveTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(AppState.saveSettings()),
    );
  }

  Widget _buildRightCoverFadeSlider({
    required String title,
    String subtitle = '',
    required double value,
    required String keyName,
    required ValueChanged<double> onChanged,
  }) => _buildContinuousSliderRow(
    title: title,
    subtitle: subtitle,
    value: value,
    min: 0.15,
    max: 1,
    resetValue: AppState.defaultRightCoverFadeLength,
    valueLabel: (value) => '${(value * 100).round()}%',
    inputScale: 100,
    inputSuffix: '%',
    sliderKey: ValueKey(keyName),
    onChanged: (value) => _updateRightArtwork(() => onChanged(value)),
    onChangeEnd: _finishRightArtworkChange,
  );

  void _finishRightArtworkChange() {
    _rightArtworkSaveTimer?.cancel();
    _rightArtworkSaveTimer = null;
    unawaited(AppState.saveSettings());
  }

  void _updateCacheLimit(VoidCallback change) {
    _updateState(change);
    _cacheLimitSaveTimer?.cancel();
    _cacheLimitSaveTimer = Timer(
      const Duration(milliseconds: 450),
      _finishCacheLimitChange,
    );
  }

  void _finishCacheLimitChange() {
    _cacheLimitSaveTimer?.cancel();
    _cacheLimitSaveTimer = null;
    unawaited(AppState.saveSettings());
    unawaited(AppState.applyCacheLimits());
  }

  void _handleFontsChanged() {
    if (mounted) _updateState(() {});
  }

  void _handleTimelineAvailability() {
    final bool nextHasTimeline = AppState.playbackDurationMs > 0;
    if (!mounted || nextHasTimeline == _hasTimeline) return;
    _updateState(() => _hasTimeline = nextHasTimeline);
  }

  Widget _buildLocalLyricsFolderRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  SettingsLabels.localLyricsDirectory,
                  style: _settingTitleStyle(),
                ),
                Text(
                  AppState.localLyricsDirectory.isEmpty
                      ? SettingsDescriptions.localLyricsEmpty
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
                _updateState(() => AppState.setLocalLyricsDirectory(path));
                widget.onVisualChanged();
              } catch (_) {}
            },
            child: const Text('选择'),
          ),
        ],
      ),
    );
  }

  String get _displayQueueProviderId {
    if (AppState.selectedQueueProviderId.isNotEmpty) {
      return AppState.selectedQueueProviderId;
    }
    if (AppState.qqPlaylistLink.isNotEmpty &&
        (AppState.currentPlatformTrack == null ||
            AppState.currentPlatformTrack?.platform == MusicPlatform.qqMusic)) {
      return 'qqMusicPlaylist';
    }
    if (AppState.neteasePlaylistLink.isNotEmpty) return 'neteasePlaylist';
    if (AppState.playlistFilePath.isNotEmpty) return 'localPlaylist';
    return 'qqMusicPlaylist';
  }
}
