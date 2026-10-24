import 'dart:async';
import '../core/appTypography.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit, RenderBox;
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart' as tm;

import '../core/appState.dart';
import '../core/widgetDiagnostics.dart';
import '../core/nativeWindowGeometry.dart';
import '../core/windowGeometryQueue.dart';
import '../core/artworkResources.dart';
import '../core/mediaProvider.dart';
import '../core/mediaSessionLifecycle.dart';
import '../core/demandPollingLoop.dart';
import '../core/mediaCaptureBackend.dart';
import '../core/musicFetcherRuntime.dart';
import '../core/runtimeCapabilities.dart';
import '../core/spectrumPacket.dart';
import 'animations/componentSizeMotion.dart';
import 'animations/nextUpPresenceMotion.dart';
import 'animations/lyricsVisualMotion.dart';
import 'animations/layoutMorphMotion.dart';
import 'animations/settingsDisclosure.dart';
import 'animations/mediaMotionTokens.dart';
import 'widgets/layoutBackdropBlend.dart';
import 'widgets/backdropCaptureBoundary.dart';
import 'widgets/smoothRoundedClip.dart';
import 'widgets/dynamicBackground.dart';
import 'widgets/lockedAspectResizeArea.dart';
import 'widgets/trackControls.dart';
import 'widgets/playbackPauseShade.dart';
import 'widgets/musicLyricsPanel.dart';
import 'widgets/musicNextUpPanel.dart';
import 'widgets/spectrumPerformanceRow.dart';
import 'widgets/slideMenu.dart';
import 'widgets/settingsPanel.dart';

part 'playerServices.dart';
part 'playerArtwork.dart';
part 'playerMedia.dart';
part 'playerGeometry.dart';
part 'playerTransitions.dart';
part 'playerRendering.dart';

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
  DemandPollingLoop? _pollingTimer;
  Timer? _spectrumTimer;
  Duration? _spectrumPollingInterval;
  DemandPollingLoop? _mediaReconnectTimer;
  bool _servicesStarted = false;
  late final _mediaLifecycle = MediaSessionLifecycle(
    onUpdate: _acceptMediaUpdate,
    estimatedPositionMs: () => AppState.estimatedPlaybackPositionMs,
  );
  MediaCaptureBackend? _mediaProvider;
  final _fetcherRuntime = MusicFetcherRuntime();
  StreamSubscription<MediaProviderEvent>? _mediaProviderSubscription;
  bool _mediaProviderConnectInFlight = false;
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

  Future<Uint8List> _readLocalResponse(Uri uri, {required Duration timeout}) {
    final backend = AppState.mediaBackend;
    if (!mounted ||
        !backend.supportsLegacyPolling ||
        backend is! LegacyMediaReader) {
      throw StateError('Selected media backend does not support HTTP polling');
    }
    return (backend as LegacyMediaReader).readLegacyResponse(
      uri,
      timeout: timeout,
    );
  }

  bool _isSettingsOpen = false;
  bool _settingsVisualOpen = false;
  bool _settingsTransitionActive = false;
  Size? _settingsCanvasSize;
  Completer<void>? _settingsSettled;
  bool? _settingsSettledTarget;
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
  final _windowGeometry = WindowGeometryQueue();
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
      AppState.externalMediaStopper = _closeFetcherRuntime;
      unawaited(_initSystemTray());
      unawaited(_bootEngineAndListen());
    }
    if (WidgetDiagnostics.enabled) {
      WidgetDiagnostics.actions.addAll({
        'captureInterrupt': (_) async {
          if (!WidgetDiagnostics.liveCapture || _fetcherRuntime.ownedPid <= 0) {
            throw StateError('No diagnostic-owned capture process');
          }
          await _fetcherRuntime.stopOwned();
        },
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
    if (AppState.externalMediaStopper == _closeFetcherRuntime) {
      AppState.externalMediaStopper = null;
    }
    unawaited(
      _fetcherRuntime.close().catchError((Object error) {
        debugPrint('Capture runtime cleanup failed: $error');
      }),
    );
    _completeSettingsWait();
    _servicesStarted = false;
    _mediaLifecycle.dispose();
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
    final backend = _mediaProvider;
    if (backend != null) unawaited(AppState.releaseMediaBackend(backend));
    _resizeSaveTimer?.cancel();
    _artworkResources.dispose();
    windowManager.removeListener(this);
    tm.trayManager.removeListener(this);
    AppState.nextUpPreviewVisible.removeListener(_onNextUpVisibilityChanged);
    _nextUpMotion.dispose();
    AppState.nextUpPanelOccupied = false;
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

  
  
  

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lyricsVisualMotion.update(
      _lyricsCollapsed,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
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

  @override
  Widget build(BuildContext context) => _buildPlayer(context);
  void _updateState(VoidCallback change) => setState(change);
}
