part of 'playerView.dart';


extension _PlayerServices on _PlayerViewState {
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
      _updateState(() => _isSystemTrayReady = true);

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
    if (mounted) _updateState(() {});
    await AppState.saveSettings();
    if (flushSettings) await AppState.flushSettings();
  }

  Future<void> _exitApplication() async {
    _servicesStarted = false;
    _pollingTimer?.cancel();
    _spectrumTimer?.cancel();
    _mediaReconnectTimer?.cancel();
    _coverFallbackTimer?.cancel();
    AppState.mediaCommandSender = null;
    await _mediaProviderSubscription?.cancel();
    final backend = _mediaProvider;
    if (backend != null) await AppState.releaseMediaBackend(backend);
    try {
      await tm.trayManager.destroy();
    } catch (_) {}
    await AppState.exitApp();
  }

  Future<void> _closeFetcherRuntime() async {
    await _fetcherRuntime.close();
    if (AppState.externalMediaStopper == _closeFetcherRuntime) {
      AppState.fetcherPid = 0;
    }
  }
}
