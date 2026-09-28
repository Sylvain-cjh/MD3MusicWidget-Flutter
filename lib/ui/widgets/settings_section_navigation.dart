import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../core/app_state.dart';
import '../animations/component_size_motion.dart';
import '../animations/settings_navigation_motion.dart';

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

  const SettingsSectionNavigation({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.shape,
    required this.onSelected,
    this.gestureClock,
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
  Timer? _pauseTimer;
  int? _activePointer;
  int? _previewIndex;
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
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _indicatorPosition = AnimationController.unbounded(
      vsync: this,
      value: widget.selectedIndex.toDouble(),
    );
    _indicatorStretch = AnimationController.unbounded(vsync: this);
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

  ShapeBorder get _shape => switch (widget.shape) {
    MD3Shape.stadium || MD3Shape.circle => const StadiumBorder(),
    MD3Shape.roundedExtraSmall => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    ),
    MD3Shape.roundedSmall => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    MD3Shape.roundedMedium => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    MD3Shape.roundedLarge => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    ),
    MD3Shape.roundedExtraLarge => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(28),
    ),
  };

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
      _previewIndex = null;
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
    final shape = _shape;
    final destinations = widget.destinations;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0 || destinations.isEmpty) return const SizedBox.shrink();
        final compact = width < 450;
        final height = compact ? 56.0 : 48.0;
        final slotWidth = width / destinations.length;
        if (_layoutWidth != width) {
          if (_activePointer != null) {
            _grabOffsetX =
                _lastPointerX - (_indicatorPosition.value + 0.5) * slotWidth;
          }
          _layoutWidth = width;
        }
        final indicatorIndex = _previewIndex ?? widget.selectedIndex;
        return Material(
          type: MaterialType.transparency,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if (_activePointer != null ||
                  event.buttons & kPrimaryButton == 0) {
                return;
              }
              final center = (_indicatorPosition.value + 0.5) * slotWidth;
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
                _previewIndex = _indicatorPosition.value.round().clamp(
                  0,
                  destinations.length - 1,
                );
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
              if (_activePointer != event.pointer || !_pressOnIndicator) return;
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
              final index = _indicatorPosition.value.round().clamp(
                0,
                destinations.length - 1,
              );
              if (index != _previewIndex) {
                setState(() => _previewIndex = index);
              }
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
                _previewIndex = null;
                _dragging = false;
                _pressOnIndicator = false;
                _hoveredIndex = event.kind == PointerDeviceKind.mouse
                    ? index
                    : null;
              });
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
            child: SizedBox(
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      key: const ValueKey('settings_section_navigation_track'),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.72,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < destinations.length; index++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: AnimatedOpacity(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 120),
                              opacity:
                                  _activePointer == null &&
                                      _hoveredIndex == index &&
                                      index != indicatorIndex
                                  ? 1
                                  : 0,
                              child: DecoratedBox(
                                key: ValueKey('settings_section_hover_$index'),
                                decoration: ShapeDecoration(
                                  shape: shape,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.075,
                                  ),
                                  shadows: [
                                    BoxShadow(
                                      color: scheme.shadow.withValues(
                                        alpha: 0.12,
                                      ),
                                      blurRadius: 7,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                    ],
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
                        key: const ValueKey('settings_section_indicator'),
                        alignment: Alignment(alignment, 0),
                        child: FractionallySizedBox(
                          widthFactor: 1 / destinations.length,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                end:
                                    _activePointer != null &&
                                        _pressOnIndicator &&
                                        !reduceMotion
                                    ? SettingsNavigationMotion.pressScale
                                    : 1.0,
                              ),
                              duration: reduceMotion
                                  ? Duration.zero
                                  : Duration(
                                      milliseconds: _activePointer == null
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
                                    color: scheme.secondaryContainer,
                                    shape: shape,
                                    shadows: [
                                      BoxShadow(
                                        color: scheme.shadow.withValues(
                                          alpha: 0.16,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < destinations.length; index++)
                        Expanded(
                          child: MouseRegion(
                            onEnter: (_) {
                              if (_activePointer == null) {
                                setState(() => _hoveredIndex = index);
                              }
                            },
                            onExit: (_) {
                              if (_hoveredIndex == index) {
                                setState(() => _hoveredIndex = null);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(3),
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
                                  child: Center(
                                    child: compact
                                        ? Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                destinations[index].icon,
                                                size: 17,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                destinations[index].label,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.labelSmall,
                                              ),
                                            ],
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                destinations[index].icon,
                                                size: 17,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                destinations[index].label,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.labelMedium,
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
