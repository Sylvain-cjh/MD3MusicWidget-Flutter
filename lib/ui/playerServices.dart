part of 'playerView.dart';


extension _PlayerServices on _PlayerViewState {
  Future<void> _initSystemTray() async {
    try {
      if (Platform.isWindows) {
        if (!await _windowsTray.start(_onWindowsTrayAction)) {
          throw StateError('Windows 未能注册托盘图标');
        }
      } else {
        await tm.trayManager.setIcon('images/tray_icon.png');
        await tm.trayManager.setToolTip('MD3 Music Widget');
        await tm.trayManager.setContextMenu(
          tm.Menu(
            items: [
              tm.MenuItem(key: 'restore_interaction', label: '恢复鼠标交互'),
              tm.MenuItem.separator(),
              tm.MenuItem(key: 'rescue_exit', label: '完全退出挂件'),
            ],
          ),
        );
      }
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

  Future<void> _onWindowsTrayAction(WindowsTrayAction action) async {
    if (!mounted) return;
    switch (action) {
      case WindowsTrayAction.activate:
        if (AppState.isMousePassthrough || !_isSystemTrayReady) {
          await _restoreMouseInteraction(flushSettings: true);
        } else {
          try {
            final next = await _windowsTray.showMenu();
            if (next != null &&
                (next == WindowsTrayAction.restore ||
                    next == WindowsTrayAction.exit)) {
              await _onWindowsTrayAction(next);
            }
          } catch (error) {
            debugPrint('系统托盘菜单打开失败: $error');
            await _restoreMouseInteraction(flushSettings: true);
          }
        }
      case WindowsTrayAction.restore:
        await _restoreMouseInteraction(flushSettings: true);
      case WindowsTrayAction.exit:
        unawaited(windowManager.hide());
        await _exitApplication();
      case WindowsTrayAction.available:
        if (!_isSystemTrayReady) _updateState(() => _isSystemTrayReady = true);
      case WindowsTrayAction.unavailable:
        if (_isSystemTrayReady) _updateState(() => _isSystemTrayReady = false);
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
      if (Platform.isWindows) {
        await _windowsTray.stop();
      } else {
        await tm.trayManager.destroy();
      }
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
