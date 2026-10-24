part of 'playerView.dart';


extension _PlayerRendering on _PlayerViewState {
  Widget _buildPlayer(BuildContext context) {
    _finishLayoutWhenViewportReady();
    bool isV = _displayLayout == WidgetLayout.vertical;
    bool isOpen = _settingsVisualOpen;
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
          sLeft = -innerSettingsW;
        } else {
          pLeft = 0;
          sLeft = innerPlayerW;
        }
      } else {
        pLeft = 0;
        
        
        sTop = innerPlayerH;
      }
    }

    double containerW = isV
        ? (isOpen ? innerPlayerW + innerSettingsW : innerPlayerW)
        : innerPlayerW;
    double containerH = isV
        ? innerPlayerH
        : (isOpen ? innerPlayerH + innerSettingsH : innerPlayerH);
    final retainedSettingsCanvas = !_layoutMotion.active && !_layoutPreparing
        ? _settingsCanvasSize
        : null;
    final canvasDesignW = math.max(
      containerW,
      retainedSettingsCanvas?.width ?? 0,
    );
    final canvasDesignH = math.max(
      containerH,
      retainedSettingsCanvas?.height ?? 0,
    );
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
        ? (_settingsTransitionActive
              ? MediaMotionTokens.settingsDisclosure
              : AppState.layoutSwitchDuration)
        : Duration.zero;
    final frameCurve = _settingsTransitionActive
        ? MediaMotionTokens.settingsDisclosureCurve
        : AppState.layoutSwitchCurve;

    final backgroundAnchorHeight =
        innerPlayerH - AppState.nextUpPanelExtentOf(_displayLayout);
    final backgroundAnchorWidth = innerPlayerW;
    final backgroundAnchorLeft = pLeft;
    final backgroundAnchor = (
      backgroundAnchorWidth,
      backgroundAnchorHeight,
      backgroundAnchorLeft,
      isV,
      _layoutMotion.active || _layoutPreparing,
      frameAnimationDuration,
      frameCurve,
    );
    if (_backgroundAnchor != backgroundAnchor) {
      _backgroundAnchor = backgroundAnchor;
      _anchoredPlayerBackground = TweenAnimationBuilder<double>(
        tween: Tween(begin: backgroundAnchorLeft, end: backgroundAnchorLeft),
        duration: frameAnimationDuration,
        curve: frameCurve,
        builder: (context, displayedLeft, _) => RepaintBoundary(
          child: DynamicBackground(
            anchorHeight: backgroundAnchorHeight,
            anchorWidth: backgroundAnchorWidth,
            anchorLeft: displayedLeft,
            verticalLayout: isV,
            animateArtworkReplacement:
                !(_layoutMotion.active || _layoutPreparing),
          ),
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
          curve: frameCurve,
          left: sLeft,
          top: sTop,
          width: innerSettingsW,
          height: innerSettingsH,
          child: _followLyrics(
            SettingsDisclosure(
              open: isOpen,
              axis: isV ? Axis.horizontal : Axis.vertical,
              fromLeft: side == 'left',
              onSettled: _onSettingsSettled,
              child: _buildSettingsPanel(),
            ),
            verticalSettings: isV,
            settingsHeight: innerSettingsH,
          ),
        ),
        MorphPositioned(
          motion: _layoutMotion,
          duration: frameAnimationDuration,
          curve: frameCurve,
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
            : math.max(canvasDesignW * stageScale, visibleW);
        final canvasH = _layoutMotion.active
            ? _layoutMotion.canvas.height
            : math.max(canvasDesignH * stageScale, visibleH);
        
        
        
        final targetBackgroundSize = Size(canvasDesignW, canvasDesignH);
        final retainDisclosureCanvas =
            !_layoutMotion.active &&
            !_layoutPreparing &&
            retainedSettingsCanvas != null;
        final backdrop = Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: transformOnly
                ? canvasDesignW
                : retainDisclosureCanvas
                ? canvasW
                : visibleW,
            height: transformOnly
                ? canvasDesignH
                : retainDisclosureCanvas
                ? canvasH
                : visibleH,
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
              : canvasDesignW,
          designHeight:
              (_layoutMotion.active || _layoutPreparing) && !transformOnly
              ? canvasH / animatedContentScale
              : canvasDesignH,
          frameScale: animatedFrameScale,
          contentScale: animatedContentScale,
          alignment: componentAlignment,
          frameAnimationDuration: frameAnimationDuration,
          frameAnimationCurve: frameCurve,
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
