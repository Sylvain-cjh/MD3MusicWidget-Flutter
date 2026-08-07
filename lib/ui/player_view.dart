import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tm;

import '../core/app_state.dart';
import '../core/spectrum_packet.dart';
import 'widgets/dynamic_background.dart';
import 'widgets/track_controls.dart';
import 'widgets/slide_menu.dart';
import 'widgets/settings_panel.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({super.key});
  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView>
    with WindowListener, tm.TrayListener, TickerProviderStateMixin {
  Timer? _pollingTimer;
  Timer? _spectrumTimer;
  final HttpClient _httpBaseClient = HttpClient();
  int? _lastInfoFingerprint;
  int _lastInfoLength = 0;
  bool _pollInFlight = false;
  bool _spectrumPollInFlight = false;
  bool _spectrumBinarySupported = true;
  int _spectrumBinaryFailureStreak = 0;
  final Float32List _spectrumDecodeBuffer = Float32List(
    AppState.spectrumBandCount,
  );
  String _latestCoverVersion = "";
  bool _coverRequestInFlight = false;
  int _colorSchemeRequestSerial = 0;
  String _legacyCoverFingerprint = "";
  bool _fetcherRestartInFlight = false;
  int _lastFetcherRestartAtMs = 0;
  int _lastInfoSuccessAtMs = 0;
  int _lastFetcherHeartbeatAtMs = 0;
  int _infoFailureStreak = 0;
  final Map<String, ColorScheme> _colorSchemeCache = <String, ColorScheme>{};

  static int _fingerprintBytes(Uint8List bytes) {
    int hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  Future<Uint8List> _readLocalResponse(
    Uri uri, {
    required Duration timeout,
  }) async {
    HttpClientRequest? request;
    try {
      final future = () async {
        request = await _httpBaseClient.getUrl(uri);
        request!.persistentConnection = false;
        final response = await request!.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'MusicFetcher returned HTTP ${response.statusCode}',
            uri: uri,
          );
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      }();
      return await future.timeout(timeout);
    } catch (_) {
      request?.abort();
      rethrow;
    }
  }

  bool _isSettingsOpen = false;
  bool _isMenuOpen = false;
  String _menuSide = "right";
  double _menuTop = 12.0;

  String _settingsSide = "right";

  late AnimationController _menuAnimController;

  bool _isTransitioning = false;
  double _leftPadding = 0.0;
  int _windowTransitionSerial = 0;

  static const String _dotnetRuntimeDownloadUrl =
      'https://aka.ms/dotnet/8.0/dotnet-runtime-win-x64.exe';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    tm.trayManager.addListener(this);

    _menuAnimController = AnimationController(
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
      vsync: this,
    );
    unawaited(_initSystemTray());
    unawaited(_bootEngineAndListen());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _spectrumTimer?.cancel();
    windowManager.removeListener(this);
    tm.trayManager.removeListener(this);
    _httpBaseClient.close(force: true);
    _menuAnimController.dispose();
    super.dispose();
  }

  Future<void> _initSystemTray() async {
    await tm.trayManager.setIcon(
      Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png',
    );
    tm.Menu menu = tm.Menu(
      items: [
        tm.MenuItem(key: 'restore_interaction', label: '恢复鼠标交互'),
        tm.MenuItem.separator(),
        tm.MenuItem(key: 'rescue_exit', label: '完全退出挂件'),
      ],
    );
    await tm.trayManager.setContextMenu(menu);
  }

  @override
  void onTrayMenuItemClick(tm.MenuItem menuItem) {
    if (menuItem.key == 'restore_interaction') {
      AppState.isMousePassthrough = false;
      unawaited(windowManager.setIgnoreMouseEvents(false));
      unawaited(AppState.saveSettings());
    } else if (menuItem.key == 'rescue_exit') {
      windowManager.hide();
      unawaited(_exitApplication());
    }
  }

  Future<void> _exitApplication() async {
    _pollingTimer?.cancel();
    _spectrumTimer?.cancel();
    _httpBaseClient.close(force: true);
    try {
      await tm.trayManager.destroy();
    } catch (_) {}
    await AppState.exitApp();
  }

  Future<void> _updateColorScheme() async {
    final int serial = ++_colorSchemeRequestSerial;
    final provider = AppState.coverProvider;
    if (provider != null) {
      try {
        final coverIdentity = AppState.currentCoverVersion == 'legacy'
            ? _legacyCoverFingerprint
            : AppState.currentCoverVersion;
        final cacheKey =
            '$coverIdentity|${AppState.themeBrightness.name}|${AppState.themeVariant.name}';
        final cachedScheme = _colorSchemeCache[cacheKey];
        if (cachedScheme != null) {
          if (mounted && serial == _colorSchemeRequestSerial) {
            setState(() => AppState.currentScheme = cachedScheme);
            AppState.notifyBackgroundChanged();
          }
          return;
        }

        final newScheme = await ColorScheme.fromImageProvider(
          provider: provider,
          brightness: AppState.themeBrightness,
          dynamicSchemeVariant: AppState.themeVariant,
        );
        if (mounted && serial == _colorSchemeRequestSerial) {
          if (_colorSchemeCache.length >= 8) {
            _colorSchemeCache.remove(_colorSchemeCache.keys.first);
          }
          _colorSchemeCache[cacheKey] = newScheme;
          setState(() => AppState.currentScheme = newScheme);
          AppState.notifyBackgroundChanged();
        }
      } catch (_) {}
    } else {
      if (mounted && serial == _colorSchemeRequestSerial) {
        setState(() {
          AppState.currentScheme = ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E5B6B),
            brightness: AppState.themeBrightness,
            dynamicSchemeVariant: AppState.themeVariant,
          );
        });
        AppState.notifyBackgroundChanged();
      }
    }
  }

  Future<void> _clearCover() async {
    _latestCoverVersion = "";
    if (AppState.coverProvider == null &&
        AppState.currentCoverVersion.isEmpty) {
      return;
    }

    AppState.currentCoverVersion = "";
    AppState.currentRawBase64 = "";
    _legacyCoverFingerprint = "";
    if (mounted) {
      setState(() {
        AppState.coverProvider = null;
        AppState.bgBlurProvider = null;
      });
      await _updateColorScheme();
    }
  }

  Future<void> _loadCover(String version) async {
    _latestCoverVersion = version;
    if (version.isEmpty) {
      await _clearCover();
      return;
    }
    if (version == AppState.currentCoverVersion || _coverRequestInFlight) {
      return;
    }

    _coverRequestInFlight = true;
    try {
      final bytes = await _readLocalResponse(
        Uri.http('localhost:12580', '/cover'),
        timeout: const Duration(milliseconds: 700),
      );
      if (!mounted || bytes.isEmpty || version != _latestCoverVersion) return;

      
      
      final image = MemoryImage(bytes);
      AppState.currentCoverVersion = version;
      AppState.currentRawBase64 = "";
      setState(() {
        AppState.coverProvider = image;
        AppState.bgBlurProvider = ResizeImage(image, width: 256);
      });
      AppState.notifyBackgroundChanged();
      await _updateColorScheme();
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
      _legacyCoverFingerprint = fingerprint;
      AppState.currentRawBase64 = "";
      AppState.currentCoverVersion = "legacy";
      setState(() {
        AppState.coverProvider = image;
        AppState.bgBlurProvider = ResizeImage(image, width: 256);
      });
      AppState.notifyBackgroundChanged();
      await _updateColorScheme();
    } catch (_) {
      
    }
  }

  Future<bool> _hasDotnet8Runtime() async {
    if (!Platform.isWindows) return true;

    
    
    final sharedRuntime = Directory(
      r'C:\Program Files\dotnet\shared\Microsoft.NETCore.App',
    );
    try {
      if (sharedRuntime.existsSync() &&
          sharedRuntime
              .listSync(followLinks: false)
              .whereType<Directory>()
              .any(
                (entry) => entry.uri.pathSegments
                    .where((segment) => segment.isNotEmpty)
                    .last
                    .startsWith('8.'),
              )) {
        return true;
      }
    } catch (_) {}

    final candidates = <String>[
      r'C:\Program Files\dotnet\dotnet.exe',
      'dotnet.exe',
    ];
    for (final executable in candidates) {
      try {
        final result = await Process.run(executable, const [
          '--list-runtimes',
        ]).timeout(const Duration(milliseconds: 1400));
        if (result.exitCode == 0 &&
            RegExp(
              r'Microsoft\.NETCore\.App\s+8\.',
            ).hasMatch(result.stdout.toString())) {
          return true;
        }
      } catch (_) {
        
      }
    }
    return false;
  }

  Future<bool> _downloadAndInstallDotnet() async {
    Directory? temporaryDirectory;
    try {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'md3_music_widget_dotnet_',
      );
      final installer = File(
        '${temporaryDirectory.path}\\dotnet-runtime-win-x64.exe',
      );
      final request = await _httpBaseClient
          .getUrl(Uri.parse(_dotnetRuntimeDownloadUrl))
          .timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) return false;

      await response
          .pipe(installer.openWrite())
          .timeout(const Duration(minutes: 2));
      final process = await Process.start(installer.path, const [
        '/install',
        '/passive',
        '/norestart',
      ], mode: ProcessStartMode.normal);
      final exitCode = await process.exitCode.timeout(
        const Duration(minutes: 5),
      );
      return exitCode == 0 || exitCode == 3010;
    } catch (_) {
      return false;
    } finally {
      if (temporaryDirectory != null) {
        try {
          if (temporaryDirectory.existsSync()) {
            await temporaryDirectory.delete(recursive: true);
          }
        } catch (_) {
          
          
        }
      }
    }
  }

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
                          final success = await _downloadAndInstallDotnet();
                          if (!dialogContext.mounted) return;
                          final runtimeReady =
                              success && await _hasDotnet8Runtime();
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

  Future<bool> _fetcherNeedsRefresh() async {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final activeFetcher = File('$executableDir\\MusicFetcher.exe');
    final bundledFetcher = File('$executableDir\\runtime\\MusicFetcher.exe');
    if (!bundledFetcher.existsSync()) return false;
    if (!activeFetcher.existsSync()) return true;
    try {
      final bundledStat = await bundledFetcher.stat();
      final activeStat = await activeFetcher.stat();
      return activeStat.size != bundledStat.size ||
          bundledStat.modified.isAfter(activeStat.modified);
    } catch (_) {
      return true;
    }
  }

  Future<void> _stopFetcherProcess() async {
    await AppState.stopFetcherProcess();
    await Future<void>.delayed(const Duration(milliseconds: 45));
  }

  Future<String?> _prepareFetcherExecutable() async {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final workingDir = Directory.current.path;
    final activeFetcher = File('$executableDir\\MusicFetcher.exe');
    final bundledFetcher = File('$executableDir\\runtime\\MusicFetcher.exe');
    final workingFetcher = File('$workingDir\\MusicFetcher.exe');

    await _stopFetcherProcess();

    if (bundledFetcher.existsSync()) {
      try {
        final bundledStat = await bundledFetcher.stat();
        final activeStat = activeFetcher.existsSync()
            ? await activeFetcher.stat()
            : null;
        final needsRefresh =
            activeStat == null ||
            activeStat.size != bundledStat.size ||
            bundledStat.modified.isAfter(activeStat.modified);
        if (needsRefresh) {
          await bundledFetcher.copy(activeFetcher.path);
        }
      } catch (_) {
        
        
      }
      if (activeFetcher.existsSync()) return activeFetcher.path;
      return bundledFetcher.path;
    }

    if (activeFetcher.existsSync()) return activeFetcher.path;
    if (workingFetcher.existsSync()) return workingFetcher.path;
    return null;
  }

  Future<bool> _waitForFetcherReady({
    Duration maxWait = const Duration(milliseconds: 1800),
  }) async {
    final deadline = DateTime.now().add(maxWait);
    var delay = 35;
    while (DateTime.now().isBefore(deadline)) {
      try {
        await _readLocalResponse(
          Uri.parse('http://localhost:12580/info'),
          timeout: const Duration(milliseconds: 160),
        );
        return true;
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (delay < 120) delay += 20;
    }
    return false;
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

  void _recordFetcherHeartbeat(Map<String, dynamic> data) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastInfoSuccessAtMs = now;
    _infoFailureStreak = 0;
    final heartbeat = (data['fetcherUpdatedAtMs'] as num?)?.toInt() ?? 0;
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

  Future<void> _restartFetcher() async {
    if (!mounted || _fetcherRestartInFlight) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFetcherRestartAtMs < 5000) return;
    _fetcherRestartInFlight = true;
    _lastFetcherRestartAtMs = now;
    try {
      if (!await _hasDotnet8Runtime()) return;
      final exePath = await _prepareFetcherExecutable();
      if (exePath == null) return;
      AppState.csharpEngine = await Process.start(
        exePath,
        [],
        mode: ProcessStartMode.detached,
      );
      AppState.fetcherPid = AppState.csharpEngine!.pid;
      _spectrumBinarySupported = true;
      _spectrumBinaryFailureStreak = 0;
      _lastFetcherHeartbeatAtMs = 0;
      await _waitForFetcherReady();
    } catch (_) {
      
    } finally {
      _fetcherRestartInFlight = false;
    }
  }

  void _startPollingTimers() {
    if (_pollingTimer != null) return;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) async {
      if (_pollInFlight) return;
      _pollInFlight = true;
      try {
        final bytes = await _readLocalResponse(
          Uri.parse('http://localhost:12580/info'),
          timeout: const Duration(milliseconds: 420),
        );
        final fingerprint = _fingerprintBytes(bytes);
        if (_lastInfoLength == bytes.length &&
            _lastInfoFingerprint == fingerprint) {
          _recordFetcherHeartbeat(const <String, dynamic>{});
          return;
        }
        _lastInfoLength = bytes.length;
        _lastInfoFingerprint = fingerprint;
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) throw const FormatException('Invalid /info JSON');
        final data = Map<String, dynamic>.from(decoded);
        final int reportedFetcherPid =
            (data['processId'] as num?)?.toInt() ?? 0;
        if (reportedFetcherPid > 0) AppState.fetcherPid = reportedFetcherPid;
        _recordFetcherHeartbeat(data);

        if (mounted) {
          final String newTitle = data['title']?.toString() ?? "未知歌曲";
          final String newArtist = data['artist']?.toString() ?? "未知歌手";
          final String newTrackVersion = data['trackVersion']?.toString() ?? "";
          final bool newIsPlaying = data['isPlaying'] == true;
          final String coverVersion = data['coverVersion']?.toString() ?? "";
          final String legacyCoverBase64 =
              data['coverBase64']?.toString() ?? "";
          _latestCoverVersion = coverVersion;

          final bool trackChanged =
              AppState.trackTitle != newTitle ||
              AppState.artistName != newArtist ||
              AppState.trackVersion != newTrackVersion;
          final bool playbackStateChanged = AppState.isPlaying != newIsPlaying;
          if (trackChanged && AppState.playbackDurationMs > 0) {
            AppState.notifyTrackTransition();
          }

          if (trackChanged || playbackStateChanged) {
            setState(() {
              AppState.trackTitle = newTitle;
              AppState.artistName = newArtist;
              AppState.trackVersion = newTrackVersion;
              AppState.isPlaying = newIsPlaying;
            });
            AppState.notifyBackgroundChanged();
          }

          if (data.containsKey('durationMs')) {
            AppState.updatePlaybackTimeline(
              positionMs: (data['positionMs'] as num?)?.toDouble() ?? 0.0,
              durationMs: (data['durationMs'] as num?)?.toDouble() ?? 0.0,
              updatedAtMs:
                  (data['timelineUpdatedAtMs'] as num?)?.toInt() ??
                  DateTime.now().millisecondsSinceEpoch,
            );
          }

          if (coverVersion.isNotEmpty &&
              coverVersion != AppState.currentCoverVersion) {
            unawaited(_loadCover(coverVersion));
          } else if (coverVersion.isEmpty && legacyCoverBase64.isNotEmpty) {
            unawaited(_loadLegacyCover(legacyCoverBase64));
          } else if (coverVersion.isEmpty && legacyCoverBase64.isEmpty) {
            unawaited(_clearCover());
          }
        }
      } catch (_) {
        _recordFetcherFailure();
      } finally {
        _pollInFlight = false;
      }
    });
    _syncSpectrumPolling();
  }

  void _syncSpectrumPolling() {
    final bool shouldPoll =
        mounted &&
        _pollingTimer != null &&
        AppState.spectrumMode != SpectrumMode.off;
    if (!shouldPoll) {
      _spectrumTimer?.cancel();
      _spectrumTimer = null;
      AppState.clearSpectrum();
      return;
    }
    _spectrumTimer ??= Timer.periodic(
      const Duration(milliseconds: 64),
      (_) => _pollSpectrum(),
    );
    unawaited(_pollSpectrum());
  }

  Future<void> _bootEngineAndListen() async {
    final needsRefresh = await _fetcherNeedsRefresh();
    if (!needsRefresh &&
        await _waitForFetcherReady(
          maxWait: const Duration(milliseconds: 220),
        )) {
      _startPollingTimers();
      return;
    }

    final exePath = await _prepareFetcherExecutable();
    if (exePath == null) return;

    if (!await _hasDotnet8Runtime()) {
      final installed = await _askToInstallDotnet();
      if (!installed || !mounted) return;
    }

    try {
      AppState.csharpEngine = await Process.start(
        exePath,
        [],
        mode: ProcessStartMode.detached,
      );
      AppState.fetcherPid = AppState.csharpEngine!.pid;
      _spectrumBinarySupported = true;
      _spectrumBinaryFailureStreak = 0;
    } catch (_) {
      return;
    }

    
    await _waitForFetcherReady();
    if (!mounted) return;

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

  int _beginWindowTransition() {
    _windowTransitionSerial++;
    _isTransitioning = true;
    return _windowTransitionSerial;
  }

  bool _isCurrentWindowTransition(int serial) {
    return mounted && serial == _windowTransitionSerial;
  }

  Future<void> _animateToTargetLayout(int serial) async {
    final bounds = await windowManager.getBounds();
    final double absCardLeft = bounds.left + _leftPadding;

    
    
    final WidgetLayout targetLayout = AppState.widgetLayout;
    final bool targetSettingsOpen = _isSettingsOpen;
    final String targetSettingsSide = _settingsSide;

    final double targetW = targetSettingsOpen
        ? AppState.expandedWindowWidthOf(targetLayout)
        : AppState.baseWindowWidthOf(targetLayout);
    final double targetH = targetSettingsOpen
        ? AppState.expandedWindowHeightOf(targetLayout)
        : AppState.baseWindowHeightOf(targetLayout);
    final double targetLeftPadding =
        targetSettingsOpen &&
            targetLayout == WidgetLayout.vertical &&
            targetSettingsSide == "left"
        ? AppState.innerSettingsSideWidth
        : 0.0;

    final Rect targetRect = Rect.fromLTWH(
      absCardLeft - targetLeftPadding,
      bounds.top,
      targetW,
      targetH,
    );
    final Rect stage = bounds.expandToInclude(targetRect);

    _leftPadding = absCardLeft - stage.left;
    await windowManager.setBounds(stage, animate: false);
    if (!_isCurrentWindowTransition(serial)) return;
    setState(() {});
    await Future.delayed(
      AppState.layoutSwitchDuration + const Duration(milliseconds: 16),
    );

    if (!_isCurrentWindowTransition(serial)) return;

    final b2 = await windowManager.getBounds();
    final double currentAbsCardLeft = b2.left + _leftPadding;
    _leftPadding = targetLeftPadding;

    if (mounted) setState(() {});
    await windowManager.setBounds(
      Rect.fromLTWH(
        currentAbsCardLeft - _leftPadding,
        b2.top,
        targetW,
        targetH,
      ),
      animate: false,
    );
  }

  Future<void> _toggleSettings() async {
    final int serial = _beginWindowTransition();
    try {
      if (_isMenuOpen) {
        await _menuAnimController.reverse();
        _isMenuOpen = false;
      }
      setState(() {
        _isSettingsOpen = !_isSettingsOpen;
      });

      if (_isSettingsOpen) {
        _settingsSide = _menuSide;
      }
      await _animateToTargetLayout(serial);
    } finally {
      if (_isCurrentWindowTransition(serial)) {
        setState(() => _isTransitioning = false);
      }
    }
  }

  Future<void> _handleLayoutChanged() async {
    final int serial = _beginWindowTransition();
    try {
      _syncSpectrumPolling();
      unawaited(AppState.saveSettings());
      AppState.notifyBackgroundChanged();
      await _animateToTargetLayout(serial);
    } finally {
      if (_isCurrentWindowTransition(serial)) {
        setState(() => _isTransitioning = false);
      }
    }
  }

  Future<void> _handleWindowBehaviorChanged() async {
    await windowManager.setAlwaysOnTop(AppState.isAlwaysOnTop);
    await windowManager.setIgnoreMouseEvents(
      AppState.isMousePassthrough,
      forward: true,
    );
    unawaited(AppState.saveSettings());
  }

  Future<void> _openMenu(bool toLeft) async {
    if (_isSettingsOpen || _isTransitioning) return;
    try {
      final bounds = await windowManager.getBounds();
      final double menuWindowHeight = AppState.baseWindowHeightOf(
        AppState.widgetLayout,
      );
      if (toLeft) {
        _leftPadding = AppState.menuExtraSpace;
        setState(() {
          _menuSide = "left";
          _isMenuOpen = true;
        });
        await windowManager.setBounds(
          Rect.fromLTWH(
            bounds.left - AppState.menuExtraSpace,
            bounds.top,
            AppState.menuWindowWidth,
            menuWindowHeight,
          ),
          animate: false,
        );
      } else {
        _leftPadding = 0.0;
        setState(() {
          _menuSide = "right";
          _isMenuOpen = true;
        });
        await windowManager.setBounds(
          Rect.fromLTWH(
            bounds.left,
            bounds.top,
            AppState.menuWindowWidth,
            menuWindowHeight,
          ),
          animate: false,
        );
      }
      _menuAnimController.forward(from: 0.0);
    } catch (_) {}
  }

  Future<void> _closeMenu() async {
    if (!_isMenuOpen || _isTransitioning) return;
    try {
      await _menuAnimController.reverse();
      setState(() => _isMenuOpen = false);
      final bounds = await windowManager.getBounds();
      double resetLeft = bounds.left + _leftPadding;
      _leftPadding = 0.0;
      setState(() {});
      await windowManager.setBounds(
        Rect.fromLTWH(
          resetLeft,
          bounds.top,
          AppState.baseWindowWidthOf(AppState.widgetLayout),
          AppState.baseWindowHeightOf(AppState.widgetLayout),
        ),
        animate: false,
      );
    } catch (_) {}
  }

  void _handleSecondaryTap(TapDownDetails details) async {
    if (_isTransitioning) return;
    if (_isSettingsOpen) {
      _toggleSettings();
      return;
    }

    final double clickX = details.localPosition.dx;
    final double clickY = details.globalPosition.dy;
    final double maxTop =
        AppState.baseWindowHeightOf(AppState.widgetLayout) - 100.0;
    _menuTop = clickY.clamp(12.0, maxTop);

    final bool toLeft =
        clickX < AppState.baseWindowWidthOf(AppState.widgetLayout) / 2;

    if (_isMenuOpen) {
      if ((toLeft && _menuSide == 'left') ||
          (!toLeft && _menuSide == 'right')) {
        await _closeMenu();
      } else {
        await _closeMenu();
        await _openMenu(toLeft);
      }
    } else {
      await _openMenu(toLeft);
    }
  }

  Widget _buildSettingsPanel() {
    return SettingsPanel(
      onThemeChanged: () {
        setState(() {});
        unawaited(_updateColorScheme());
        unawaited(AppState.saveSettings());
      },
      onVisualChanged: () {
        setState(() {});
        _syncSpectrumPolling();
        unawaited(AppState.saveSettings());
      },
      onBackgroundChanged: () {
        AppState.notifyBackgroundChanged();
        unawaited(AppState.saveSettings());
      },
      onLayoutChanged: _handleLayoutChanged,
      onWindowBehaviorChanged: () {
        unawaited(_handleWindowBehaviorChanged());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isV = AppState.isVertical;
    bool isOpen = _isSettingsOpen;
    String side = _settingsSide;

    bool anchorRight = isV && side == "left" && (isOpen || _isTransitioning);

    double innerPlayerW = AppState.innerPlayerWidthOf(AppState.widgetLayout);
    double innerPlayerH = AppState.innerPlayerHeightOf(AppState.widgetLayout);
    double corePlayerH = AppState.corePlayerHeightOf(AppState.widgetLayout);
    bool spectrumVisible = AppState.spectrumMode != SpectrumMode.off;
    double playerHorizontalPadding = isV ? 24.0 : 16.0;

    double innerSettingsW = isV
        ? AppState.innerSettingsSideWidth
        : innerPlayerW;
    double innerSettingsH = isV
        ? innerPlayerH
        : AppState.innerSettingsPanelHeight;

    double pLeft = 0;
    double pTop = 0;
    double sLeft = 0;
    double sTop = 0;

    if (isOpen) {
      if (isV) {
        if (side == "left") {
          pLeft = innerSettingsW;
          sLeft = 0;
        } else {
          pLeft = 0;
          sLeft = innerPlayerW;
        }
      } else {
        pLeft = 0;
        sTop = innerPlayerH;
      }
    } else {
      if (isV) {
        if (side == "left") {
          pLeft = 0;
          sLeft = 0;
        } else {
          pLeft = 0;
          sLeft = innerPlayerW;
        }
      } else {
        pLeft = 0;
        sTop = 0;
      }
    }

    double containerW = isV
        ? (isOpen ? innerPlayerW + innerSettingsW : innerPlayerW)
        : innerPlayerW;
    double containerH = isV
        ? innerPlayerH
        : (isOpen ? innerPlayerH + innerSettingsH : innerPlayerH);

    return AnimatedTheme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: AppState.currentScheme,
        fontFamily: AppState.currentFontFamily == 'System Default'
            ? null
            : AppState.currentFontFamily,
        fontFamilyFallback: AppState.textFontFallback,
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: anchorRight ? null : _leftPadding,
                right: anchorRight ? 0.0 : null,
                top: 0,
                child: AnimatedContainer(
                  duration: AppState.layoutSwitchDuration,
                  curve: AppState.layoutSwitchCurve,
                  width: containerW,
                  height: containerH,
                  margin: EdgeInsets.all(AppState.cardMargin),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppState.currentScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      children: [
                        
                        
                        Positioned.fill(
                          child: const RepaintBoundary(
                            child: DynamicBackground(),
                          ),
                        ),

                        AnimatedPositioned(
                          duration: AppState.layoutSwitchDuration,
                          curve: AppState.layoutSwitchCurve,
                          left: sLeft,
                          top: sTop,
                          width: innerSettingsW,
                          height: innerSettingsH,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: isOpen ? 1.0 : 0.0,
                            child: IgnorePointer(
                              ignoring: !isOpen,
                              child: _buildSettingsPanel(),
                            ),
                          ),
                        ),

                        AnimatedPositioned(
                          duration: AppState.layoutSwitchDuration,
                          curve: AppState.layoutSwitchCurve,
                          left: pLeft,
                          top: pTop,
                          width: innerPlayerW,
                          height: innerPlayerH,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanStart: (_) => windowManager.startDragging(),
                            onSecondaryTapDown: (details) =>
                                _handleSecondaryTap(details),
                            onTapDown: (_) {
                              if (_isMenuOpen) _closeMenu();
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  width: innerPlayerW,
                                  height: corePlayerH,
                                  child: ContinuousTrackControls(
                                    isVertical: isV,
                                  ),
                                ),
                                AnimatedPositioned(
                                  duration: AppState.layoutSwitchDuration,
                                  curve: AppState.layoutSwitchCurve,
                                  left: playerHorizontalPadding,
                                  top: corePlayerH + 8.0,
                                  width:
                                      innerPlayerW -
                                      playerHorizontalPadding * 2,
                                  height: spectrumVisible ? 48.0 : 0.0,
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    opacity: spectrumVisible ? 1.0 : 0.0,
                                    child: IgnorePointer(
                                      ignoring: !spectrumVisible,
                                      child: MusicSpectrumPanel(
                                        mode: AppState.spectrumMode,
                                        isPlaying: AppState.isPlaying,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isMenuOpen)
                Positioned(
                  left: _menuSide == "left"
                      ? 0
                      : AppState.baseWindowWidthOf(AppState.widgetLayout),
                  top: _menuTop,
                  width: AppState.menuExtraSpace,
                  child: Align(
                    alignment: _menuSide == "left"
                        ? Alignment.topRight
                        : Alignment.topLeft,
                    child: SlideMenu(
                      animation: _menuAnimController,
                      menuSide: _menuSide,
                      onSettingsTap: _toggleSettings,
                      onExitTap: () {
                        windowManager.hide();
                        unawaited(_exitApplication());
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
