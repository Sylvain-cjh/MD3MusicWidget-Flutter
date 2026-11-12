import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../core/appState.dart';
import '../animations/componentSizeMotion.dart';
import '../animations/settingsNavigationMotion.dart';
import 'backdropCaptureBoundary.dart';
import 'settingsControlShape.dart';
import 'smoothRoundedClip.dart';
import 'navigationGlassSurface.dart';

class SettingsSectionDestination {
  final String id;
  final String label;
  final IconData icon;

  const SettingsSectionDestination(this.id, this.label, this.icon);
}

class SettingsSectionNavigation extends StatefulWidget {
  final List<SettingsSectionDestination> destinations;
  final int selectedIndex;
  final MD3Shape shape;
  final ValueChanged<int> onSelected;
  final Duration Function()? gestureClock;
  final GlobalKey? glassBackdropKey;
  final bool glassCaptureReady;

  const SettingsSectionNavigation({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.shape,
    required this.onSelected,
    this.gestureClock,
    this.glassBackdropKey,
    this.glassCaptureReady = false,
  });

  @override
  State<SettingsSectionNavigation> createState() =>
      _SettingsSectionNavigationState();
}

class _SettingsSectionNavigationState extends State<SettingsSectionNavigation>
    with TickerProviderStateMixin {
  late final AnimationController _indicatorPosition;
  late final AnimationController _indicatorStretch;
  late final Listenable _indicatorVisual;
  final _glyphCaptureKey = GlobalKey();
  Timer? _pauseTimer;
  int? _activePointer;
  double _grabOffsetX = 0;
  double _pressStartX = 0;
  bool _dragging = false;
  bool _pressOnIndicator = false;
  bool _suppressTap = false;
  double _lastPointerX = 0;
  Duration _lastPointerTime = Duration.zero;
  double _dragVelocity = 0;
  double? _layoutWidth;
  int? _settlingIndex;
  int _settleEpoch = 0;
  int _stretchEpoch = 0;
  late final AnimationController _hoverPosition;
  late final AnimationController _hoverOpacity;
  int? _hoverTarget;
  
  static const _hoverCurve = Cubic(0.22, 1, 0.36, 1);

  @override
  void initState() {
    super.initState();
    _indicatorPosition = AnimationController.unbounded(
      vsync: this,
      value: widget.selectedIndex.toDouble(),
    );
    _indicatorStretch = AnimationController.unbounded(vsync: this);
    _hoverPosition = AnimationController.unbounded(
      vsync: this,
      value: widget.selectedIndex.toDouble(),
    );
    _hoverOpacity = AnimationController(vsync: this);
    _indicatorVisual = Listenable.merge([
      _indicatorPosition,
      _indicatorStretch,
    ]);
  }

  @override
  void didUpdateWidget(SettingsSectionNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        _activePointer == null) {
      _settleIndicator(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    _indicatorPosition.dispose();
    _indicatorStretch.dispose();
    _hoverPosition.dispose();
    _hoverOpacity.dispose();
    super.dispose();
  }

  void _settleIndicator(int index, {double velocity = 0, bool spring = false}) {
    if (_settlingIndex == index && _indicatorPosition.isAnimating) return;
    _settlingIndex = index;
    final epoch = ++_settleEpoch;
    if (MediaQuery.disableAnimationsOf(context)) {
      _indicatorPosition.value = index.toDouble();
    } else if (spring) {
      final boundedVelocity = velocity.clamp(-4.0, 4.0);
      final safeVelocity =
          (index == 0 && boundedVelocity < 0) ||
              (index == widget.destinations.length - 1 && boundedVelocity > 0)
          ? 0.0
          : boundedVelocity;
      final simulation = SpringSimulation(
        ComponentSizeMotion.frameSpring,
        _indicatorPosition.value,
        index.toDouble(),
        safeVelocity,
      )..tolerance = ComponentSizeMotion.scaleTolerance;
      _indicatorPosition.animateWith(simulation).whenCompleteOrCancel(() {
        if (mounted && _activePointer == null && epoch == _settleEpoch) {
          _indicatorPosition.value = index.toDouble();
        }
      });
    } else {
      _indicatorPosition.animateTo(
        index.toDouble(),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubicEmphasized,
      );
    }
  }

  void _settleStretch({double velocity = 0}) {
    final epoch = ++_stretchEpoch;
    if (MediaQuery.disableAnimationsOf(context)) {
      _indicatorStretch.value = 0;
      return;
    }
    final simulation = SpringSimulation(
      ComponentSizeMotion.frameSpring,
      _indicatorStretch.value,
      0,
      velocity,
    )..tolerance = ComponentSizeMotion.scaleTolerance;
    _indicatorStretch.animateWith(simulation).whenCompleteOrCancel(() {
      if (mounted && epoch == _stretchEpoch) _indicatorStretch.value = 0;
    });
  }

  void _schedulePause(int pointer, double slotWidth) {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(const Duration(milliseconds: 70), () {
      if (!mounted || _activePointer != pointer || !_dragging) return;
      final impulse = SettingsNavigationMotion.releaseImpulse(
        _dragVelocity,
        slotWidth,
      );
      _dragVelocity = 0;
      _settleStretch(velocity: impulse);
    });
  }

  void _hoverAt(int? index, bool reduced) {
    if (_hoverTarget == index) return;
    _hoverTarget = index;
    if (index != null) {
      if (reduced || _hoverOpacity.value == 0) {
        _hoverPosition.value = index.toDouble();
      } else {
        _hoverPosition.animateTo(
          index.toDouble(),
          duration: const Duration(milliseconds: 150),
          curve: _hoverCurve,
        );
      }
    }
    if (reduced) {
      _hoverOpacity.value = index == null ? 0 : 1;
    } else {
      _hoverOpacity.animateTo(
        index == null ? 0 : 1,
        duration: const Duration(milliseconds: 125),
        curve: _hoverCurve,
      );
    }
  }

  int _indexAt(double dx, double width) =>
      (dx / width * widget.destinations.length).floor().clamp(
        0,
        widget.destinations.length - 1,
      );

  Duration _gestureTime(PointerEvent event) =>
      widget.gestureClock?.call() ?? event.timeStamp;

  void _cancelPreview() {
    if (_activePointer == null) return;
    _pauseTimer?.cancel();
    setState(() {
      _activePointer = null;
      _dragging = false;
      _pressOnIndicator = false;
    });
    _dragVelocity = 0;
    _suppressTap = false;
    _settleStretch();
    _settleIndicator(widget.selectedIndex, spring: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final destinations = widget.destinations;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0 || destinations.isEmpty) return const SizedBox.shrink();
        final slotWidth = width / destinations.length;
        final compact =
            width < 450 ||
            slotWidth < MediaQuery.textScalerOf(context).scale(78);
        final height = compact ? 56.0 : 48.0;
        const inset = SmoothSurfaceCorners.navigationInset;
        final radius = SettingsControlShape.borderFor(
          widget.shape,
        ).borderRadius.resolve(TextDirection.ltr).topLeft.x;
        final glassBackdropKey = widget.glassBackdropKey;
        if (_layoutWidth != width) {
          if (_activePointer != null) {
            _grabOffsetX =
                _lastPointerX - (_indicatorPosition.value + 0.5) * slotWidth;
          }
          _layoutWidth = width;
        }
        return Material(
          type: MaterialType.transparency,
          child: MouseRegion(
            onEnter: (event) {
              if (_activePointer == null &&
                  event.kind == PointerDeviceKind.mouse) {
                _hoverAt(_indexAt(event.localPosition.dx, width), reduceMotion);
              }
            },
            onHover: (event) {
              if (_activePointer == null &&
                  event.kind == PointerDeviceKind.mouse) {
                _hoverAt(_indexAt(event.localPosition.dx, width), reduceMotion);
              }
            },
            onExit: (_) => _hoverAt(null, reduceMotion),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (_activePointer != null ||
                    event.buttons & kPrimaryButton == 0) {
                  return;
                }
                final center = (_indicatorPosition.value + 0.5) * slotWidth;
                _hoverAt(null, reduceMotion);
                _pauseTimer?.cancel();
                _indicatorPosition.stop();
                _indicatorStretch.stop();
                _settleEpoch++;
                _stretchEpoch++;
                _settlingIndex = null;
                _dragVelocity = 0;
                _suppressTap = false;
                setState(() {
                  _activePointer = event.pointer;
                  _dragging = false;
                  _pressOnIndicator =
                      (event.localPosition.dx - center).abs() <= slotWidth / 2;
                  _pressStartX = event.localPosition.dx;
                  _lastPointerX = event.localPosition.dx;
                  _lastPointerTime = _gestureTime(event);
                  _grabOffsetX = event.localPosition.dx - center;
                });
              },
              onPointerMove: (event) {
                if (_activePointer != event.pointer || !_pressOnIndicator) {
                  return;
                }
                if (!_dragging &&
                    (event.localPosition.dx - _pressStartX).abs() < 3) {
                  return;
                }
                _dragging = true;
                final deltaX = event.localPosition.dx - _lastPointerX;
                final eventTime = _gestureTime(event);
                final elapsed =
                    (eventTime - _lastPointerTime).inMicroseconds /
                    Duration.microsecondsPerSecond;
                final frameElapsed = elapsed > 0 ? elapsed : 1 / 120;
                final instantaneousVelocity = (deltaX / frameElapsed).clamp(
                  -3000.0,
                  3000.0,
                );
                _dragVelocity =
                    _dragVelocity * 0.25 + instantaneousVelocity * 0.75;
                _lastPointerX = event.localPosition.dx;
                _lastPointerTime = eventTime;
                final center = SettingsNavigationMotion.elasticCenter(
                  event.localPosition.dx - _grabOffsetX,
                  slotWidth,
                  width,
                  reduceMotion: reduceMotion,
                );
                final rawIndex = center / slotWidth - 0.5;
                _indicatorPosition.value =
                    rawIndex < 0 || rawIndex > destinations.length - 1
                    ? rawIndex
                    : SettingsNavigationMotion.dampedIndex(rawIndex, 0);
                _stretchEpoch++;
                _indicatorStretch.stop();
                final targetStretch = _pressOnIndicator && !reduceMotion
                    ? SettingsNavigationMotion.signedStretch(
                        rawIndex,
                        _dragVelocity,
                      )
                    : 0;
                _indicatorStretch.value = reduceMotion
                    ? 0
                    : _indicatorStretch.value +
                          (targetStretch - _indicatorStretch.value) *
                              (frameElapsed / 0.04).clamp(0.0, 1.0);
                _schedulePause(event.pointer, slotWidth);
              },
              onPointerUp: (event) {
                if (_activePointer != event.pointer) return;
                _pauseTimer?.cancel();
                final inside =
                    event.localPosition.dx >= 0 &&
                    event.localPosition.dx < width &&
                    event.localPosition.dy >= 0 &&
                    event.localPosition.dy < height;
                final dragged = _dragging;
                _suppressTap = dragged;
                final elapsedSinceMove = _gestureTime(event) - _lastPointerTime;
                final velocity =
                    elapsedSinceMove < Duration.zero ||
                        elapsedSinceMove > const Duration(milliseconds: 80)
                    ? 0.0
                    : _dragVelocity;
                final index = inside
                    ? dragged
                          ? _indicatorPosition.value.round().clamp(
                              0,
                              destinations.length - 1,
                            )
                          : _indexAt(event.localPosition.dx, width)
                    : null;
                setState(() {
                  _activePointer = null;
                  _dragging = false;
                  _pressOnIndicator = false;
                });
                _hoverAt(
                  inside && event.kind == PointerDeviceKind.mouse
                      ? _indexAt(event.localPosition.dx, width)
                      : null,
                  reduceMotion,
                );
                _settleStretch(
                  velocity: dragged
                      ? SettingsNavigationMotion.releaseImpulse(
                          velocity,
                          slotWidth,
                        )
                      : 0,
                );
                if (dragged && index != null && index != widget.selectedIndex) {
                  _settleIndicator(
                    index,
                    velocity: velocity / slotWidth,
                    spring: true,
                  );
                  widget.onSelected(index);
                } else if (dragged ||
                    index == null ||
                    index == widget.selectedIndex) {
                  _settleIndicator(
                    widget.selectedIndex,
                    velocity: dragged ? velocity / slotWidth : 0,
                    spring: dragged,
                  );
                }
              },
              onPointerCancel: (event) {
                if (_activePointer == event.pointer) _cancelPreview();
              },
              child: _withGlass(glassBackdropKey, Size(width, height), (glass) {
                final hasGlyphPlane = glassBackdropKey != null;
                final glyphPlane = hasGlyphPlane
                    ? _buildGlyphPlane(context, compact)
                    : null;
                final trackColor = scheme.surfaceContainerHighest.withValues(
                  alpha:
                      glassBackdropKey != null &&
                          MediaQuery.highContrastOf(context)
                      ? 1
                      : glass == null
                      ? .72
                      : .44,
                );
                return TweenAnimationBuilder<double>(
                  tween: Tween(end: radius),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: _hoverCurve,
                  builder: (context, rounding, _) {
                    final shape = SmoothSurfaceCorners.shape(
                      BorderRadius.circular(rounding),
                    );
                    final trackShape = SmoothSurfaceCorners.navigationTrack(
                      shape,
                    );
                    return SizedBox(
                      height: height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              key: const ValueKey(
                                'settings_section_navigation_track',
                              ),
                              decoration: ShapeDecoration(
                                color: trackColor,
                                shape: trackShape,
                              ),
                              child: glass == null
                                  ? null
                                  : NavigationGlassTrack(
                                      key: const ValueKey(
                                        'navigation_glass_base',
                                      ),
                                      texture: glass,
                                      shape: trackShape,
                                      color: trackColor,
                                      radius: rounding + inset,
                                    ),
                            ),
                          ),
                          if (glyphPlane != null && glass?.glyphs != null)
                            glyphPlane,
                          Positioned(
                            top: inset,
                            bottom: inset,
                            left: inset,
                            width: (slotWidth - inset * 2).clamp(
                              0.0,
                              double.infinity,
                            ),
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: _hoverPosition,
                                child: FadeTransition(
                                  opacity: _hoverOpacity,
                                  child: RepaintBoundary(
                                    child: DecoratedBox(
                                      key: const ValueKey(
                                        'settings_section_hover_surface',
                                      ),
                                      decoration: ShapeDecoration(
                                        shape: shape,
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.085,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                builder: (context, child) =>
                                    Transform.translate(
                                      offset: Offset(
                                        slotWidth * _hoverPosition.value,
                                        0,
                                      ),
                                      child: child,
                                    ),
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _indicatorVisual,
                            builder: (context, _) {
                              final alignment = destinations.length == 1
                                  ? 0.0
                                  : 2 *
                                            _indicatorPosition.value /
                                            (destinations.length - 1) -
                                        1;
                              final stretch = reduceMotion
                                  ? 0.0
                                  : _indicatorStretch.value.clamp(-0.18, 0.18);
                              final stretchMagnitude = stretch.abs();
                              return Align(
                                key: const ValueKey(
                                  'settings_section_indicator',
                                ),
                                alignment: Alignment(alignment, 0),
                                child: FractionallySizedBox(
                                  widthFactor: 1 / destinations.length,
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      SmoothSurfaceCorners.navigationInset,
                                    ),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(
                                        end:
                                            _activePointer != null &&
                                                _pressOnIndicator &&
                                                !reduceMotion
                                            ? SettingsNavigationMotion
                                                  .pressScale
                                            : 1.0,
                                      ),
                                      duration: reduceMotion
                                          ? Duration.zero
                                          : Duration(
                                              milliseconds:
                                                  _activePointer == null
                                                  ? 210
                                                  : 120,
                                            ),
                                      curve: _activePointer == null
                                          ? Curves.easeOutBack
                                          : Curves.easeOutCubic,
                                      builder: (context, value, child) =>
                                          Transform.scale(
                                            key: const ValueKey(
                                              'settings_section_indicator_press_scale',
                                            ),
                                            scaleX: value,
                                            scaleY:
                                                1 +
                                                (value - 1) *
                                                    (SettingsNavigationMotion
                                                            .pressVerticalScale -
                                                        1) /
                                                    (SettingsNavigationMotion
                                                            .pressScale -
                                                        1),
                                            child: child,
                                          ),
                                      child: Transform(
                                        key: const ValueKey(
                                          'settings_section_indicator_deformation',
                                        ),
                                        alignment: stretch >= 0
                                            ? Alignment.centerLeft
                                            : Alignment.centerRight,
                                        transform: Matrix4.diagonal3Values(
                                          1 + stretchMagnitude,
                                          1 - stretchMagnitude * 0.25,
                                          1,
                                        ),
                                        child: DecoratedBox(
                                          key: const ValueKey(
                                            'settings_section_indicator_surface',
                                          ),
                                          decoration: ShapeDecoration(
                                            color: glass == null
                                                ? scheme.secondaryContainer
                                                : null,
                                            shape: shape,
                                            shadows: [
                                              BoxShadow(
                                                color: scheme.shadow.withValues(
                                                  alpha: glass == null
                                                      ? 0.16
                                                      : 0.075,
                                                ),
                                                blurRadius: glass == null
                                                    ? 8
                                                    : 5,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: glass == null
                                              ? SizedBox.expand(
                                                  key: glassBackdropKey == null
                                                      ? null
                                                      : const ValueKey(
                                                          'navigation_glass_fallback',
                                                        ),
                                                )
                                              : NavigationGlassThumb(
                                                  key: const ValueKey(
                                                    'navigation_glass_refraction',
                                                  ),
                                                  texture: glass,
                                                  shape: shape,
                                                  trackColor: trackColor,
                                                  trackRadius: rounding + inset,
                                                  position:
                                                      _indicatorPosition.value,
                                                  engaged:
                                                      _activePointer != null &&
                                                      (_pressOnIndicator ||
                                                          _dragging),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (glyphPlane != null && glass?.glyphs == null)
                            glyphPlane,
                          Row(
                            children: [
                              for (
                                var index = 0;
                                index < destinations.length;
                                index++
                              )
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                      SmoothSurfaceCorners.navigationInset,
                                    ),
                                    child: Semantics(
                                      button: true,
                                      selected: widget.selectedIndex == index,
                                      child: InkWell(
                                        key: ValueKey(
                                          'settings_section_${destinations[index].id}',
                                        ),
                                        customBorder: shape,
                                        hoverColor: Colors.transparent,
                                        highlightColor: Colors.transparent,
                                        splashColor: Colors.transparent,
                                        focusColor: scheme.primary.withValues(
                                          alpha: 0.14,
                                        ),
                                        onTap: () {
                                          if (_suppressTap) {
                                            _suppressTap = false;
                                            return;
                                          }
                                          if (widget.selectedIndex != index) {
                                            widget.onSelected(index);
                                          }
                                        },
                                        child: _destinationContent(
                                          context,
                                          destinations[index],
                                          compact: compact,
                                          showGlyph: !hasGlyphPlane,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        );
      },
    );
  }

  Widget _destinationContent(
    BuildContext context,
    SettingsSectionDestination destination, {
    required bool compact,
    bool showGlyph = true,
    bool showLabel = true,
  }) {
    final styles = Theme.of(context).textTheme;
    final glyph = showGlyph
        ? Icon(destination.icon, size: 17)
        : const SizedBox.square(dimension: 17);
    Widget label = Text(
      destination.label,
      maxLines: compact ? null : 1,
      overflow: compact ? null : TextOverflow.ellipsis,
      style: compact ? styles.labelSmall : styles.labelMedium,
    );
    if (!showLabel) {
      
      
      label = Opacity(
        opacity: 0,
        child: RichText(
          text: TextSpan(
            text: destination.label,
            style: DefaultTextStyle.of(
              context,
            ).style.merge(compact ? styles.labelSmall : styles.labelMedium),
          ),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: compact ? null : 1,
          overflow: compact ? TextOverflow.clip : TextOverflow.ellipsis,
        ),
      );
    }
    return Center(
      child: compact
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                glyph,
                const SizedBox(height: 2),
                Flexible(
                  child: FittedBox(fit: BoxFit.scaleDown, child: label),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                glyph,
                const SizedBox(width: 5),
                Flexible(child: label),
              ],
            ),
    );
  }

  Widget _buildGlyphPlane(BuildContext context, bool compact) =>
      Positioned.fill(
        key: const ValueKey('settings_navigation_glyph_plane'),
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: BackdropCaptureBoundary(
              key: _glyphCaptureKey,
              child: Row(
                children: [
                  for (final destination in widget.destinations)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(
                          SmoothSurfaceCorners.navigationInset,
                        ),
                        child: _destinationContent(
                          context,
                          destination,
                          compact: compact,
                          showLabel: false,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _withGlass(
    GlobalKey? backdropKey,
    Size size,
    Widget Function(NavigationGlassTexture?) builder,
  ) => backdropKey == null
      ? builder(null)
      : NavigationGlassSurface(
          backdropKey: backdropKey,
          glyphKey: _glyphCaptureKey,
          backgroundRevision: AppState.backgroundRevision,
          allowCapture: widget.glassCaptureReady,
          trackSize: size,
          builder: builder,
        );
}
