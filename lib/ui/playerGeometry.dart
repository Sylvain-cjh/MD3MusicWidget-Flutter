part of 'playerView.dart';


extension _PlayerGeometry on _PlayerViewState {
  int _beginWindowTransition() {
    _completeSettingsWait();
    _settingsTransitionActive = false;
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

  void _completeSettingsWait() {
    final pending = _settingsSettled;
    _settingsSettled = null;
    _settingsSettledTarget = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void _onSettingsSettled(bool open) {
    if (_settingsSettledTarget == open) _completeSettingsWait();
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

  Future<Rect> _readWindowBounds() async {
    _resizeAreaKey.currentState?.cancelPendingResize();
    await _resizeAreaKey.currentState?.waitForIdle();
    return _windowGeometry.read(windowManager.getBounds);
  }

  Future<void> _writeWindowBounds(Rect bounds, {int? serial}) {
    final owner = serial ?? _windowTransitionSerial;
    return _windowGeometry.write(
      () => windowManager.setBounds(bounds, animate: false),
      isCurrent: () => _isCurrentWindowTransition(owner),
    );
  }

  void _onLyricsVisibilityChanged() {
    if (!mounted) return;
    final visible = AppState.lyricsPanelVisible;
    if (visible == _lastLyricsVisible &&
        _lyricsVisualMotion.collapsed == _lyricsCollapsed) {
      return;
    }
    _updateState(() => _lastLyricsVisible = visible);
    _lyricsVisualMotion.update(
      _lyricsCollapsed,
      reduceMotion: MediaQuery.maybeOf(context)?.disableAnimations ?? false,
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
    _updateState(() {});
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
    final serial = _windowTransitionSerial;
    await _resizeAreaKey.currentState?.waitForIdle();
    if (!_isCurrentWindowTransition(serial)) {
      _nextUpResizePending = true;
      return;
    }
    if (occupied && !AppState.nextUpPreviewVisible.value) return;
    if (_isTransitioning) {
      AppState.nextUpPanelOccupied = occupied;
      _updateState(() {});
      _nextUpResizePending = true;
      return;
    }
    
    
    
    if (!occupied) {
      AppState.nextUpPanelOccupied = false;
      _updateState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final bounds = await _readWindowBounds();
    if (!mounted) return;
    if (!_isCurrentWindowTransition(serial)) {
      _nextUpResizePending = true;
      return;
    }
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
      await _writeWindowBounds(
        Rect.fromLTWH(bounds.left, bounds.top, bounds.width, targetHeight),
        serial: serial,
      );
    }
    if (!_isCurrentWindowTransition(serial)) {
      _nextUpResizePending = true;
      return;
    }
    if (occupied && !AppState.nextUpPreviewVisible.value) return;
    AppState.nextUpPanelOccupied = occupied;
    _updateState(() {});
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
      if (mounted) _updateState(() {});
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
    final Rect bounds = await _readWindowBounds();
    if (!_isCurrentWindowTransition(serial)) return;
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
      _updateState(() {
        _frameScale = targetScale;
        _contentScale = targetScale;
        _componentSizeStageScale = targetScale;
        _leftPadding = targetLeftPadding;
        _isComponentSizeTransitioning = false;
      });
      if (!_rectNearlyEquals(bounds, targetRect)) {
        await _writeWindowBounds(targetRect, serial: serial);
      }
      return;
    } else {
      _componentSizeStageScale = math.max(_frameScale, targetScale);
      _leftPadding = absCardLeft - stage.left;
      _updateState(() {
        _isComponentSizeTransitioning = true;
      });

      final Future<void> stageResize = _rectNearlyEquals(bounds, stage)
          ? Future<void>.value()
          : _writeWindowBounds(stage, serial: serial);
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
      _updateState(() {
        _frameScale = targetScale;
        _contentScale = targetScale;
        _componentSizeStageScale = targetScale;
      });
    }

    _leftPadding = targetLeftPadding;
    if (mounted) {
      _updateState(() {
        _isComponentSizeTransitioning = false;
      });
    }
    if (!_rectNearlyEquals(stage, targetRect)) {
      await _writeWindowBounds(targetRect, serial: serial);
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
    _updateState(() {
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
}
