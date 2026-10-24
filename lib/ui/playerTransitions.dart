part of 'playerView.dart';


extension _PlayerTransitions on _PlayerViewState {
  Future<void> _morphOrientation(int serial) async {
    try {
      final bounds = await _readWindowBounds();
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
      _updateState(() {
        _layoutPreviousBackdrop = snapshot;
        _layoutPreparing = true;
        _layoutHeldFrame = source.shift(-bounds.topLeft);
        _layoutMotion.holdCapturedBackdrop();
      });
      _retireLayoutImage(oldImage);
      if (!_rectNearlyEquals(bounds, stage)) {
        await _writeWindowBounds(stage, serial: serial);
      }
      if (!_isCurrentWindowTransition(serial)) return;
      _updateState(() {
        _layoutPlayerCanvasHeight = math.max(
          AppState.innerPlayerHeightOf(_displayLayout),
          AppState.innerPlayerHeightOf(targetLayout),
        );
        _displayLayout = targetLayout;
        _settingsVisualOpen = targetOpen;
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
      final current = await _readWindowBounds();
      if (!_isCurrentWindowTransition(serial)) return;
      final moved = current.topLeft - stage.topLeft;
      final finalBounds = target.shift(moved);
      _leftPadding = targetPadding;
      _layoutMotion.requestTrim(stage.shift(moved), finalBounds);
      if (!_rectNearlyEquals(current, finalBounds)) {
        await _writeWindowBounds(finalBounds, serial: serial);
      }
      if (!_isCurrentWindowTransition(serial)) return;
      await WidgetsBinding.instance.endOfFrame;
      _finishLayoutWhenViewportReady();
    } catch (error) {
      if (!_isCurrentWindowTransition(serial)) return;
      final old = _layoutPreviousBackdrop;
      _updateState(() {
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
    final bounds = await _readWindowBounds();
    if (!_isCurrentWindowTransition(serial)) return;
    if (_layoutPreparing && !_layoutMotion.active) {
      
      
      
      _clearLayoutMorph();
    }
    final double absCardLeft = bounds.left + _leftPadding;

    
    
    final WidgetLayout targetLayout = AppState.widgetLayout;
    final bool targetSettingsOpen = _isSettingsOpen;
    final String targetSettingsSide = _settingsSide;

    final duration = _settingsTransitionActive
        ? MediaMotionTokens.settingsDisclosure
        : AppState.layoutSwitchDuration;

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
      await _writeWindowBounds(stage, serial: serial);
      
      
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!_isCurrentWindowTransition(serial)) return;
    if (!mounted) return;
    final reducedDisclosure = MediaQuery.disableAnimationsOf(context);
    if (_settingsVisualOpen != targetSettingsOpen) {
      final settled = Completer<void>();
      _settingsSettled = settled;
      _settingsSettledTarget = targetSettingsOpen;
      _updateState(() => _settingsVisualOpen = targetSettingsOpen);
      await settled.future;
      if (!_isCurrentWindowTransition(serial)) return;
      
      
      await WidgetsBinding.instance.endOfFrame;
    } else {
      _updateState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (!_settingsTransitionActive && !reducedDisclosure) {
        await Future<void>.delayed(duration + const Duration(milliseconds: 16));
      }
    }

    if (!_isCurrentWindowTransition(serial)) return;

    final b2 = await _readWindowBounds();
    if (!_isCurrentWindowTransition(serial)) return;
    final double currentAbsCardLeft = b2.left + _leftPadding;
    _leftPadding = targetLeftPadding;

    if (mounted) _updateState(() {});
    final finalBounds = Rect.fromLTWH(
      currentAbsCardLeft - _leftPadding,
      b2.top,
      targetW,
      targetH,
    );
    if (!_rectNearlyEquals(b2, finalBounds)) {
      await _writeWindowBounds(finalBounds, serial: serial);
    }
  }

  Future<void> _toggleSettings() async {
    if (_menuResizeInFlight) return;
    final int serial = _beginWindowTransition();
    _settingsTransitionActive = true;
    try {
      if (_isMenuOpen) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _menuAnimController.value = 0;
        } else {
          await _menuAnimController.reverse();
        }
        if (!_isCurrentWindowTransition(serial)) return;
        _isMenuOpen = false;
      }
      _updateState(() {
        _settingsCanvasSize = Size(
          AppState.expandedWindowWidthOf(_displayLayout),
          AppState.expandedWindowHeightOf(_displayLayout),
        );
        _isSettingsOpen = !_isSettingsOpen;
      });

      if (_isSettingsOpen) {
        _settingsSide = _menuSide;
      }
      await _animateToTargetLayout(serial);
    } finally {
      if (_isCurrentWindowTransition(serial)) {
        _completeSettingsWait();
        _updateState(() {
          _settingsCanvasSize = null;
          _settingsTransitionActive = false;
          _isTransitioning = false;
        });
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
        _updateState(() {
          _settingsCanvasSize = null;
          _isTransitioning = false;
        });
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
    _updateState(() {
      _menuResizeInFlight = true;
      _menuSide = toLeft ? 'left' : 'right';
    });
    try {
      
      
      await WidgetsBinding.instance.endOfFrame;
      final bounds = await _readWindowBounds();
      if (!mounted) return;
      final ratio = MediaQuery.devicePixelRatioOf(context);
      _menuBaseViewportWidth = bounds.width;
      _menuNativeExtra = (AppState.menuExtraSpace * ratio).round() / ratio;
      await _writeWindowBounds(
        Rect.fromLTWH(
          bounds.left - (toLeft ? _menuNativeExtra : 0),
          bounds.top,
          bounds.width + _menuNativeExtra,
          bounds.height,
        ),
      );
      if (!mounted) return;
      _updateState(() {
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
        _updateState(() => _menuResizeInFlight = false);
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
    _updateState(() => _menuResizeInFlight = true);
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _menuAnimController.value = 0;
      } else {
        await _menuAnimController.reverse();
      }
      if (!mounted) return;
      _updateState(() => _isMenuOpen = false);
      await WidgetsBinding.instance.endOfFrame;
      final bounds = await _readWindowBounds();
      if (!mounted) return;
      double resetLeft = bounds.left + _leftPadding;
      _leftPadding = 0.0;
      await _writeWindowBounds(
        Rect.fromLTWH(
          resetLeft,
          bounds.top,
          bounds.width - _menuNativeExtra,
          bounds.height,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    } catch (error) {
      debugPrint('右键菜单收起失败: $error');
    } finally {
      if (mounted) {
        _updateState(() {
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
            _updateState(() {});
            unawaited(_updateColorScheme());
            unawaited(AppState.saveSettings());
          },
          onVisualChanged: () {
            _updateState(() {});
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
}
