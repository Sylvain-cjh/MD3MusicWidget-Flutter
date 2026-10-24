part of 'playerView.dart';


extension _PlayerMedia on _PlayerViewState {
  Future<bool> _askToInstallDotnet() async {
    if (!mounted) return false;
    bool installing = false;
    String message = 'MusicFetcher 需要 .NET 8 Runtime x64。安装过程需要联网并可能弹出系统权限确认。';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: const Text('.NET 运行环境缺失'),
              content: SizedBox(
                width: 360,
                child: Text(
                  installing ? '正在在线下载并安装 .NET 8 Runtime，请稍候……' : message,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: installing
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('稍后安装'),
                ),
                FilledButton(
                  onPressed: installing
                      ? null
                      : () async {
                          dialogSetState(() => installing = true);
                          final success = await _fetcherRuntime.dotnet
                              .installOnline();
                          if (!dialogContext.mounted) return;
                          final runtimeReady =
                              success &&
                              await _fetcherRuntime.dotnet.isAvailable();
                          if (!dialogContext.mounted) return;
                          if (runtimeReady) {
                            Navigator.of(dialogContext).pop(true);
                          } else {
                            dialogSetState(() {
                              installing = false;
                              message = '在线安装没有完成，请检查网络或确认系统权限后重试。';
                            });
                          }
                        },
                  child: const Text('在线安装'),
                ),
              ],
            );
          },
        );
      },
    );
    return result == true;
  }

  Future<bool> _waitForFetcherReady({
    Duration maxWait = const Duration(milliseconds: 1800),
  }) async {
    if (!mounted) return false;
    final backend = AppState.mediaBackend;
    if (!backend.supportsLegacyPolling || backend is! LegacyMediaReader) {
      return false;
    }
    final pid = await (backend as LegacyMediaReader).waitUntilReady(
      maxWait: maxWait,
    );
    if (!mounted || pid == null) return false;
    AppState.recordFetcherProcess(backend, pid);
    return true;
  }

  Future<bool> _applySavedSource() async {
    if (!mounted) return false;
    try {
      await AppState.mediaBackend.selectSource(AppState.selectedSourceAppId);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _recordFetcherFailure() {
    _infoFailureStreak++;
    final now = DateTime.now().millisecondsSinceEpoch;
    final hasBeenUnavailable =
        _lastInfoSuccessAtMs == 0 || now - _lastInfoSuccessAtMs > 1200;
    if (_infoFailureStreak >= 4 &&
        hasBeenUnavailable &&
        now - _lastFetcherRestartAtMs >= 5000) {
      unawaited(_restartFetcher());
    }
  }

  void _recordFetcherHeartbeat([int heartbeat = 0]) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastInfoSuccessAtMs = now;
    _infoFailureStreak = 0;
    if (heartbeat > 0) _lastFetcherHeartbeatAtMs = heartbeat;
    final effectiveHeartbeat = heartbeat > 0
        ? heartbeat
        : _lastFetcherHeartbeatAtMs;
    if (effectiveHeartbeat > 0 &&
        now - effectiveHeartbeat > 2400 &&
        now - _lastFetcherRestartAtMs >= 5000) {
      unawaited(_restartFetcher());
    }
  }

  void _applyMediaSnapshot(MediaSnapshot snapshot) {
    if (!mounted) return;

    _mediaLifecycle.accept(snapshot);
  }

  void _acceptMediaUpdate(MediaSessionUpdate update) {
    if (!mounted) return;
    final snapshot = update.snapshot;
    WidgetDiagnostics.markOnce('firstMediaSnapshot');
    if (snapshot.sourceAppId.isNotEmpty && snapshot.title.trim().isNotEmpty) {
      WidgetDiagnostics.markOnce('firstIdentifiedMedia');
    }
    _recordFetcherHeartbeat(snapshot.fetcherUpdatedAtMs);
    AppState.recordFetcherProcess(
      _mediaProvider ?? AppState.mediaBackend,
      snapshot.processId,
    );

    final nextTrack = update.track;
    AppState.trackNavigation.observe(
      nextTrack,
      queue: AppState.queue.queue,
      shuffle: snapshot.isShuffleActive == true,
      wrap: snapshot.autoRepeatMode == 'list',
      positionMs: snapshot.positionMs,
      previousPositionMs: AppState.estimatedPlaybackPositionMs,
    );

    final bool metadataChanged =
        AppState.trackTitle != snapshot.title ||
        AppState.artistName != snapshot.artist ||
        (AppState.currentPlatformTrack?.sourceAppId ?? '') !=
            snapshot.sourceAppId;
    final bool versionChanged = AppState.trackVersion != snapshot.trackVersion;
    final bool playbackStateChanged = AppState.isPlaying != snapshot.isPlaying;
    final bool capabilitiesChanged =
        AppState.mediaCapabilities != snapshot.capabilities;
    if (update.startsTrack && AppState.playbackDurationMs > 0) {
      AppState.notifyTrackTransition();
    }

    if (versionChanged) AppState.trackVersion = snapshot.trackVersion;
    if (metadataChanged || playbackStateChanged || capabilitiesChanged) {
      _updateState(() {
        AppState.trackTitle = snapshot.title;
        AppState.artistName = snapshot.artist;
        AppState.trackVersion = snapshot.trackVersion;
        AppState.isPlaying = snapshot.isPlaying;
        AppState.mediaCapabilities = snapshot.capabilities;
      });
      if (playbackStateChanged) AppState.notifyBackgroundChanged();
    }

    AppState.currentPlatformTrack = nextTrack;
    AppState.isShuffleActive = snapshot.isShuffleActive;
    AppState.autoRepeatMode = snapshot.autoRepeatMode;
    AppState.updatePlaybackTimeline(
      positionMs: snapshot.positionMs,
      durationMs: snapshot.durationMs,
      updatedAtMs: snapshot.timelineUpdatedAtMs > 0
          ? snapshot.timelineUpdatedAtMs
          : DateTime.now().millisecondsSinceEpoch,
    );
    
    
    AppState.refreshQueue();
    if (playbackStateChanged) _syncSpectrumPolling();
    AppState.refreshLyrics();
    if (AppState.showLyrics) {
      AppState.lyrics.setPositionMs(AppState.lyricsPlaybackPositionMs);
    }

    _latestCoverVersion = snapshot.coverVersion;
    if (snapshot.coverVersion.isNotEmpty ||
        snapshot.legacyCoverBase64.isNotEmpty) {
      _missingCoverTimer?.cancel();
      _missingCoverTimer = null;
      _missingCoverIdentity = null;
    }
    if (snapshot.coverVersion.isNotEmpty &&
        snapshot.coverVersion != AppState.currentCoverVersion) {
      if (_artworkResources.findArtwork(snapshot.coverVersion) != null) {
        unawaited(
          _restoreCachedArtwork(snapshot.coverVersion).then((hit) {
            if (!hit &&
                mounted &&
                snapshot.coverVersion == _latestCoverVersion &&
                snapshot.coverVersion != AppState.currentCoverVersion) {
              _scheduleCoverFallback(snapshot.coverVersion);
            }
          }),
        );
      } else if (_mediaProvider?.isConnected == true) {
        _scheduleCoverFallback(snapshot.coverVersion);
      } else {
        unawaited(_loadCover(snapshot.coverVersion));
      }
    } else if (snapshot.coverVersion.isEmpty &&
        snapshot.legacyCoverBase64.isNotEmpty) {
      unawaited(_loadLegacyCover(snapshot.legacyCoverBase64));
    } else if (snapshot.coverVersion.isEmpty &&
        snapshot.legacyCoverBase64.isEmpty) {
      _deferMissingCoverClear();
    }
  }

  void _handleMediaProviderEvent(MediaProviderEvent event) {
    switch (event) {
      case MediaSnapshotEvent(:final snapshot):
        _applyMediaSnapshot(snapshot);
      case MediaSpectrumEvent(:final packet):
        final decoded = decodeSpectrumPacket(
          packet,
          expectedBandCount: AppState.spectrumBandCount,
          targetLevels: _spectrumDecodeBuffer,
        );
        if (decoded != null) {
          AppState.updateSpectrumTyped(decoded.levels, decoded.updatedAtMs);
        }
      case MediaArtworkEvent(:final version, :final bytes):
        unawaited(_applyCoverBytes(version, bytes));
      case MediaHeartbeatEvent():
        _recordFetcherHeartbeat();
      case MediaDisconnectedEvent():
        RuntimeCapabilities.instance.set(
          RuntimeCapability.mediaStream,
          const CapabilityStatus(
            CapabilityPhase.temporarilyUnavailable,
            reason: 'stream_disconnected',
          ),
        );
        AppState.mediaCommandSender = null;
        _syncMediaFallback();
        if (_latestCoverVersion.isNotEmpty &&
            _latestCoverVersion != AppState.currentCoverVersion) {
          unawaited(_loadCover(_latestCoverVersion));
        }
        if (mounted) _syncSpectrumPolling();
    }
  }

  Future<void> _connectMediaProvider() async {
    if (!mounted || _mediaProviderConnectInFlight) return;
    final provider = _mediaProvider ??= AppState.mediaBackend;
    if (provider.isConnected) return;
    _mediaProviderSubscription ??= provider.events.listen(
      _handleMediaProviderEvent,
    );
    _mediaProviderConnectInFlight = true;
    try {
      if (await provider.connect() && mounted) {
        if (!provider.usesExternalProcess) await _applySavedSource();
        if (!mounted) return;
        RuntimeCapabilities.instance.set(
          RuntimeCapability.mediaStream,
          const CapabilityStatus(CapabilityPhase.ready),
        );
        AppState.mediaCommandSender = provider.sendCommand;
        _syncMediaFallback();
        _syncSpectrumPolling();
      }
    } finally {
      _mediaProviderConnectInFlight = false;
    }
  }

  Future<void> _restartFetcher() async {
    if (!mounted || _fetcherRestartInFlight) return;
    if (!AppState.mediaBackend.usesExternalProcess) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFetcherRestartAtMs < 5000 || now < _nextFetcherRestartAtMs) {
      return;
    }
    _fetcherRestartInFlight = true;
    _lastFetcherRestartAtMs = now;
    try {
      if (!await _fetcherRuntime.dotnet.isAvailable()) return;
      if (!mounted) return;
      final exePath = await _fetcherRuntime.prepareExecutable();
      if (exePath == null) return;
      final pid = await _fetcherRuntime.start(exePath);
      if (pid == null || !mounted) return;
      AppState.fetcherPid = pid;
      _spectrumBinarySupported = true;
      _spectrumBinaryFailureStreak = 0;
      _lastFetcherHeartbeatAtMs = 0;
      if (await _waitForFetcherReady()) {
        await _applySavedSource();
        _fetcherRestartFailures = 0;
        _nextFetcherRestartAtMs = 0;
      } else {
        _fetcherRestartFailures++;
      }
    } catch (_) {
      _fetcherRestartFailures++;
    } finally {
      if (_fetcherRestartFailures > 0) {
        _nextFetcherRestartAtMs =
            DateTime.now().millisecondsSinceEpoch +
            math.min(60000, 5000 * (1 << math.min(_fetcherRestartFailures, 4)));
      }
      _fetcherRestartInFlight = false;
    }
  }

  void _startPollingTimers() {
    if (!mounted || _servicesStarted) return;
    _servicesStarted = true;
    unawaited(_connectMediaProvider());
    _syncMediaFallback();
    _syncSpectrumPolling();
  }

  void _syncMediaFallback() {
    if (!_servicesStarted || !mounted) return;
    if (_mediaProvider?.isConnected == true) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      _mediaReconnectTimer?.cancel();
      _mediaReconnectTimer = null;
      return;
    }
    _mediaReconnectTimer ??= DemandPollingLoop(
      interval: const Duration(seconds: 2),
      poll: () async {
        if (_mediaProvider?.isConnected != true) {
          await _connectMediaProvider();
        }
      },
    )..setActive(true);
    if (!AppState.mediaBackend.supportsLegacyPolling) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      return;
    }
    _pollingTimer ??= DemandPollingLoop(
      interval: const Duration(milliseconds: 300),
      poll: () async {
        if (_mediaProvider?.isConnected == true) return;
        if (_pollInFlight) return;
        _pollInFlight = true;
        try {
          final bytes = await _readLocalResponse(
            Uri.parse('http://localhost:12580/info'),
            timeout: const Duration(milliseconds: 420),
          );
          final fingerprint = _PlayerViewState._fingerprintBytes(bytes);
          if (_lastInfoLength == bytes.length &&
              _lastInfoFingerprint == fingerprint) {
            _recordFetcherHeartbeat();
            return;
          }
          _lastInfoLength = bytes.length;
          _lastInfoFingerprint = fingerprint;
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is! Map) {
            throw const FormatException('Invalid /info JSON');
          }
          final data = Map<String, dynamic>.from(decoded);
          _applyMediaSnapshot(MediaSnapshot.fromJson(data));
        } catch (_) {
          _recordFetcherFailure();
        } finally {
          _pollInFlight = false;
        }
      },
    )..setActive(true);
  }

  void _syncSpectrumPolling() {
    final bool shouldPoll =
        mounted &&
        _servicesStarted &&
        AppState.spectrumMode != SpectrumMode.off;
    final provider = _mediaProvider;
    if (provider?.isConnected == true) {
      _spectrumTimer?.cancel();
      _spectrumTimer = null;
      _spectrumPollingInterval = null;
      provider!.setSpectrumEnabled(shouldPoll);
      if (!shouldPoll) AppState.clearSpectrum();
      return;
    }
    if (!shouldPoll || !AppState.mediaBackend.supportsLegacyPolling) {
      _spectrumTimer?.cancel();
      _spectrumTimer = null;
      _spectrumPollingInterval = null;
      AppState.clearSpectrum();
      return;
    }
    final interval = AppState.isPlaying
        ? const Duration(milliseconds: 64)
        : const Duration(milliseconds: 250);
    if (_spectrumTimer != null && _spectrumPollingInterval == interval) return;
    _spectrumTimer?.cancel();
    _spectrumPollingInterval = interval;
    _spectrumTimer = Timer.periodic(interval, (_) => _pollSpectrum());
    unawaited(_pollSpectrum());
  }

  Future<void> _bootEngineAndListen() async {
    if (!AppState.mediaBackend.usesExternalProcess) {
      if (mounted) _startPollingTimers();
      return;
    }
    
    
    if (await _waitForFetcherReady(
      maxWait: const Duration(milliseconds: 220),
    )) {
      await _applySavedSource();
      _startPollingTimers();
      return;
    }

    if (!mounted) return;
    final exePath = await _fetcherRuntime.prepareExecutable();
    if (exePath == null || !mounted) return;

    if (!await _fetcherRuntime.dotnet.isAvailable()) {
      if (!mounted) return;
      final installed = await _askToInstallDotnet();
      if (!installed || !mounted) return;
    }

    if (!mounted) return;
    try {
      final pid = await _fetcherRuntime.start(exePath);
      if (pid == null || !mounted) return;
      AppState.fetcherPid = pid;
      _spectrumBinarySupported = true;
      _spectrumBinaryFailureStreak = 0;
    } catch (_) {
      return;
    }

    
    await _waitForFetcherReady();
    if (!mounted) return;

    await _applySavedSource();

    _startPollingTimers();
  }

  Future<void> _pollSpectrum() async {
    if (!mounted ||
        AppState.spectrumMode == SpectrumMode.off ||
        _spectrumPollInFlight) {
      return;
    }
    _spectrumPollInFlight = true;
    try {
      if (_spectrumBinarySupported) {
        try {
          final bytes = await _readLocalResponse(
            Uri.parse('http://localhost:12580/spectrum.bin'),
            timeout: const Duration(milliseconds: 220),
          );
          final packet = decodeSpectrumPacket(
            bytes,
            expectedBandCount: AppState.spectrumBandCount,
            targetLevels: _spectrumDecodeBuffer,
          );
          if (packet != null) {
            _spectrumBinaryFailureStreak = 0;
            AppState.updateSpectrumTyped(packet.levels, packet.updatedAtMs);
            return;
          }
          _spectrumBinaryFailureStreak++;
        } catch (_) {
          _spectrumBinaryFailureStreak++;
        }
        if (_spectrumBinaryFailureStreak >= 3) {
          _spectrumBinarySupported = false;
        }
      }
      final bytes = await _readLocalResponse(
        Uri.parse('http://localhost:12580/spectrum'),
        timeout: const Duration(milliseconds: 260),
      );
      final data = jsonDecode(utf8.decode(bytes));
      final levels = data['levels'];
      if (levels is List) {
        AppState.updateSpectrum(
          levels,
          (data['updatedAtMs'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {
      
    } finally {
      _spectrumPollInFlight = false;
    }
  }
}
