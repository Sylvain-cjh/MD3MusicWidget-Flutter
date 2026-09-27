import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';

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

  const SettingsSectionNavigation({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.shape,
    required this.onSelected,
  });

  @override
  State<SettingsSectionNavigation> createState() =>
      _SettingsSectionNavigationState();
}

class _SettingsSectionNavigationState extends State<SettingsSectionNavigation> {
  int? _activePointer;
  int? _previewIndex;
  double? _previewCenterX;
  double _grabOffsetX = 0;
  int? _hoveredIndex;

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

  void _cancelPreview() {
    if (_activePointer == null) return;
    setState(() {
      _activePointer = null;
      _previewIndex = null;
      _previewCenterX = null;
    });
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
        final compact = width < 450;
        final height = compact ? 56.0 : 48.0;
        final slotWidth = width / destinations.length;
        final indicatorIndex = _previewIndex ?? widget.selectedIndex;
        final indicatorCenter =
            _previewCenterX ?? (indicatorIndex + 0.5) * slotWidth;
        final indicatorAlignment = destinations.length == 1
            ? 0.0
            : 2 * (indicatorCenter - slotWidth / 2) / (width - slotWidth) - 1;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (_activePointer != null ||
                    event.buttons & kPrimaryButton == 0) {
                  return;
                }
                final index = _indexAt(event.localPosition.dx, width);
                final center = (index + 0.5) * slotWidth;
                setState(() {
                  _activePointer = event.pointer;
                  _previewIndex = index;
                  _previewCenterX = center;
                  _grabOffsetX = event.localPosition.dx - center;
                });
              },
              onPointerMove: (event) {
                if (_activePointer != event.pointer) return;
                final center = (event.localPosition.dx - _grabOffsetX).clamp(
                  slotWidth / 2,
                  width - slotWidth / 2,
                );
                final index = _indexAt(center, width);
                if (center != _previewCenterX) {
                  setState(() {
                    _previewCenterX = center;
                    _previewIndex = index;
                  });
                }
              },
              onPointerUp: (event) {
                if (_activePointer != event.pointer) return;
                final inside =
                    event.localPosition.dx >= 0 &&
                    event.localPosition.dx < width &&
                    event.localPosition.dy >= 0 &&
                    event.localPosition.dy < height;
                final index = inside
                    ? _indexAt(
                        (event.localPosition.dx - _grabOffsetX).clamp(
                          slotWidth / 2,
                          width - slotWidth / 2,
                        ),
                        width,
                      )
                    : null;
                setState(() {
                  _activePointer = null;
                  _previewIndex = null;
                  _previewCenterX = null;
                  _hoveredIndex = event.kind == PointerDeviceKind.mouse
                      ? index
                      : null;
                });
                if (index != null && index != widget.selectedIndex) {
                  widget.onSelected(index);
                }
              },
              onPointerCancel: (_) => _cancelPreview(),
              child: SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Row(
                      children: [
                        for (
                          var index = 0;
                          index < destinations.length;
                          index++
                        )
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
                                  key: ValueKey(
                                    'settings_section_hover_$index',
                                  ),
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
                    AnimatedAlign(
                      key: const ValueKey('settings_section_indicator'),
                      alignment: Alignment(indicatorAlignment, 0),
                      duration: _activePointer != null || reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeInOutCubicEmphasized,
                      child: FractionallySizedBox(
                        widthFactor: 1 / destinations.length,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: DecoratedBox(
                            key: const ValueKey(
                              'settings_section_indicator_surface',
                            ),
                            decoration: ShapeDecoration(
                              color: scheme.secondaryContainer,
                              shape: shape,
                              shadows: [
                                BoxShadow(
                                  color: scheme.shadow.withValues(alpha: 0.16),
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
                    Row(
                      children: [
                        for (
                          var index = 0;
                          index < destinations.length;
                          index++
                        )
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
          ),
        );
      },
    );
  }
}
