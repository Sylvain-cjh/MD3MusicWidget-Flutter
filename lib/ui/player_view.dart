import 'dart:async';
import '../core/app_typography.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit, RenderBox;
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tm;

import '../core/app_state.dart';
import '../core/widget_diagnostics.dart';
import '../core/native_window_geometry.dart';
import '../core/artwork_resources.dart';
import '../core/media_provider.dart';
import '../core/music_fetcher_provider.dart';
import '../core/platform_provider.dart';
import '../core/spectrum_packet.dart';
import '../core/music_source_service.dart';
import 'animations/component_size_motion.dart';
import 'animations/next_up_presence_motion.dart';
import 'animations/lyrics_visual_motion.dart';
import 'animations/layout_morph_motion.dart';
import 'widgets/layout_backdrop_blend.dart';
import 'widgets/backdrop_capture_boundary.dart';
import 'widgets/smooth_rounded_clip.dart';
import 'widgets/dynamic_background.dart';
import 'widgets/locked_aspect_resize_area.dart';
import 'widgets/track_controls.dart';
import 'widgets/playback_pause_shade.dart';
import 'widgets/music_lyrics_panel.dart';
import 'widgets/music_next_up_panel.dart';
import 'widgets/spectrum_performance_row.dart';
import 'widgets/slide_menu.dart';
import 'widgets/settings_panel.dart';

class PlayerView extends StatefulWidget {
  final Future<void>? windowReady;
  
  final bool startPlatformServices;

