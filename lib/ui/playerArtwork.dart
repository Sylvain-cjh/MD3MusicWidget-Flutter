part of 'playerView.dart';


extension _PlayerArtwork on _PlayerViewState {
  Future<void> _updateColorScheme() async {
    if (WidgetDiagnostics.enabled && WidgetDiagnostics.suppressPalette) return;
    final int serial = ++_colorSchemeRequestSerial;
    final provider = AppState.coverProvider;
    if (provider != null) {
      try {
        final coverIdentity = AppState.currentCoverVersion == 'legacy'
            ? _legacyCoverFingerprint
            : AppState.currentCoverVersion;
        final newScheme = await WidgetDiagnostics.measure(
          'artwork.palette',
          () => _artworkResources.colorSchemes.resolve(
            identity: coverIdentity,
            provider: provider,
            brightness: AppState.themeBrightness,
            variant: AppState.themeVariant,
          ),
        );
        if (mounted &&
            serial == _colorSchemeRequestSerial &&
            AppState.currentScheme != newScheme) {
          _updateState(() => AppState.currentScheme = newScheme);
          AppState.notifyBackgroundChanged();
        }
      } catch (_) {}
    } else {
      if (mounted && serial == _colorSchemeRequestSerial) {
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E5B6B),
          brightness: AppState.themeBrightness,
          dynamicSchemeVariant: AppState.themeVariant,
        );
        if (AppState.currentScheme != scheme) {
          _updateState(() => AppState.currentScheme = scheme);
          AppState.notifyBackgroundChanged();
        }
      }
    }
  }

  Future<void> _clearCover() async {
    _coverFallbackTimer?.cancel();
    _missingCoverTimer?.cancel();
    _missingCoverIdentity = null;
    _latestCoverVersion = "";
    if (AppState.coverProvider == null &&
        AppState.currentCoverVersion.isEmpty) {
      return;
    }

    AppState.currentCoverVersion = "";
    AppState.currentRawBase64 = "";
    _legacyCoverFingerprint = "";
    unawaited(_artworkResources.retire(AppState.coverProvider));
    unawaited(_artworkResources.retire(AppState.bgBlurProvider));
    if (mounted) {
      _updateState(() {
        AppState.coverProvider = null;
        AppState.bgBlurProvider = null;
      });
      AppState.setArtworkTone(null);
      AppState.notifyBackgroundChanged();
      await _updateColorScheme();
    }
  }

  Future<void> _loadCover(String version) async {
    _coverFallbackTimer?.cancel();
    _missingCoverTimer?.cancel();
    _missingCoverIdentity = null;
    _latestCoverVersion = version;
    if (version.isEmpty) {
      await _clearCover();
      return;
    }
    if (!AppState.mediaBackend.supportsLegacyPolling) {
      await _requestArtwork(version);
      return;
    }
    if (version == AppState.currentCoverVersion || _coverRequestInFlight) {
      return;
    }

    _coverRequestInFlight = true;
    try {
      await _requestArtwork(version, allowLegacyFetch: true);
    } catch (_) {
      
    } finally {
      _coverRequestInFlight = false;
      final pendingVersion = _latestCoverVersion;
      if (mounted &&
          pendingVersion.isNotEmpty &&
          pendingVersion != AppState.currentCoverVersion) {
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          if (mounted &&
              pendingVersion == _latestCoverVersion &&
              pendingVersion != AppState.currentCoverVersion) {
            unawaited(_loadCover(pendingVersion));
          }
        });
      }
    }
  }

  bool _wantsArtwork(String version) =>
      mounted && version.isNotEmpty && version == _latestCoverVersion;

  Future<bool> _requestArtwork(
    String version, {
    Uint8List? bytes,
    bool allowLegacyFetch = false,
  }) {
    if (!_wantsArtwork(version)) return Future.value(false);
    if (version == AppState.currentCoverVersion &&
        AppState.coverProvider != null) {
      return Future.value(true);
    }
    return _artworkRequests.run(
      version,
      (request) => _prepareArtwork(version, request),
      bytes: bytes,
      allowLegacyFetch: allowLegacyFetch,
    );
  }

  Future<bool> _prepareArtwork(String version, ArtworkRequest request) async {
    final generation = _artworkResources.generation;
    try {
      var entry = _artworkResources.findArtwork(version);
      if (entry == null) {
        final saved = await WidgetDiagnostics.measure(
          'artwork.diskLookup',
          () => AppState.backgroundCacheStore.get(version),
        );
        if (!_wantsArtwork(version)) return false;
        if (saved != null && saved.isNotEmpty) entry = CachedArtwork(saved);
      }
      if (entry != null) {
        if (await _tryActivateArtwork(
          version,
          entry,
          generation,
          request,
          persistSource: false,
        )) {
          return true;
        }
        if (!_wantsArtwork(version)) return false;
        
        
        _artworkResources.forgetArtwork(version);
        unawaited(AppState.backgroundCacheStore.remove(version));
      }
      var bytes = request.bytes;
      if (bytes == null && request.allowLegacyFetch) {
        final fetched = await _readLocalResponse(
          Uri.http('localhost:12580', '/cover'),
          timeout: const Duration(milliseconds: 700),
        );
        bytes = request.bytes ?? fetched;
      }
      if (!_wantsArtwork(version) || bytes == null || bytes.isEmpty) {
        return false;
      }
      return await _tryActivateArtwork(
        version,
        CachedArtwork(bytes),
        generation,
        request,
        persistSource: true,
      );
    } catch (_) {
      
      return false;
    }
  }

  Future<bool> _tryActivateArtwork(
    String version,
    CachedArtwork entry,
    int generation,
    ArtworkRequest request, {
    required bool persistSource,
  }) async {
    if (!await WidgetDiagnostics.measure(
          'artwork.mainImageReady',
          () => _precacheArtwork(entry.cover),
        ) ||
        !_wantsArtwork(version) ||
        !await WidgetDiagnostics.measure(
          'artwork.backgroundImageReady',
          () => _precacheArtwork(entry.background),
        ) ||
        !_wantsArtwork(version)) {
      unawaited(_artworkResources.retire(entry.cover));
      unawaited(_artworkResources.retire(entry.background));
      return false;
    }
    Color? tone = entry.averageColor;
    if (tone == null && !entry.tonePrepared) {
      final saved = await WidgetDiagnostics.measure(
        'artwork.toneLookup',
        () => AppState.backgroundCacheStore.get('tone|$version'),
      );
      if (saved?.length == 4) {
        tone = Color(ByteData.sublistView(saved!).getUint32(0));
      }
      tone ??= await WidgetDiagnostics.measure(
        'artwork.averageTone',
        entry.prepareAverageColor,
      );
      if (tone != null && saved?.length != 4) {
        final bytes = Uint8List(4);
        ByteData.sublistView(bytes).setUint32(0, tone.toARGB32());
        unawaited(AppState.backgroundCacheStore.put('tone|$version', bytes));
      }
      entry.averageColor = tone;
    }
    entry.tonePrepared = true;
    if (!_wantsArtwork(version)) {
      unawaited(_artworkResources.retire(entry.cover));
      unawaited(_artworkResources.retire(entry.background));
      return false;
    }
    if (generation == _artworkResources.generation) {
      _artworkResources.rememberPreparedArtwork(version, entry);
    }
    AppState.setArtworkTone(tone);
    final previousCover = AppState.coverProvider;
    final previousBackground = AppState.bgBlurProvider;
    AppState.currentCoverVersion = version;
    AppState.currentRawBase64 = "";
    _artworkRequests.committed(version, request);
    _updateState(() {
      AppState.coverProvider = entry.cover;
      AppState.bgBlurProvider = entry.background;
    });
    AppState.notifyBackgroundChanged();
    WidgetDiagnostics.markOnce('firstArtworkActivated');
    if (WidgetDiagnostics.enabled) {
      WidgetDiagnostics.markOnce('artworkActivated:$version');
    }
    if (persistSource) {
      unawaited(AppState.backgroundCacheStore.put(version, entry.cover.bytes));
    }
    unawaited(_artworkResources.retire(previousCover));
    unawaited(_artworkResources.retire(previousBackground));
    await _updateColorScheme();
    return true;
  }

  Future<void> _applyCoverBytes(String version, Uint8List bytes) async {
    if (bytes.isEmpty || !_wantsArtwork(version)) return;
    _coverFallbackTimer?.cancel();
    await _requestArtwork(version, bytes: bytes);
  }

  Future<bool> _precacheArtwork(ImageProvider provider) async {
    Object? decodeError;
    try {
      final status = await provider.obtainCacheStatus(
        configuration: createLocalImageConfiguration(context),
        handleError: (error, stack) {
          decodeError = error;
        },
      );
      if (!mounted || decodeError != null) return false;
      
      
      if (status?.keepAlive == true && status?.pending == false) return true;
      await precacheImage(
        provider,
        context,
        onError: (error, stack) {
          decodeError = error;
        },
      );
    } catch (_) {
      return false;
    }
    return decodeError == null;
  }

  void _scheduleCoverFallback(String version) {
    _coverFallbackTimer?.cancel();
    _coverFallbackTimer = Timer(const Duration(milliseconds: 420), () {
      if (mounted &&
          version == _latestCoverVersion &&
          version != AppState.currentCoverVersion) {
        unawaited(_loadCover(version));
      }
    });
  }

  void _deferMissingCoverClear() {
    if (AppState.coverProvider == null && AppState.bgBlurProvider == null) {
      return;
    }
    final identity = AppState.currentPlatformTrack?.queueIdentity;
    if (_missingCoverTimer?.isActive == true &&
        _missingCoverIdentity == identity) {
      return;
    }
    _missingCoverTimer?.cancel();
    _missingCoverIdentity = identity;
    _missingCoverTimer = Timer(
      Duration(milliseconds: identity == null ? 600 : 1800),
      () {
        _missingCoverTimer = null;
        _missingCoverIdentity = null;
        if (mounted &&
            _latestCoverVersion.isEmpty &&
            AppState.currentPlatformTrack?.queueIdentity == identity) {
          unawaited(_clearCover());
        }
      },
    );
  }

  Future<void> _loadLegacyCover(String base64) async {
    if (base64.isEmpty) {
      await _clearCover();
      return;
    }
    final fingerprint = '${base64.length}:${base64.hashCode}';
    if (fingerprint == _legacyCoverFingerprint &&
        AppState.coverProvider != null) {
      return;
    }

    try {
      final bytes = base64Decode(base64);
      if (!mounted || bytes.isEmpty) return;
      final image = MemoryImage(bytes);
      final tone = await CachedArtwork(bytes).prepareAverageColor();
      if (!mounted) return;
      AppState.setArtworkTone(tone);
      _legacyCoverFingerprint = fingerprint;
      AppState.currentRawBase64 = "";
      AppState.currentCoverVersion = "legacy";
      _updateState(() {
        AppState.coverProvider = image;
        AppState.bgBlurProvider = ResizeImage(image, width: 256);
      });
      AppState.notifyBackgroundChanged();
      await _updateColorScheme();
    } catch (_) {
      
    }
  }
}