  const PlayerView({
    super.key,
    this.windowReady,
    this.startPlatformServices = true,
  });
  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView>
    with WindowListener, tm.TrayListener, TickerProviderStateMixin {
  Timer? _pollingTimer;
  Timer? _spectrumTimer;
  Duration? _spectrumPollingInterval;
  Timer? _mediaReconnectTimer;
  MusicFetcherProvider? _mediaProvider;
  StreamSubscription<MediaProviderEvent>? _mediaProviderSubscription;
  bool _mediaProviderConnectInFlight = false;
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
  Timer? _coverFallbackTimer;
  Timer? _missingCoverTimer;
  String? _missingCoverIdentity;
  int _colorSchemeRequestSerial = 0;
  String _legacyCoverFingerprint = "";
  bool _fetcherRestartInFlight = false;
  int _lastFetcherRestartAtMs = 0;
  int _fetcherRestartFailures = 0;
  int _nextFetcherRestartAtMs = 0;
  late final ArtworkResources _artworkResources;
  int _lastInfoSuccessAtMs = 0;
  int _lastFetcherHeartbeatAtMs = 0;
  int _infoFailureStreak = 0;

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
  bool _menuResizeInFlight = false;
  bool _isSystemTrayReady = false;
  String _menuSide = "right";
  double _menuTop = 12.0;

  String _settingsSide = "right";

  late AnimationController _menuAnimController;
  late AnimationController _frameScaleController;
  late AnimationController _contentScaleController;
  late Listenable _componentSizeScaleListenable;
  double _frameScaleVelocity = 0.0;
  double _contentScaleVelocity = 0.0;
  double _componentSizeStageScale = AppState.componentScale;
  bool _isComponentSizeTransitioning = false;
  bool _customScaleCommitScheduled = false;
  double? _pendingCustomScale;
  Size? _pendingCustomViewport;
  Size? _pendingCustomDesign;
  int? _pendingCustomTransitionSerial;
  Timer? _resizeSaveTimer;

  bool _isTransitioning = false;
  double _leftPadding = 0.0;
  int _windowTransitionSerial = 0;
  bool _nextUpResizePending = false;
  bool _nextUpResizeInFlight = false;
  bool _nextUpSyncScheduled = false;
  final _resizeAreaKey = GlobalKey<LockedAspectResizeAreaState>();
  Timer? _nextUpRetryTimer;
  bool? _nextUpRequestedVisible;
  int _nextUpResizeFailures = 0;
  late final NextUpPresenceMotion _nextUpMotion;
  late bool _lastLyricsVisible;
  late final LyricsVisualMotion _lyricsVisualMotion;
  bool get _lyricsCollapsed =>
      AppState.showLyrics && !AppState.lyricsPanelVisible;
  Object? _backgroundAnchor;
  Widget? _anchoredPlayerBackground;
  late WidgetLayout _displayLayout;
  late final LayoutMorphMotion _layoutMotion;
  final _layoutFrameKey = GlobalKey();
  final _playerAnchorKey = GlobalKey();
  final _layoutBackdropKey = GlobalKey();
  ui.Image? _layoutPreviousBackdrop;
  bool _layoutPreparing = false;
  bool _layoutCleanupScheduled = false;
  Rect? _layoutHeldFrame;
  double? _layoutPlayerCanvasHeight;
  double? _menuBaseViewportWidth;
  double _menuNativeExtra = 0;

  static const String _dotnetRuntimeDownloadUrl =
      'https://aka.ms/dotnet/8.0/dotnet-runtime-win-x64.exe';

  @override
  void initState() {
    super.initState();
    _displayLayout = AppState.widgetLayout;
    _layoutMotion = LayoutMorphMotion(
      vsync: this,
      duration: AppState.layoutSwitchDuration,
      curve: AppState.layoutSwitchCurve,
    );
    _artworkResources = ArtworkResources();
    windowManager.addListener(this);
    tm.trayManager.addListener(this);
    _nextUpMotion = NextUpPresenceMotion(
      vsync: this,
      reserveSpace: _reserveNextUpSpace,
    );
    AppState.nextUpPreviewVisible.addListener(_onNextUpVisibilityChanged);
    AppState.nextUpPreviewController.refresh();
    if (AppState.nextUpPreviewVisible.value) _onNextUpVisibilityChanged();

    _menuAnimController = AnimationController(
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _frameScaleController = AnimationController.unbounded(
      value: AppState.componentScale,
      vsync: this,
    );
    _contentScaleController = AnimationController.unbounded(
      value: AppState.componentScale,
      vsync: this,
    );
    _componentSizeScaleListenable = Listenable.merge([
      _frameScaleController,
      _contentScaleController,
      _layoutMotion,
    ]);
    _lastLyricsVisible = AppState.lyricsPanelVisible;
    _lyricsVisualMotion = LyricsVisualMotion(
      vsync: this,
      collapsed: _lyricsCollapsed,
    );
    AppState.lyrics.addListener(_onLyricsVisibilityChanged);
    AppState.lyricsVisualRevision.addListener(_onLyricsVisibilityChanged);
    if (widget.startPlatformServices) {
      unawaited(_initSystemTray());
      unawaited(_bootEngineAndListen());
    }
    if (WidgetDiagnostics.enabled) {
      WidgetDiagnostics.actions.addAll({
        'menuOpen': (value) => _openMenu(value == true),
        'menuClose': (_) => _closeMenu(),
        'settings': (_) => _toggleSettings(),
        'layout': (value) async {
          AppState.widgetLayout = value as WidgetLayout;
          await _handleLayoutChanged();
        },
        'artwork': (value) async {
          final data = value as (String, Uint8List);
          _latestCoverVersion = data.$1;
          await _applyCoverBytes(data.$1, data.$2);
        },
        'track': (value) async => _applyMediaSnapshot(value as MediaSnapshot),
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetDiagnostics.mark('playerFirstFrame');
      });
    }
  }

  @override
  void dispose() {
    _nextUpRetryTimer?.cancel();
    AppState.lyrics.removeListener(_onLyricsVisibilityChanged);
    AppState.lyricsVisualRevision.removeListener(_onLyricsVisibilityChanged);
    _lyricsVisualMotion.dispose();
    _pollingTimer?.cancel();
    _spectrumTimer?.cancel();
    _mediaReconnectTimer?.cancel();
    _coverFallbackTimer?.cancel();
    _missingCoverTimer?.cancel();
    _missingCoverIdentity = null;
    AppState.mediaCommandSender = null;
    unawaited(_mediaProviderSubscription?.cancel());
    unawaited(_mediaProvider?.close());
    _resizeSaveTimer?.cancel();
    _artworkResources.dispose();
    windowManager.removeListener(this);
    tm.trayManager.removeListener(this);
    AppState.nextUpPreviewVisible.removeListener(_onNextUpVisibilityChanged);
    _nextUpMotion.dispose();
    AppState.nextUpPanelOccupied = false;
    _httpBaseClient.close(force: true);
    _menuAnimController.dispose();
    _frameScaleController.dispose();
    _contentScaleController.dispose();
    _layoutMotion.dispose();
    _layoutPreviousBackdrop?.dispose();
    super.dispose();
  }

  double get _frameScale => _frameScaleController.value;
  set _frameScale(double value) => _frameScaleController.value = value;

  double get _contentScale => _contentScaleController.value;
  set _contentScale(double value) => _contentScaleController.value = value;

  TickerFuture _animateFrameScale(double target) {
    return _frameScaleController.animateWith(
      ComponentSizeMotion.frameSimulation(
        begin: _frameScale,
        end: target,
        velocity: _frameScaleVelocity,
      ),
    );
  }

  TickerFuture _animateContentScale(double target) {
    return _contentScaleController.animateWith(
      ComponentSizeMotion.contentSimulation(
        begin: _contentScale,
        end: target,
        velocity: _contentScaleVelocity,
      ),
    );
  }

  Future<void> _initSystemTray() async {
    try {
      final String iconAsset = Platform.isWindows
          ? 'images/tray_icon.ico'
          : 'images/tray_icon.png';
      if (Platform.isWindows) {
        final String bundledIconPath = [
          File(Platform.resolvedExecutable).parent.path,
          'data',
          'flutter_assets',
          'images',
          'tray_icon.ico',
        ].join(Platform.pathSeparator);
        if (!File(bundledIconPath).existsSync()) {
          throw FileSystemException('托盘图标资源不存在', bundledIconPath);
        }
      }

      await tm.trayManager.setIcon(iconAsset);
      await tm.trayManager.setToolTip('MD3 Music Widget');
      final tm.Menu menu = tm.Menu(
        items: [
          tm.MenuItem(key: 'restore_interaction', label: '恢复鼠标交互'),
          tm.MenuItem.separator(),
          tm.MenuItem(key: 'rescue_exit', label: '完全退出挂件'),
        ],
      );
      await tm.trayManager.setContextMenu(menu);
      if (!mounted) return;
      setState(() => _isSystemTrayReady = true);

      await (widget.windowReady ?? Future<void>.value());
      if (!mounted) return;
      await windowManager.setIgnoreMouseEvents(
        AppState.isMousePassthrough,
        forward: true,
      );
    } catch (error, stackTrace) {
      debugPrint('系统托盘初始化失败: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _restoreMouseInteraction(flushSettings: true);
    }
  }

  Future<void> _showTrayContextMenu() async {
    if (!_isSystemTrayReady) {
      await _restoreMouseInteraction(flushSettings: true);
      return;
    }
    try {
      await tm.trayManager.popUpContextMenu();
    } catch (error) {
      debugPrint('系统托盘菜单打开失败: $error');
      await _restoreMouseInteraction(flushSettings: true);
    }
  }

  Future<void> _restoreMouseInteraction({bool flushSettings = false}) async {
    AppState.isMousePassthrough = false;
    try {
      await windowManager.setIgnoreMouseEvents(false, forward: true);
    } catch (error) {
      debugPrint('恢复鼠标交互失败: $error');
    }
    if (mounted) setState(() {});
    await AppState.saveSettings();
    if (flushSettings) await AppState.flushSettings();
  }

  @override
  void onTrayIconMouseDown() {
    if (AppState.isMousePassthrough) {
      unawaited(_restoreMouseInteraction(flushSettings: true));
    } else {
      unawaited(_showTrayContextMenu());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_showTrayContextMenu());
  }

  @override
  void onTrayMenuItemClick(tm.MenuItem menuItem) {
    if (menuItem.key == 'restore_interaction') {
      unawaited(_restoreMouseInteraction(flushSettings: true));
    } else if (menuItem.key == 'rescue_exit') {
      windowManager.hide();
      unawaited(_exitApplication());
    }
  }

  Future<void> _exitApplication() async {
    _pollingTimer?.cancel();
    _spectrumTimer?.cancel();
    _mediaReconnectTimer?.cancel();
    _coverFallbackTimer?.cancel();
    AppState.mediaCommandSender = null;
    await _mediaProviderSubscription?.cancel();
    await _mediaProvider?.close();
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
        final newScheme = await _artworkResources.colorSchemes.resolve(
          identity: coverIdentity,
          provider: provider,
          brightness: AppState.themeBrightness,
          variant: AppState.themeVariant,
        );
        if (mounted &&
            serial == _colorSchemeRequestSerial &&
            AppState.currentScheme != newScheme) {
          setState(() => AppState.currentScheme = newScheme);
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
          setState(() => AppState.currentScheme = scheme);
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
      setState(() {
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
    if (version == AppState.currentCoverVersion || _coverRequestInFlight) {
      return;
    }

    _coverRequestInFlight = true;
    try {
      if (await _restoreCachedArtwork(version)) return;
      final bytes = await _readLocalResponse(
        Uri.http('localhost:12580', '/cover'),
        timeout: const Duration(milliseconds: 700),
      );
      await _applyCoverBytes(version, bytes);
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

  Future<bool> _restoreCachedArtwork(String version) async {
    var entry = _artworkResources.findArtwork(version);
    if (entry == null) {
      final bytes = await AppState.backgroundCacheStore.get(version);
      if (!mounted || version != _latestCoverVersion) return true;
      if (bytes != null) entry = CachedArtwork(bytes);
    }
    if (entry == null) return false;
    if (!await _precacheArtwork(entry.cover) ||
        !await _precacheArtwork(entry.background)) {
      _artworkResources.forgetArtwork(version);
      unawaited(AppState.backgroundCacheStore.remove(version));
      return false;
    }
    if (!mounted || version != _latestCoverVersion) return true;
    _artworkResources.rememberPreparedArtwork(version, entry);
    if (version != AppState.currentCoverVersion) {
      await _activateArtwork(version, entry, persistSource: false);
    }
    return true;
  }

  Future<void> _activateArtwork(
    String version,
    CachedArtwork entry, {
    bool persistSource = true,
  }) async {
    Color? tone = entry.averageColor;
    if (tone == null) {
      final saved = await AppState.backgroundCacheStore.get('tone|$version');
      if (saved?.length == 4) {
        tone = Color(ByteData.sublistView(saved!).getUint32(0));
      }
      tone ??= await entry.prepareAverageColor();
      if (tone != null && saved?.length != 4) {
        final bytes = Uint8List(4);
        ByteData.sublistView(bytes).setUint32(0, tone.toARGB32());
        unawaited(AppState.backgroundCacheStore.put('tone|$version', bytes));
      }
      entry.averageColor = tone;
    }
    if (!mounted || version != _latestCoverVersion) return;
    AppState.setArtworkTone(tone);
    final previousCover = AppState.coverProvider;
    final previousBackground = AppState.bgBlurProvider;
    AppState.currentCoverVersion = version;
    AppState.currentRawBase64 = "";
    setState(() {
      AppState.coverProvider = entry.cover;
      AppState.bgBlurProvider = entry.background;
    });
    AppState.notifyBackgroundChanged();
    if (persistSource) {
      unawaited(AppState.backgroundCacheStore.put(version, entry.cover.bytes));
    }
    unawaited(_artworkResources.retire(previousCover));
    unawaited(_artworkResources.retire(previousBackground));
    await _updateColorScheme();
  }

  Future<void> _applyCoverBytes(String version, Uint8List bytes) async {
    if (!mounted ||
        version.isEmpty ||
        bytes.isEmpty ||
        version != _latestCoverVersion) {
      return;
    }
    _coverFallbackTimer?.cancel();
    if (version == AppState.currentCoverVersion &&
        AppState.coverProvider != null) {
      return;
    }
    if (await _restoreCachedArtwork(version)) return;

    final entry = CachedArtwork(bytes);
    final coverReady = await _precacheArtwork(entry.cover);
    if (!mounted || version != _latestCoverVersion || !coverReady) {
      unawaited(_artworkResources.retire(entry.cover));
      
      
      return;
    }
    final backgroundReady = await _precacheArtwork(entry.background);
    if (!mounted || version != _latestCoverVersion || !backgroundReady) {
      unawaited(_artworkResources.retire(entry.cover));
      unawaited(_artworkResources.retire(entry.background));
      return;
    }
    _artworkResources.rememberPreparedArtwork(version, entry);
    await _activateArtwork(version, entry);
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
        final infoBytes = await _readLocalResponse(
          Uri.parse('http://localhost:12580/info'),
          timeout: const Duration(milliseconds: 160),
        );
        final info = jsonDecode(utf8.decode(infoBytes));
        if (info is Map && info['processId'] is num) {
          final pid = (info['processId'] as num).toInt();
          if (pid > 0) AppState.fetcherPid = pid;
        }
        return true;
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (delay < 120) delay += 20;
    }
    return false;
  }

  Future<bool> _applySavedSource() async {
    try {
      await MusicSourceService.selectSource(AppState.selectedSourceAppId);
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
    _recordFetcherHeartbeat(snapshot.fetcherUpdatedAtMs);
    if (snapshot.processId > 0) AppState.fetcherPid = snapshot.processId;
    if (!mounted) return;

    final nextTrack = PlatformTrack.fromSnapshot(snapshot);
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
    final bool trackChanged = metadataChanged || versionChanged;
    final bool playbackStateChanged = AppState.isPlaying != snapshot.isPlaying;
    final bool capabilitiesChanged =
        AppState.mediaCapabilities != snapshot.capabilities;
    final bool sameTrackRestarted =
        versionChanged &&
        !metadataChanged &&
        snapshot.positionMs < 5000 &&
        AppState.estimatedPlaybackPositionMs > 5000;
    if ((metadataChanged || sameTrackRestarted) &&
        AppState.playbackDurationMs > 0) {
      AppState.notifyTrackTransition();
    }

    if (trackChanged || playbackStateChanged || capabilitiesChanged) {
      setState(() {
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
        AppState.mediaCommandSender = null;
        if (_latestCoverVersion.isNotEmpty &&
            _latestCoverVersion != AppState.currentCoverVersion) {
          unawaited(_loadCover(_latestCoverVersion));
        }
        if (mounted) _syncSpectrumPolling();
    }
  }

  Future<void> _connectMediaProvider() async {
    if (!mounted || _mediaProviderConnectInFlight) return;
    final provider = _mediaProvider ??= MusicFetcherProvider();
    if (provider.isConnected) return;
    _mediaProviderSubscription ??= provider.events.listen(
      _handleMediaProviderEvent,
    );
    _mediaProviderConnectInFlight = true;
    try {
      if (await provider.connect() && mounted) {
        AppState.mediaCommandSender = provider.sendCommand;
        _syncSpectrumPolling();
      }
    } finally {
      _mediaProviderConnectInFlight = false;
    }
  }

  Future<void> _restartFetcher() async {
    if (!mounted || _fetcherRestartInFlight) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFetcherRestartAtMs < 5000 || now < _nextFetcherRestartAtMs) {
      return;
    }
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
    if (_pollingTimer != null) return;
    unawaited(_connectMediaProvider());
    _mediaReconnectTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (_mediaProvider?.isConnected != true) {
        unawaited(_connectMediaProvider());
      }
    });
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) async {
      if (_mediaProvider?.isConnected == true) return;
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
          _recordFetcherHeartbeat();
          return;
        }
        _lastInfoLength = bytes.length;
        _lastInfoFingerprint = fingerprint;
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map) throw const FormatException('Invalid /info JSON');
        final data = Map<String, dynamic>.from(decoded);
        _applyMediaSnapshot(MediaSnapshot.fromJson(data));
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
    final provider = _mediaProvider;
    if (provider?.isConnected == true) {
      _spectrumTimer?.cancel();
      _spectrumTimer = null;
      _spectrumPollingInterval = null;
      provider!.setSpectrumEnabled(shouldPoll);
      if (!shouldPoll) AppState.clearSpectrum();
      return;
    }
    if (!shouldPoll) {
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
    final needsRefresh = await _fetcherNeedsRefresh();
    if (!needsRefresh &&
        await _waitForFetcherReady(
          maxWait: const Duration(milliseconds: 220),
        ) &&
        await _applySavedSource()) {
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

  int _beginWindowTransition() {
    if (!_layoutMotion.active &&
        !_layoutPreparing &&
        _layoutMotion.holding &&
        AppState.widgetLayout == _displayLayout) {
      
      
      _layoutMotion.finish();
    }
    if (_layoutMotion.active || AppState.widgetLayout != _displayLayout) {
      _layoutMotion.freeze();
    }
    if (_nextUpResizeInFlight) {
      _nextUpResizePending = true;
      _nextUpMotion.cancel();
    }
    _windowTransitionSerial++;
    _frameScaleVelocity = _frameScaleController.isAnimating
        ? _frameScaleController.velocity
        : 0.0;
    _contentScaleVelocity = _contentScaleController.isAnimating
        ? _contentScaleController.velocity
        : 0.0;
    _frameScaleController.stop();
    _contentScaleController.stop();
    _isComponentSizeTransitioning = false;
    _isTransitioning = true;
    return _windowTransitionSerial;
  }

  Size _designWindowSize({
    required WidgetLayout layout,
    required bool settingsOpen,
  }) => Size(
    settingsOpen
        ? AppState.expandedWindowWidthOf(layout)
        : AppState.baseWindowWidthOf(layout),
    settingsOpen
        ? AppState.expandedWindowHeightOf(layout)
        : AppState.baseWindowHeightOf(layout),
  );

  bool _rectNearlyEquals(Rect first, Rect second) {
    return NativeWindowGeometry.sameBounds(
      first,
      second,
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  void _onLyricsVisibilityChanged() {
    if (!mounted) return;
    final visible = AppState.lyricsPanelVisible;
    if (visible == _lastLyricsVisible &&
        _lyricsVisualMotion.collapsed == _lyricsCollapsed) {
      return;
    }
    setState(() => _lastLyricsVisible = visible);
    _lyricsVisualMotion.update(
      _lyricsCollapsed,
      reduceMotion: MediaQuery.maybeOf(context)?.disableAnimations ?? false,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lyricsVisualMotion.update(
      _lyricsCollapsed,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
  }

  Widget _followLyrics(
    Widget child, {
    bool verticalSettings = false,
    double? settingsHeight,
  }) => AnimatedBuilder(
    animation: _lyricsVisualMotion.animation,
    child: child,
    builder: (context, child) {
      final inset = AppState.showLyrics
          ? LyricsVisualMotion.reservedExtent *
                _lyricsVisualMotion.animation.value
          : 0.0;
      return Transform.translate(
        offset: verticalSettings ? Offset.zero : Offset(0, -inset),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: verticalSettings
                ? math.max(0.0, settingsHeight! - inset)
                : null,
            child: child,
          ),
        ),
      );
    },
  );

  Widget _clipPlayerVisualHeight(Widget child, double fullHeight) =>
      AnimatedBuilder(
        animation: _lyricsVisualMotion.animation,
        child: child,
        builder: (context, child) {
          final inset = AppState.showLyrics
              ? 64 * _lyricsVisualMotion.animation.value
              : 0.0;
          final canvasHeight = _layoutPlayerCanvasHeight ?? fullHeight;
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: math.max(0.0, canvasHeight - inset),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: canvasHeight,
                  maxHeight: canvasHeight,
                  child: child,
                ),
              ),
            ),
          );
        },
      );

  void _onNextUpVisibilityChanged() {
    if (!mounted) return;
    final target = AppState.nextUpPreviewVisible.value;
    if (_nextUpRequestedVisible != target) {
      _nextUpRequestedVisible = target;
      _nextUpResizeFailures = 0;
      _nextUpRetryTimer?.cancel();
      _nextUpRetryTimer = null;
    }
    _nextUpResizePending = true;
    setState(() {});
    _nextUpMotion.cancel();
    if (_nextUpSyncScheduled) return;
    _nextUpSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nextUpSyncScheduled = false;
      if (!mounted) return;
      unawaited(_resizeWindowForNextUp());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _reserveNextUpSpace(bool occupied) async {
    if (!mounted) return;
    await _resizeAreaKey.currentState?.waitForIdle();
    if (!mounted) return;
    if (occupied && !AppState.nextUpPreviewVisible.value) return;
    if (_isTransitioning) {
      AppState.nextUpPanelOccupied = occupied;
      setState(() {});
      _nextUpResizePending = true;
      return;
    }
    
    
    
    if (!occupied) {
      AppState.nextUpPanelOccupied = false;
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final bounds = await windowManager.getBounds();
    if (!mounted) return;
    if (occupied && !AppState.nextUpPreviewVisible.value) return;
    if (_isTransitioning) {
      _nextUpResizePending = true;
      return;
    }
    final designHeight = _designWindowSize(
      layout: AppState.widgetLayout,
      settingsOpen: _isSettingsOpen,
    ).height;
    if (AppState.isCustomComponentSize) {
      final designWidth = _designWindowSize(
        layout: AppState.widgetLayout,
        settingsOpen: _isSettingsOpen,
      ).width;
      final scale = ComponentSizeMotion.stableWidthScale(
        width: bounds.width - (_isMenuOpen ? AppState.menuExtraSpace : 0),
        designWidth: designWidth,
        referenceScale: _frameScale,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        minimumScale: AppState.minimumComponentScale,
        maximumScale: AppState.maximumComponentScale,
      );
      _frameScale = scale;
      _contentScale = scale;
      AppState.customComponentScale = scale / AppState.standardDisplayScale;
    }
    final targetExtent = occupied ? 64.0 : 0.0;
    final targetHeight =
        (designHeight +
            targetExtent -
            AppState.nextUpPanelExtentOf(AppState.widgetLayout)) *
        _frameScale;
    if ((bounds.height - targetHeight).abs() > 0.5) {
      await windowManager.setBounds(
        Rect.fromLTWH(bounds.left, bounds.top, bounds.width, targetHeight),
        animate: false,
      );
    }
    if (!mounted) return;
    if (occupied && !AppState.nextUpPreviewVisible.value) return;
    AppState.nextUpPanelOccupied = occupied;
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _resizeWindowForNextUp() async {
    if (!mounted ||
        !_nextUpResizePending ||
        _nextUpResizeInFlight ||
        _isTransitioning ||
        _menuResizeInFlight) {
      return;
    }
    _nextUpResizePending = false;
    _nextUpResizeInFlight = true;
    _nextUpRetryTimer?.cancel();
    _nextUpRetryTimer = null;
    try {
      await _nextUpMotion.setVisible(
        AppState.nextUpPreviewVisible.value,
        reduceMotion: MediaQuery.maybeOf(context)?.disableAnimations ?? false,
      );
      _nextUpResizeFailures = 0;
    } catch (error) {
      debugPrint('下一首预告窗口尺寸同步失败: $error');
      _nextUpResizeFailures++;
      if (mounted && _nextUpResizeFailures < 3) {
        _nextUpResizePending = true;
        _nextUpRetryTimer = Timer(
          Duration(milliseconds: _nextUpResizeFailures == 1 ? 160 : 400),
          () {
            _nextUpRetryTimer = null;
            if (mounted) _onNextUpVisibilityChanged();
          },
        );
      }
    } finally {
      _nextUpResizeInFlight = false;
      if (mounted) setState(() {});
      if (mounted &&
          _nextUpResizePending &&
          !_isTransitioning &&
          _nextUpRetryTimer == null) {
        _onNextUpVisibilityChanged();
      }
    }
  }

  Future<void> _applyComponentSizeToTarget(int serial) async {
    final bool disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Rect bounds = await windowManager.getBounds();
    final WidgetLayout targetLayout = AppState.widgetLayout;
    final bool targetSettingsOpen = _isSettingsOpen;
    final String targetSettingsSide = _settingsSide;
    final Size designSize = _designWindowSize(
      layout: targetLayout,
      settingsOpen: targetSettingsOpen,
    );
    final double targetScale = AppState.componentScale;
    final double absCardLeft = bounds.left + _leftPadding;
    final double targetLeftPadding =
        targetSettingsOpen &&
            targetLayout == WidgetLayout.vertical &&
            targetSettingsSide == 'left'
        ? AppState.innerSettingsSideWidth * targetScale
        : 0.0;
    final Rect targetRect = Rect.fromLTWH(
      absCardLeft - targetLeftPadding,
      bounds.top,
      designSize.width * targetScale,
      designSize.height * targetScale,
    );
    final Rect stage = bounds.expandToInclude(targetRect);

    if (disableAnimations) {
      setState(() {
        _frameScale = targetScale;
        _contentScale = targetScale;
        _componentSizeStageScale = targetScale;
        _leftPadding = targetLeftPadding;
        _isComponentSizeTransitioning = false;
      });
      if (!_rectNearlyEquals(bounds, targetRect)) {
        await windowManager.setBounds(targetRect, animate: false);
      }
      return;
    } else {
      _componentSizeStageScale = math.max(_frameScale, targetScale);
      _leftPadding = absCardLeft - stage.left;
      setState(() {
        _isComponentSizeTransitioning = true;
      });

      final Future<void> stageResize = _rectNearlyEquals(bounds, stage)
          ? Future<void>.value()
          : windowManager.setBounds(stage, animate: false);
      await Future.wait<void>([
        stageResize,
        WidgetsBinding.instance.endOfFrame,
      ]);
      if (!_isCurrentWindowTransition(serial)) return;

      final TickerFuture frameMotion = _animateFrameScale(targetScale);
      final Future<void> contentMotion = () async {
        await Future<void>.delayed(ComponentSizeMotion.contentDelay);
        if (!_isCurrentWindowTransition(serial)) return;
        await _animateContentScale(targetScale).orCancel;
      }();
      try {
        await Future.wait<void>([frameMotion.orCancel, contentMotion]);
      } on TickerCanceled {
        return;
      }
      if (!_isCurrentWindowTransition(serial)) return;
      setState(() {
        _frameScale = targetScale;
        _contentScale = targetScale;
        _componentSizeStageScale = targetScale;
      });
    }

    _leftPadding = targetLeftPadding;
    if (mounted) {
      setState(() {
        _isComponentSizeTransitioning = false;
      });
    }
    if (!_rectNearlyEquals(stage, targetRect)) {
      await windowManager.setBounds(targetRect, animate: false);
    }
  }

  bool _isCurrentWindowTransition(int serial) {
    return mounted && serial == _windowTransitionSerial;
  }

  Future<ui.Image?> _captureLayoutBackdrop(Rect frame, Rect bounds) async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      final render = _layoutBackdropKey.currentContext?.findRenderObject();
      if (render is! RenderBackdropCaptureBoundary || !render.hasSize) {
        return null;
      }
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final origin = bounds.topLeft + render.localToGlobal(Offset.zero);
      
      
      return await render.capture(
        (frame.topLeft - origin) & frame.size,
        pixelRatio: ratio,
      );
    } catch (error) {
      debugPrint('布局背景过渡画面采集失败，使用连续布局回退: $error');
      return null;
    }
  }

  void _retireLayoutImage(ui.Image? image) {
    if (image == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  void _clearLayoutMorph() {
    if (!mounted) return;
    final old = _layoutPreviousBackdrop;
    setState(() {
      _layoutMotion.finish();
      _layoutPreviousBackdrop = null;
      _layoutPlayerCanvasHeight = null;
      _layoutHeldFrame = null;
      _layoutPreparing = false;
    });
    _retireLayoutImage(old);
  }

  void _finishLayoutWhenViewportReady() {
    if (!mounted ||
        !_layoutMotion.active ||
        !_layoutMotion.trimRequested ||
        _layoutCleanupScheduled ||
        !_layoutMotion.viewportIsTarget(
          MediaQuery.sizeOf(context),
          MediaQuery.devicePixelRatioOf(context),
        )) {
      return;
    }
    _layoutCleanupScheduled = true;
    final serial = _windowTransitionSerial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutCleanupScheduled = false;
      if (!_isCurrentWindowTransition(serial) ||
          !_layoutMotion.trimRequested ||
          !_layoutMotion.viewportIsTarget(
            MediaQuery.sizeOf(context),
            MediaQuery.devicePixelRatioOf(context),
          )) {
        return;
      }
      _clearLayoutMorph();
      if (_nextUpResizePending && !_isTransitioning) {
        _onNextUpVisibilityChanged();
      }
    });
  }

  Future<void> _morphOrientation(int serial) async {
    try {
      final bounds = await windowManager.getBounds();
      if (!mounted || !_isCurrentWindowTransition(serial)) return;
      final targetLayout = AppState.widgetLayout;
      final targetOpen = _isSettingsOpen;
      final reduced = MediaQuery.disableAnimationsOf(context);
      final frameRender = _layoutFrameKey.currentContext?.findRenderObject();
      final playerRender = _playerAnchorKey.currentContext?.findRenderObject();
      final inset = AppState.showLyrics
          ? 64 * _lyricsVisualMotion.animation.value * _frameScale
          : 0.0;
      final frameOffset = frameRender is RenderBox && frameRender.hasSize
          ? frameRender.localToGlobal(Offset.zero)
          : Offset(_leftPadding, 0);
      final frameSize = frameRender is RenderBox && frameRender.hasSize
          ? Size(frameRender.size.width, frameRender.size.height + inset)
          : bounds.size;
      final source = (bounds.topLeft + frameOffset) & frameSize;
      final playerLeft = playerRender is RenderBox && playerRender.hasSize
          ? bounds.left + playerRender.localToGlobal(Offset.zero).dx
          : bounds.left + _leftPadding;
      final targetPadding =
          targetOpen &&
              targetLayout == WidgetLayout.vertical &&
              _settingsSide == 'left'
          ? AppState.innerSettingsSideWidth * _frameScale
          : 0.0;
      final design = _designWindowSize(
        layout: targetLayout,
        settingsOpen: targetOpen,
      );
      final target = Rect.fromLTWH(
        playerLeft - targetPadding,
        bounds.top,
        design.width * _frameScale,
        design.height * _frameScale,
      );
      final stage = bounds.expandToInclude(target);
      if (!reduced) {
        await DynamicBackground.prepareLayout(context, targetLayout);
        if (!_isCurrentWindowTransition(serial)) return;
      }
      final snapshot = reduced
          ? null
          : await _captureLayoutBackdrop(source, bounds);
      if (!_isCurrentWindowTransition(serial)) {
        snapshot?.dispose();
        return;
      }
      final oldImage = _layoutPreviousBackdrop;
      setState(() {
        _layoutPreviousBackdrop = snapshot;
        _layoutPreparing = true;
        _layoutHeldFrame = source.shift(-bounds.topLeft);
        _layoutMotion.holdCapturedBackdrop();
      });
      _retireLayoutImage(oldImage);
      if (!_rectNearlyEquals(bounds, stage)) {
        await windowManager.setBounds(stage, animate: false);
      }
      if (!_isCurrentWindowTransition(serial)) return;
      setState(() {
        _layoutPlayerCanvasHeight = math.max(
          AppState.innerPlayerHeightOf(_displayLayout),
          AppState.innerPlayerHeightOf(targetLayout),
        );
        _displayLayout = targetLayout;
        _layoutPreparing = false;
        _layoutMotion.prepare(
          source: source,
          target: target,
          stage: stage,
          nativeTarget: target,
          vertical: targetLayout == WidgetLayout.vertical,
        );
      });
      
      
      
      if (!reduced) {
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrentWindowTransition(serial)) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrentWindowTransition(serial)) return;
      }
      final completed = await _layoutMotion.play(reduced: reduced);
      if (!completed || !_isCurrentWindowTransition(serial)) return;
      await WidgetsBinding.instance.endOfFrame;
      final current = await windowManager.getBounds();
      if (!_isCurrentWindowTransition(serial)) return;
      final moved = current.topLeft - stage.topLeft;
      final finalBounds = target.shift(moved);
      _leftPadding = targetPadding;
      _layoutMotion.requestTrim(stage.shift(moved), finalBounds);
      if (!_rectNearlyEquals(current, finalBounds)) {
        await windowManager.setBounds(finalBounds, animate: false);
      }
      if (!_isCurrentWindowTransition(serial)) return;
      await WidgetsBinding.instance.endOfFrame;
      _finishLayoutWhenViewportReady();
    } catch (error) {
      if (!_isCurrentWindowTransition(serial)) return;
      final old = _layoutPreviousBackdrop;
      setState(() {
        AppState.widgetLayout = _displayLayout;
        _layoutMotion.finish();
        _layoutPreviousBackdrop = null;
        _layoutPreparing = false;
        _layoutHeldFrame = null;
        _layoutPlayerCanvasHeight = null;
      });
      _retireLayoutImage(old);
      unawaited(AppState.saveSettings());
      debugPrint('横竖布局过渡失败，保留当前布局: $error');
    }
  }

  Future<void> _animateToTargetLayout(int serial) async {
    if (AppState.widgetLayout != _displayLayout || _layoutMotion.active) {
      await _morphOrientation(serial);
      return;
    }
    final bounds = await windowManager.getBounds();
    final double absCardLeft = bounds.left + _leftPadding;

    
    
    final WidgetLayout targetLayout = AppState.widgetLayout;
    final bool targetSettingsOpen = _isSettingsOpen;
    final String targetSettingsSide = _settingsSide;

    final double targetW =
        (targetSettingsOpen
            ? AppState.expandedWindowWidthOf(targetLayout)
            : AppState.baseWindowWidthOf(targetLayout)) *
        _frameScale;
    final double targetH =
        (targetSettingsOpen
            ? AppState.expandedWindowHeightOf(targetLayout)
            : AppState.baseWindowHeightOf(targetLayout)) *
        _frameScale;
    final double targetLeftPadding =
        targetSettingsOpen &&
            targetLayout == WidgetLayout.vertical &&
            targetSettingsSide == "left"
        ? AppState.innerSettingsSideWidth * _frameScale
        : 0.0;

    final Rect targetRect = Rect.fromLTWH(
      absCardLeft - targetLeftPadding,
      bounds.top,
      targetW,
      targetH,
    );
    final Rect stage = bounds.expandToInclude(targetRect);

    _leftPadding = absCardLeft - stage.left;
    if (!_rectNearlyEquals(bounds, stage)) {
      await windowManager.setBounds(stage, animate: false);
    }
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
    final finalBounds = Rect.fromLTWH(
      currentAbsCardLeft - _leftPadding,
      b2.top,
      targetW,
      targetH,
    );
    if (!_rectNearlyEquals(b2, finalBounds)) {
      await windowManager.setBounds(finalBounds, animate: false);
    }
  }

  Future<void> _toggleSettings() async {
    if (_menuResizeInFlight) return;
    final int serial = _beginWindowTransition();
    try {
      if (_isMenuOpen) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _menuAnimController.value = 0;
        } else {
          await _menuAnimController.reverse();
        }
        if (!mounted) return;
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
        if (_nextUpResizePending) _onNextUpVisibilityChanged();
      }
    }
  }

  Future<void> _handleLayoutChanged() async {
    final int serial = _beginWindowTransition();
    try {
      _syncSpectrumPolling();
      unawaited(AppState.saveSettings());
      AppState.notifyBackgroundChanged();
      final bool componentScaleChanged =
          (AppState.componentScale - _frameScale).abs() > 0.0001 ||
          (AppState.componentScale - _contentScale).abs() > 0.0001 ||
          _frameScaleController.isAnimating ||
          _contentScaleController.isAnimating;
      if (AppState.widgetLayout != _displayLayout || _layoutMotion.active) {
        await _morphOrientation(serial);
        if (mounted &&
            componentScaleChanged &&
            _isCurrentWindowTransition(serial)) {
          if (_layoutMotion.active &&
              _layoutMotion.viewportIsTarget(
                MediaQuery.sizeOf(context),
                MediaQuery.devicePixelRatioOf(context),
              )) {
            _clearLayoutMorph();
          }
          await _applyComponentSizeToTarget(serial);
        }
      } else if (componentScaleChanged) {
        await _applyComponentSizeToTarget(serial);
      } else {
        await _animateToTargetLayout(serial);
      }
    } finally {
      if (_isCurrentWindowTransition(serial)) {
        setState(() => _isTransitioning = false);
        if (_nextUpResizePending) _onNextUpVisibilityChanged();
      }
    }
  }

  void _stageCustomScale(double scale, Size viewport, Size design) {
    _pendingCustomScale = scale;
    _pendingCustomViewport = viewport;
    _pendingCustomDesign = design;
    _pendingCustomTransitionSerial = _windowTransitionSerial;
    if (_customScaleCommitScheduled) return;
    _customScaleCommitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _customScaleCommitScheduled = false;
      final double? pending = _pendingCustomScale;
      final viewport = _pendingCustomViewport;
      final design = _pendingCustomDesign;
      final serial = _pendingCustomTransitionSerial;
      _pendingCustomScale = null;
      _pendingCustomViewport = null;
      _pendingCustomDesign = null;
      _pendingCustomTransitionSerial = null;
      if (!mounted ||
          pending == null ||
          !AppState.isCustomComponentSize ||
          _nextUpResizePending ||
          _nextUpResizeInFlight ||
          _menuResizeInFlight ||
          _isTransitioning ||
          serial != _windowTransitionSerial ||
          viewport != MediaQuery.sizeOf(context) ||
          design !=
              _designWindowSize(
                layout: AppState.widgetLayout,
                settingsOpen: _isSettingsOpen,
              )) {
        return;
      }
      AppState.customComponentScale = pending / AppState.standardDisplayScale;
      _frameScale = pending;
      _contentScale = pending;
    });
  }

  @override
  void onWindowResized() {
    if (AppState.isCustomComponentSize &&
        !_nextUpResizePending &&
        !_nextUpResizeInFlight) {
      _resizeSaveTimer?.cancel();
      _resizeSaveTimer = Timer(const Duration(milliseconds: 180), () {
        unawaited(AppState.saveSettings());
      });
    }
  }

  Future<void> _handleWindowBehaviorChanged() async {
    await windowManager.setAlwaysOnTop(AppState.isAlwaysOnTop);
    if (AppState.isMousePassthrough && !_isSystemTrayReady) {
      await _restoreMouseInteraction(flushSettings: true);
      return;
    }
    await windowManager.setIgnoreMouseEvents(
      AppState.isMousePassthrough,
      forward: true,
    );
    unawaited(AppState.saveSettings());
  }

  Future<void> _openMenu(bool toLeft) async {
    if (_isSettingsOpen ||
        _isTransitioning ||
        _menuResizeInFlight ||
        _nextUpResizeInFlight) {
      return;
    }
    setState(() {
      _menuResizeInFlight = true;
      _menuSide = toLeft ? 'left' : 'right';
    });
    try {
      
      
      await WidgetsBinding.instance.endOfFrame;
      final bounds = await windowManager.getBounds();
      if (!mounted) return;
      final ratio = MediaQuery.devicePixelRatioOf(context);
      _menuBaseViewportWidth = bounds.width;
      _menuNativeExtra = (AppState.menuExtraSpace * ratio).round() / ratio;
      await windowManager.setBounds(
        Rect.fromLTWH(
          bounds.left - (toLeft ? _menuNativeExtra : 0),
          bounds.top,
          bounds.width + _menuNativeExtra,
          bounds.height,
        ),
        animate: false,
      );
      if (!mounted) return;
      setState(() {
        _leftPadding = toLeft ? _menuNativeExtra : 0;
        _isMenuOpen = true;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _menuAnimController.value = 1;
        } else {
          _menuAnimController.forward();
        }
      }
    } catch (error) {
      debugPrint('右键菜单展开失败: $error');
    } finally {
      if (mounted) {
        setState(() => _menuResizeInFlight = false);
        if (_nextUpResizePending) _onNextUpVisibilityChanged();
      }
    }
  }

  Future<void> _closeMenu() async {
    if (!_isMenuOpen ||
        _isTransitioning ||
        _menuResizeInFlight ||
        _nextUpResizeInFlight) {
      return;
    }
    setState(() => _menuResizeInFlight = true);
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _menuAnimController.value = 0;
      } else {
        await _menuAnimController.reverse();
      }
      if (!mounted) return;
      setState(() => _isMenuOpen = false);
      await WidgetsBinding.instance.endOfFrame;
      final bounds = await windowManager.getBounds();
      if (!mounted) return;
      double resetLeft = bounds.left + _leftPadding;
      _leftPadding = 0.0;
      await windowManager.setBounds(
        Rect.fromLTWH(
          resetLeft,
          bounds.top,
          bounds.width - _menuNativeExtra,
          bounds.height,
        ),
        animate: false,
      );
      await WidgetsBinding.instance.endOfFrame;
    } catch (error) {
      debugPrint('右键菜单收起失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _menuResizeInFlight = false;
          if (!_isMenuOpen) _menuBaseViewportWidth = null;
        });
        if (_nextUpResizePending) _onNextUpVisibilityChanged();
      }
    }
  }

  void _handleSecondaryTap(TapDownDetails details) async {
    if (_isTransitioning || _menuResizeInFlight) return;
    if (_isSettingsOpen) {
      _toggleSettings();
      return;
    }

    final double clickX = details.localPosition.dx;
    final double clickY = details.localPosition.dy * _contentScale;
    final double maxTop = AppState.baseWindowHeight - 100.0 * _frameScale;
    _menuTop = clickY.clamp(12.0, maxTop);

    final bool toLeft =
        clickX < AppState.innerPlayerWidthOf(AppState.widgetLayout) / 2;

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
    return RepaintBoundary(
      key: const ValueKey('settings_panel_surface'),
      child: Material(
        type: MaterialType.transparency,
        child: SettingsPanel(
          isMousePassthroughAvailable: _isSystemTrayReady,
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _finishLayoutWhenViewportReady();
    bool isV = _displayLayout == WidgetLayout.vertical;
    bool isOpen = _isSettingsOpen;
    String side = _settingsSide;

    bool anchorRight = isV && side == "left" && (isOpen || _isTransitioning);

    double innerPlayerW = AppState.innerPlayerWidthOf(_displayLayout);
    double innerPlayerH = AppState.innerPlayerHeightOf(_displayLayout);
    double corePlayerH = AppState.corePlayerHeightOf(_displayLayout);
    bool spectrumVisible = AppState.spectrumMode != SpectrumMode.off;
    bool performanceVisible = AppState.performanceMonitorVisible;
    bool spectrumRowVisible = spectrumVisible || performanceVisible;
    bool lyricsVisible = AppState.lyricsPanelVisible;
    bool lyricsOccupied = AppState.showLyrics;
    bool nextUpConfigured =
        AppState.showNextUp && AppState.hasPlaylistConfigured;
    bool nextUpVisible =
        nextUpConfigured && AppState.nextUpPreviewVisible.value;
    bool nextUpOccupied = AppState.nextUpPanelOccupied;
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
    final Alignment componentAlignment =
        (_layoutMotion.active || _layoutPreparing)
        ? Alignment.topLeft
        : anchorRight
        ? Alignment.topRight
        : Alignment.topLeft;
    double renderFrameScale = _frameScale;
    double renderContentScale = _contentScale;
    final bool isLiveCustomResize =
        AppState.isCustomComponentSize &&
        !_isTransitioning &&
        !_layoutMotion.active &&
        !_layoutPreparing &&
        !_isMenuOpen &&
        !_menuResizeInFlight &&
        !_nextUpResizePending &&
        !_nextUpResizeInFlight;
    if (isLiveCustomResize) {
      final viewport = MediaQuery.sizeOf(context);
      final design = Size(containerW, containerH);
      final double viewportScale = ComponentSizeMotion.stableFitScale(
        viewport: viewport,
        design: design,
        referenceScale: _frameScale,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        maximumScale: AppState.maximumComponentScale,
      );
      renderFrameScale = viewportScale;
      renderContentScale = viewportScale;
      final bool isPersistableScale =
          viewportScale >= AppState.minimumComponentScale &&
          viewportScale <= AppState.maximumComponentScale;
      if (isPersistableScale &&
          (viewportScale - AppState.componentScale).abs() > 0.0005) {
        _stageCustomScale(viewportScale, viewport, design);
      }
    }
    final double stageScale = _isComponentSizeTransitioning
        ? _componentSizeStageScale
        : renderFrameScale;
    final double frameWidth = containerW * stageScale;
    final double frameHeight = containerH * stageScale;
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final Duration frameAnimationDuration =
        _isTransitioning &&
            !_layoutMotion.active &&
            !_layoutPreparing &&
            !_isComponentSizeTransitioning &&
            !isLiveCustomResize &&
            !reduceMotion
        ? AppState.layoutSwitchDuration
        : Duration.zero;

    final backgroundAnchorHeight =
        (innerPlayerH - AppState.nextUpPanelExtentOf(_displayLayout)) *
        (_isComponentSizeTransitioning ? 1.0 : renderFrameScale);
    final backgroundAnchorWidth =
        innerPlayerW * (_isComponentSizeTransitioning ? 1.0 : renderFrameScale);
    final backgroundAnchorLeft =
        pLeft * (_isComponentSizeTransitioning ? 1.0 : renderFrameScale);
    final backgroundAnchor = (
      backgroundAnchorWidth,
      backgroundAnchorHeight,
      backgroundAnchorLeft,
      isV,
      _layoutMotion.active || _layoutPreparing,
    );
    if (_backgroundAnchor != backgroundAnchor) {
      _backgroundAnchor = backgroundAnchor;
      _anchoredPlayerBackground = RepaintBoundary(
        child: DynamicBackground(
          anchorHeight: backgroundAnchorHeight,
          anchorWidth: backgroundAnchorWidth,
          anchorLeft: backgroundAnchorLeft,
          verticalLayout: isV,
          animateArtworkReplacement:
              !(_layoutMotion.active || _layoutPreparing),
        ),
      );
    }
    final playerBackground = _anchoredPlayerBackground!;
    Widget playerContent = Stack(
      clipBehavior: Clip.none,
      children: [
        MorphPositioned(
          motion: _layoutMotion,
          duration: frameAnimationDuration,
          curve: AppState.layoutSwitchCurve,
          left: sLeft,
          top: sTop,
          width: innerSettingsW,
          height: innerSettingsH,
          child: _followLyrics(
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: isOpen ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !isOpen,
                child: TickerMode(
                  enabled: isOpen || _isTransitioning,
                  child: _buildSettingsPanel(),
                ),
              ),
            ),
            verticalSettings: isV,
            settingsHeight: innerSettingsH,
          ),
        ),
        MorphPositioned(
          motion: _layoutMotion,
          duration: frameAnimationDuration,
          curve: AppState.layoutSwitchCurve,
          left: pLeft,
          top: pTop,
          width: innerPlayerW,
          height: innerPlayerH,
          child: _clipPlayerVisualHeight(
            GestureDetector(
              key: _playerAnchorKey,
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onSecondaryTapDown: _handleSecondaryTap,
              onTapDown: (_) {
                if (_isMenuOpen) _closeMenu();
              },
              child: RepaintBoundary(
                key: const ValueKey('player_content_surface'),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MorphPositioned(
                      motion: _layoutMotion,
                      duration: frameAnimationDuration,
                      curve: AppState.layoutSwitchCurve,
                      left: 0,
                      top: 0,
                      width: innerPlayerW,
                      height: corePlayerH,
                      child: ContinuousTrackControls(
                        isVertical: isV,
                        layoutMotion: _layoutMotion,
                      ),
                    ),
                    MorphPositioned(
                      motion: _layoutMotion,
                      duration: frameAnimationDuration,
                      curve: AppState.layoutSwitchCurve,
                      left: playerHorizontalPadding,
                      top: corePlayerH + 8.0,
                      width: innerPlayerW - playerHorizontalPadding * 2,
                      height: spectrumRowVisible ? 48.0 : 0.0,
                      child: AnimatedOpacity(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        opacity: spectrumRowVisible ? 1.0 : 0.0,
                        child: IgnorePointer(
                          ignoring: !spectrumRowVisible,
                          child: SpectrumPerformanceRow(
                            spectrumMode: AppState.spectrumMode,
                            isPlaying: AppState.isPlaying,
                            showPerformance: performanceVisible,
                            isVertical: isV,
                          ),
                        ),
                      ),
                    ),
                    MorphPositioned(
                      motion: _layoutMotion,
                      duration: frameAnimationDuration,
                      curve: AppState.layoutSwitchCurve,
                      left: playerHorizontalPadding,
                      top:
                          corePlayerH +
                          AppState.spectrumPanelExtentOf(_displayLayout) +
                          8.0,
                      width: innerPlayerW - playerHorizontalPadding * 2,
                      height: lyricsOccupied ? 48.0 : 0.0,
                      child: AnimatedBuilder(
                        animation: _lyricsVisualMotion.animation,
                        builder: (context, child) => Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            height: math.max(
                              0.0,
                              48 - 64 * _lyricsVisualMotion.animation.value,
                            ),
                            child: ClipRect(
                              child: OverflowBox(
                                minHeight: 48,
                                maxHeight: 48,
                                alignment: Alignment.topCenter,
                                child: child,
                              ),
                            ),
                          ),
                        ),
                        child: IgnorePointer(
                          ignoring: !lyricsVisible,
                          child: AnimatedSwitcher(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeOutCubic,
                            layoutBuilder: (child, previous) => Stack(
                              fit: StackFit.expand,
                              children: [...previous, ?child],
                            ),
                            child: lyricsVisible
                                ? const MusicLyricsPanel(
                                    key: ValueKey('visible_lyrics'),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey('hidden_lyrics'),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    MorphPositioned(
                      motion: _layoutMotion,
                      duration: frameAnimationDuration,
                      curve: AppState.layoutSwitchCurve,
                      left: playerHorizontalPadding,
                      top:
                          corePlayerH +
                          AppState.spectrumPanelExtentOf(_displayLayout) +
                          AppState.lyricsPanelExtentOf(_displayLayout) +
                          8.0,
                      width: innerPlayerW - playerHorizontalPadding * 2,
                      height: nextUpOccupied ? 48.0 : 0.0,
                      child: _followLyrics(
                        IgnorePointer(
                          ignoring: !nextUpVisible,
                          child: nextUpConfigured || nextUpOccupied
                              ? MusicNextUpPanel(
                                  presenceAnimation: _nextUpMotion.animation,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    MorphPositioned(
                      motion: _layoutMotion,
                      duration: frameAnimationDuration,
                      curve: AppState.layoutSwitchCurve,
                      left: 0,
                      top: corePlayerH,
                      width: innerPlayerW,
                      height: math.max(0, innerPlayerH - corePlayerH),
                      child: ValueListenableBuilder<int>(
                        valueListenable: AppState.backgroundRevision,
                        builder: (context, revision, child) =>
                            PlaybackPauseShade(
                              key: const ValueKey('auxiliary_pause_shade'),
                              paused: !AppState.isPlaying,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            innerPlayerH,
          ),
        ),
      ],
    );

    Widget mainStage = AnimatedBuilder(
      animation: _componentSizeScaleListenable,
      child: playerContent,
      builder: (context, child) {
        final bool transformOnly = _isComponentSizeTransitioning;
        final double animatedFrameScale = transformOnly
            ? _frameScale
            : renderFrameScale;
        final double animatedContentScale = transformOnly
            ? _contentScale
            : renderContentScale;
        final morphFrame = _layoutMotion.active
            ? _layoutMotion.frameInViewport(
                MediaQuery.sizeOf(context),
                MediaQuery.devicePixelRatioOf(context),
              )
            : _layoutPreparing
            ? _layoutHeldFrame
            : null;
        final visibleW = morphFrame?.width ?? frameWidth;
        final visibleH = morphFrame?.height ?? frameHeight;
        final canvasW = _layoutMotion.active
            ? _layoutMotion.canvas.width
            : math.max(frameWidth, visibleW);
        final canvasH = _layoutMotion.active
            ? _layoutMotion.canvas.height
            : math.max(frameHeight, visibleH);
        final targetBackgroundSize = transformOnly
            ? Size(containerW, containerH)
            : Size(frameWidth, frameHeight);
        final backdrop = Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: transformOnly ? containerW : visibleW,
            height: transformOnly ? containerH : visibleH,
            child: BackdropCaptureBoundary(
              key: _layoutBackdropKey,
              child: LayoutBackdropBlend(
                motion: _layoutMotion,
                previous: _layoutPreviousBackdrop,
                targetSize: targetBackgroundSize,
                child: playerBackground,
              ),
            ),
          ),
        );
        return ComponentSizeStage(
          key: _layoutFrameKey,
          frameWidth: visibleW,
          visualCollapse: _lyricsVisualMotion.animation,
          collapseExtent: lyricsOccupied
              ? LyricsVisualMotion.reservedExtent
              : 0,
          frameHeight: visibleH,
          canvasWidth: canvasW,
          canvasHeight: canvasH,
          designWidth:
              (_layoutMotion.active || _layoutPreparing) && !transformOnly
              ? canvasW / animatedContentScale
              : containerW,
          designHeight:
              (_layoutMotion.active || _layoutPreparing) && !transformOnly
              ? canvasH / animatedContentScale
              : containerH,
          frameScale: animatedFrameScale,
          contentScale: animatedContentScale,
          alignment: componentAlignment,
          frameAnimationDuration: frameAnimationDuration,
          frameAnimationCurve: AppState.layoutSwitchCurve,
          transformOnly: transformOnly,
          background: backdrop,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              transformOnly ? 28.0 : 28.0 * animatedFrameScale,
            ),
            border: Border.all(
              color: AppState.currentScheme.outlineVariant.withValues(
                alpha: 0.4,
              ),
              width: RoundedRasterScale.hairline(
                context,
                scale: transformOnly ? animatedFrameScale : 1,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    mainStage = LockedAspectResizeArea(
      key: _resizeAreaKey,
      enabled:
          AppState.isCustomComponentSize &&
          !_isTransitioning &&
          !_isMenuOpen &&
          !_menuResizeInFlight &&
          !_nextUpResizePending &&
          !_nextUpResizeInFlight,
      designSize: Size(containerW, containerH),
      minimumScale: AppState.minimumComponentScale,
      maximumScale: AppState.maximumComponentScale,
      onResizeEnd: () {
        _resizeSaveTimer?.cancel();
        _resizeSaveTimer = Timer(const Duration(milliseconds: 180), () {
          unawaited(AppState.saveSettings());
        });
      },
      child: mainStage,
    );

    return AnimatedTheme(
      data: ThemeData(useMaterial3: true, colorScheme: AppState.currentScheme),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOutCubic,
      child: AppTypographyTheme(
        family: AppState.effectiveGlobalFontFamily,
        fallback: AppState.textFontFallback,
        displayScale: AppState.componentScale,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: _layoutMotion,
                  child: mainStage,
                  builder: (context, child) {
                    final frame = _layoutMotion.active
                        ? _layoutMotion.frameInViewport(
                            MediaQuery.sizeOf(context),
                            MediaQuery.devicePixelRatioOf(context),
                          )
                        : _layoutPreparing
                        ? _layoutHeldFrame
                        : null;
                    final menuAnchored =
                        _menuSide == 'left' &&
                        (_isMenuOpen || _menuResizeInFlight);
                    final menuLeft = menuAnchored
                        ? math.max(
                            0.0,
                            MediaQuery.sizeOf(context).width -
                                (_menuBaseViewportWidth ??
                                    MediaQuery.sizeOf(context).width),
                          )
                        : null;
                    return Positioned(
                      left:
                          frame?.left ??
                          menuLeft ??
                          (anchorRight ? null : _leftPadding),
                      right: frame == null && !menuAnchored && anchorRight
                          ? 0
                          : null,
                      top: frame?.top ?? 0,
                      child: child!,
                    );
                  },
                ),
                if (_isMenuOpen)
                  Positioned(
                    left: _menuSide == "left" ? 0 : AppState.baseWindowWidth,
                    top: _menuTop,
                    width: AppState.menuExtraSpace,
                    child: OverflowBox(
                      fit: OverflowBoxFit.deferToChild,
                      minWidth: AppState.unscaledMenuExtraSpace,
                      maxWidth: AppState.unscaledMenuExtraSpace,
                      alignment: _menuSide == 'left'
                          ? Alignment.topRight
                          : Alignment.topLeft,
                      child: Transform.scale(
                        scale: renderContentScale,
                        alignment: _menuSide == "left"
                            ? Alignment.topRight
                            : Alignment.topLeft,
                        child: RoundedRasterScale(
                          scale: renderContentScale,
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
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
