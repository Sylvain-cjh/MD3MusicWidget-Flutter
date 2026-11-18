import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../animations/mediaMotionTokens.dart';
import 'continuousSurfaceBorder.dart';
import 'smoothRoundedClip.dart';

typedef _SelectActiveRow = Widget Function(BuildContext context, double scale);

class Md3AnchoredSelect<T> extends StatefulWidget {
  final T value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final double width;
  final double height;
  final bool enabled;
  final bool _chip;
  final double? _chipMenuWidth;
  final IconData? _chipIcon;
  final String? semanticLabel;
  final Widget Function(BuildContext context, double scale)? activeRow;

  const Md3AnchoredSelect({
    super.key,
    required this.value,
    required this.entries,
    required this.onSelected,
    this.width = 156,
    this.height = 48,
    this.enabled = true,
  }) : _chip = false,
       _chipMenuWidth = null,
       _chipIcon = null,
       semanticLabel = null,
       activeRow = null;

  const Md3AnchoredSelect.chip({
    super.key,
    required this.value,
    required this.entries,
    required this.onSelected,
    required IconData icon,
    this.semanticLabel,
    this.activeRow,
    double menuWidth = 252,
    this.width = 154,
    this.height = 28,
    this.enabled = true,
  }) : _chip = true,
       _chipMenuWidth = menuWidth,
       _chipIcon = icon;

  @override
  State<Md3AnchoredSelect<T>> createState() => _Md3AnchoredSelectState<T>();
}

class _Md3AnchoredSelectState<T> extends State<Md3AnchoredSelect<T>> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _expanded = false;

  int get _selectedIndex =>
      widget.entries.indexWhere((entry) => entry.value == widget.value);

  _SelectFaceStyle _faceStyle(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chip = widget._chip;
    final ink = chip ? scheme.onPrimaryContainer : scheme.onSurface;
    return (
      radius: chip
          ? BorderRadius.circular(widget.height * .62)
          : SmoothSurfaceCorners.control,
      fill: widget.enabled || chip
          ? (chip ? scheme.primaryContainer : scheme.surfaceContainerHighest)
          : scheme.onSurface.withValues(alpha: .08),
      ink: widget.enabled ? ink : scheme.onSurface.withValues(alpha: .38),
      arrow: widget.enabled
          ? scheme.onSurfaceVariant
          : scheme.onSurface.withValues(alpha: .38),
      font: (theme.textTheme.labelLarge ?? const TextStyle(fontSize: 14))
          .copyWith(fontSize: chip ? 12.5 : null, fontWeight: FontWeight.w500),
      leading: widget._chipIcon,
    );
  }

  Future<void> _openMenu() async {
    if (!widget.enabled || _expanded || widget.entries.isEmpty) return;

    final NavigatorState navigator = Navigator.of(context);
    final RenderBox? anchor =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        navigator.overlay?.context.findRenderObject() as RenderBox?;
    if (anchor == null || overlay == null || !anchor.hasSize) return;

    final Offset topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final Offset bottomRight = anchor.localToGlobal(
      anchor.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final Rect anchorRect = Rect.fromPoints(topLeft, bottomRight);
    if (anchorRect.isEmpty) return;
    final bool disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final scale = anchorRect.height / widget.height;
    final route = _Md3SelectRoute<T>(
      anchorRect: anchorRect,
      selectedIndex: math.max(_selectedIndex, 0),
      entries: List.unmodifiable(widget.entries),
      face: _faceStyle(context),
      width: math.max(anchorRect.width, (widget._chipMenuWidth ?? 0) * scale),
      itemHeight: widget._chip ? 42 * scale : anchorRect.height,
      visualScale: scale,
      alignEnd: widget._chip,
      activeRow: widget.activeRow,
      disableAnimations: disableAnimations,
      barrierLabel: MaterialLocalizations.of(context).menuDismissLabel,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
    );

    setState(() => _expanded = true);
    try {
      final choice = await navigator.push<T>(route);
      
      
      
      await route.completed;
      if (mounted && choice != null && choice != widget.value) {
        widget.onSelected(choice);
      }
    } finally {
      if (mounted) setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final face = _faceStyle(context);
    final label = widget.entries.isEmpty
        ? ''
        : widget.entries[math.max(_selectedIndex, 0)].label;
    final bool hide =
        _expanded && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      expanded: _expanded,
      label: widget.semanticLabel,
      value: label,
      child: Opacity(
        key: const ValueKey('md3-select-anchor-visibility'),
        opacity: hide ? 0 : 1,
        child: Material(
          key: _anchorKey,
          color: face.fill,
          shape: SmoothSurfaceCorners.shape(face.radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.enabled ? _openMenu : null,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return scheme.primary.withValues(alpha: 0.12);
              }
              if (states.contains(WidgetState.focused)) {
                return scheme.primary.withValues(alpha: 0.10);
              }
              if (states.contains(WidgetState.hovered)) {
                return scheme.primary.withValues(alpha: 0.08);
              }
              return null;
            }),
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: _SelectFace(label: label, style: face),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _SelectFaceStyle = ({
  BorderRadius radius,
  Color fill,
  Color ink,
  Color arrow,
  TextStyle font,
  IconData? leading,
});

class _SelectFace extends StatelessWidget {
  final String label;
  final _SelectFaceStyle style;
  final double scale;
  final double progress;
  final bool toActiveRow;

  const _SelectFace({
    required this.label,
    required this.style,
    this.scale = 1,
    this.progress = 0,
    this.toActiveRow = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(
      start:
          (style.leading == null
              ? 16
              : 10 + (toActiveRow ? 11 * progress : 0)) *
          scale,
      end: 10 * scale,
    ),
    child: Row(
      children: [
        if (style.leading case final icon?) ...[
          Icon(
            icon,
            size: (15 + (toActiveRow ? 4 * progress : 0)) * scale,
            color: style.ink,
          ),
          SizedBox(width: (6 + (toActiveRow ? 7 * progress : 0)) * scale),
        ],
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.font.copyWith(
              fontSize: (style.font.fontSize ?? 14) * scale,
              color: style.ink,
            ),
          ),
        ),
        if (style.leading == null)
          Transform.rotate(
            angle: progress * math.pi,
            child: Icon(
              Icons.arrow_drop_down_rounded,
              size: 24 * scale,
              color: style.arrow,
            ),
          ),
      ],
    ),
  );
}

class _Md3SelectRoute<T> extends PopupRoute<T> {
  final Rect anchorRect;
  final int selectedIndex;
  final List<DropdownMenuEntry<T>> entries;
  final _SelectFaceStyle face;
  final double width;
  final double itemHeight;
  final double visualScale;
  final bool alignEnd;
  final _SelectActiveRow? activeRow;
  final bool disableAnimations;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  _Md3SelectRoute({
    required this.anchorRect,
    required this.selectedIndex,
    required this.entries,
    required this.face,
    required this.width,
    required this.itemHeight,
    required this.visualScale,
    required this.alignEnd,
    required this.activeRow,
    required this.disableAnimations,
    required this.barrierLabel,
    required this.capturedThemes,
  }) : super(
         requestFocus: true,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  static const double _screenPadding = 8;
  static const double _chipTopInset = 24;
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => disableAnimations
      ? const Duration(milliseconds: 120)
      : alignEnd
      ? MediaMotionTokens.outputMenuOpen
      : const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => disableAnimations
      ? const Duration(milliseconds: 100)
      : alignEnd
      ? MediaMotionTokens.outputMenuClose
      : const Duration(milliseconds: 160);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final chipMorph = alignEnd && !disableAnimations;
    final shapeCurve = chipMorph
        ? MediaMotionTokens.outputMenuHeightCurve
        : MediaMotionTokens.settleCurve;
    final surfaceMotion = animation.drive(CurveTween(curve: shapeCurve));
    
    
    final rowMotion = chipMorph ? surfaceMotion : animation;
    final selectedBlend = rowMotion.drive(
      CurveTween(
        curve: chipMorph
            ? const Interval(
                .59,
                .78,
                curve: MediaMotionTokens.surfaceOpacityCurve,
              )
            : const Interval(.42, .74, curve: Curves.easeInOut),
      ),
    );
    final Widget page = Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Size viewport = constraints.biggest;
          final double menuPadding =
              SmoothSurfaceCorners.popoverRowInset * visualScale;
          final double contentHeight =
              entries.length * itemHeight + menuPadding * 2;
          final int safeSelectedIndex = selectedIndex < 0 ? 0 : selectedIndex;
          final double selectedContentCenter =
              menuPadding + safeSelectedIndex * itemHeight + itemHeight / 2;
          final double topInset = alignEnd
              ? math.max(
                  _screenPadding,
                  math.min(_chipTopInset * visualScale, viewport.height / 8),
                )
              : _screenPadding;
          
          
          
          final double rowHalfExtent = menuPadding + itemHeight / 2;
          final double minCenter = topInset + rowHalfExtent;
          final double maxCenter =
              viewport.height - _screenPadding - rowHalfExtent;
          final double selectedCenter = alignEnd && minCenter <= maxCenter
              ? anchorRect.center.dy.clamp(minCenter, maxCenter)
              : anchorRect.center.dy;
          final double visibleAbove = math.min(
            selectedContentCenter,
            math.max(0, selectedCenter - topInset),
          );
          final double visibleBelow = math.min(
            contentHeight - selectedContentCenter,
            math.max(0, viewport.height - _screenPadding - selectedCenter),
          );
          final double menuHeight = visibleAbove + visibleBelow;
          final double top = selectedCenter - visibleAbove;
          final double initialScrollOffset =
              selectedContentCenter - visibleAbove;
          final double sidePadding = math.min(
            _screenPadding,
            viewport.width / 2,
          );
          final double menuWidth = math.min(
            width,
            viewport.width - sidePadding * 2,
          );
          if (menuWidth <= 0 || menuHeight <= 0) return const SizedBox.shrink();
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final double desiredLeft = alignEnd && !rtl
              ? anchorRect.right - menuWidth
              : anchorRect.left;
          final double left = desiredLeft.clamp(
            sidePadding,
            viewport.width - menuWidth - sidePadding,
          );
          final menuRect = Rect.fromLTWH(left, top, menuWidth, menuHeight);
          final bounds = anchorRect.expandToInclude(menuRect);
          final origin = -bounds.topLeft;
          final anchor = anchorRect.shift(origin);
          final menu = menuRect.shift(origin);
          final double selectedLocalY = selectedCenter + origin.dy;
          final menuRadius = SmoothSurfaceCorners.popover * visualScale;
          final scheme = Theme.of(context).colorScheme;
          Widget menuContent = _Md3SelectMenu<T>(
            entries: entries,
            selectedIndex: safeSelectedIndex,
            initialScrollOffset: initialScrollOffset,
            rowHeight: itemHeight,
            visualScale: visualScale,
            face: face,
            activeRow: activeRow,
            animation: rowMotion,
            selectedBlend: selectedBlend,
            disableAnimations: disableAnimations,
          );
          if (alignEnd) {
            
            
            menuContent = ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: menuContent,
            );
          }
          return Stack(
            children: [
              Positioned.fromRect(
                rect: bounds,
                child: AnimatedBuilder(
                  animation: surfaceMotion,
                  builder: (context, child) {
                    final t = surfaceMotion.value;
                    final progress = disableAnimations ? 1.0 : t;
                    final heightFrame = Rect.lerp(anchor, menu, progress)!;
                    final Rect rect;
                    if (chipMorph) {
                      final widthFrame = Rect.lerp(
                        anchor,
                        menu,
                        MediaMotionTokens.outputMenuWidthCurve.transform(
                          animation.value,
                        ),
                      )!;
                      rect = Rect.fromLTRB(
                        widthFrame.left,
                        heightFrame.top,
                        widthFrame.right,
                        heightFrame.bottom,
                      );
                    } else {
                      rect = heightFrame;
                    }
                    final materialProgress = chipMorph
                        ? MediaMotionTokens.surfaceOpacityCurve.transform(
                            progress,
                          )
                        : progress;
                    final faceProgress = chipMorph
                        ? const Interval(
                            0,
                            .75,
                            curve: Curves.easeOutCubic,
                          ).transform(progress)
                        : progress;
                    
                    
                    
                    final faceOpacity =
                        1 -
                        (chipMorph
                            ? const Interval(
                                .45,
                                .61,
                                curve: MediaMotionTokens.surfaceOpacityCurve,
                              ).transform(progress)
                            : selectedBlend.value);
                    final radius = BorderRadius.lerp(
                      face.radius * visualScale,
                      menuRadius,
                      progress,
                    )!;
                    final clipper = _SelectSurfaceClipper(rect, radius);
                    final surface = CustomPaint(
                      painter: _SelectShadow(
                        clipper,
                        scheme.shadow,
                        materialProgress,
                        visualScale,
                      ),
                      child: ClipPath(
                        key: disableAnimations
                            ? null
                            : const ValueKey('md3-select-reveal'),
                        
                        
                        clipBehavior: Clip.antiAliasWithSaveLayer,
                        clipper: clipper,
                        child: ColoredBox(
                          color: Color.lerp(
                            face.fill,
                            scheme.surfaceContainerHighest,
                            materialProgress,
                          )!,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              child!,
                              if (!disableAnimations && faceOpacity > 0)
                                Positioned.fromRect(
                                  key: const ValueKey('md3-select-morph-face'),
                                  rect: Rect.fromCenter(
                                    center: Offset(
                                      rect.center.dx,
                                      anchor.center.dy +
                                          (selectedLocalY - anchor.center.dy) *
                                              faceProgress,
                                    ),
                                    width: rect.width,
                                    height: anchor.height,
                                  ),
                                  child: IgnorePointer(
                                    child: ExcludeSemantics(
                                      child: Opacity(
                                        opacity: faceOpacity,
                                        child: _SelectFace(
                                          label:
                                              entries[safeSelectedIndex].label,
                                          style: face,
                                          scale: visualScale,
                                          progress: faceProgress,
                                          toActiveRow: activeRow != null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                    return disableAnimations
                        ? Opacity(opacity: t, child: surface)
                        : surface;
                  },
                  child: Positioned.fromRect(rect: menu, child: menuContent),
                ),
              ),
            ],
          );
        },
      ),
    );
    return capturedThemes.wrap(page);
  }
}

class _Md3SelectMenu<T> extends StatefulWidget {
  final List<DropdownMenuEntry<T>> entries;
  final int selectedIndex;
  final double initialScrollOffset;
  final double rowHeight;
  final double visualScale;
  final _SelectFaceStyle face;
  final _SelectActiveRow? activeRow;
  final Animation<double> animation;
  final Animation<double> selectedBlend;
  final bool disableAnimations;

  const _Md3SelectMenu({
    required this.entries,
    required this.selectedIndex,
    required this.initialScrollOffset,
    required this.rowHeight,
    required this.visualScale,
    required this.face,
    required this.activeRow,
    required this.animation,
    required this.selectedBlend,
    required this.disableAnimations,
  });

  @override
  State<_Md3SelectMenu<T>> createState() => _Md3SelectMenuState<T>();
}

class _Md3SelectMenuState<T> extends State<_Md3SelectMenu<T>> {
  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: widget.initialScrollOffset,
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('md3-select-menu-surface'),
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(
          vertical: SmoothSurfaceCorners.popoverRowInset * widget.visualScale,
        ),
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(widget.entries.length, (index) {
              final DropdownMenuEntry<T> entry = widget.entries[index];
              final bool selected = index == widget.selectedIndex;
              final Widget row = Padding(
                padding: EdgeInsets.symmetric(
                  horizontal:
                      SmoothSurfaceCorners.popoverRowInset * widget.visualScale,
                ),
                child: selected && widget.activeRow != null
                    ? SizedBox(
                        height: widget.rowHeight,
                        child: widget.activeRow!(context, widget.visualScale),
                      )
                    : MenuItemButton(
                        overflowAxis: Axis.vertical,
                        autofocus: selected,
                        onPressed: entry.enabled
                            ? () => Navigator.of(context).pop(entry.value)
                            : null,
                        leadingIcon: widget.face.leading != null
                            ? null
                            : entry.leadingIcon,
                        trailingIcon: SizedBox.square(
                          dimension: 24 * widget.visualScale,
                          child: selected && entry.enabled
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 20 * widget.visualScale,
                                  color: scheme.primary,
                                )
                              : null,
                        ),
                        style: ButtonStyle(
                          
                          
                          
                          
                          fixedSize: WidgetStatePropertyAll(
                            Size.fromHeight(widget.rowHeight),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: WidgetStatePropertyAll(
                            Size(0, widget.rowHeight),
                          ),
                          maximumSize: WidgetStatePropertyAll(
                            Size(double.infinity, widget.rowHeight),
                          ),
                          padding: WidgetStatePropertyAll(
                            EdgeInsetsDirectional.only(
                              start:
                                  (widget.face.leading == null ? 10 : 4) *
                                  widget.visualScale,
                              end: 6 * widget.visualScale,
                            ),
                          ),
                          shape: WidgetStatePropertyAll(
                            SmoothSurfaceCorners.shape(
                              SmoothSurfaceCorners.popoverItem *
                                  widget.visualScale,
                            ),
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.pressed)) {
                              return scheme.primary.withValues(alpha: 0.12);
                            }
                            if (states.contains(WidgetState.focused)) {
                              return scheme.primary.withValues(alpha: 0.10);
                            }
                            if (states.contains(WidgetState.hovered)) {
                              return scheme.primary.withValues(alpha: 0.08);
                            }
                            return selected && entry.enabled
                                ? scheme.primary.withValues(alpha: .10)
                                : null;
                          }),
                          foregroundColor: WidgetStatePropertyAll(
                            scheme.onSurface,
                          ),
                          textStyle: WidgetStatePropertyAll(
                            widget.face.font.copyWith(
                              fontSize:
                                  (widget.face.font.fontSize ?? 14) *
                                  widget.visualScale,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (widget.face.leading != null) ...[
                              SizedBox.square(
                                dimension: 15 * widget.visualScale,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child:
                                      entry.leadingIcon ??
                                      const SizedBox.shrink(),
                                ),
                              ),
                              SizedBox(width: 6 * widget.visualScale),
                            ],
                            Expanded(
                              child: Text(
                                entry.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
              );
              if (widget.disableAnimations) return row;
              if (selected) {
                return FadeTransition(
                  opacity: widget.selectedBlend,
                  child: row,
                );
              }
              final int distance = (index - widget.selectedIndex).abs();
              
              
              final bool widens = widget.face.leading != null;
              final double start = widens
                  ? math.min(.90, .46 + (distance - 1) * .14)
                  : math.min(.52, .07 + (distance - 1) * .065);
              final Animation<double> reveal = widget.animation.drive(
                CurveTween(
                  curve: Interval(
                    start,
                    math.min(1, start + (widens ? .20 : .42)),
                    curve: widens
                        ? MediaMotionTokens.surfaceOpacityCurve
                        : MediaMotionTokens.settleCurve,
                  ),
                ),
              );
              final double travel = math.min(.18, .06 * distance);
              return FadeTransition(
                key: ValueKey('md3-select-option-$index'),
                opacity: reveal,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(
                      0,
                      index < widget.selectedIndex ? travel : -travel,
                    ),
                    end: Offset.zero,
                  ).animate(reveal),
                  child: row,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _SelectSurfaceClipper extends CustomClipper<Path> {
  final Rect rect;
  final BorderRadius radius;

  const _SelectSurfaceClipper(this.rect, this.radius);

  @override
  Path getClip(Size size) => ContinuousSurfaceBorder.outline(rect, radius);

  @override
  bool shouldReclip(_SelectSurfaceClipper oldClipper) =>
      oldClipper.rect != rect || oldClipper.radius != radius;
}

class _SelectShadow extends CustomPainter {
  final _SelectSurfaceClipper outline;
  final Color color;
  final double progress;
  final double scale;

  const _SelectShadow(this.outline, this.color, this.progress, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    canvas.drawShadow(
      outline.getClip(size),
      color.withValues(alpha: .18 * progress),
      2 * scale * progress,
      false,
    );
  }

  @override
  bool shouldRepaint(_SelectShadow oldDelegate) =>
      outline.shouldReclip(oldDelegate.outline) ||
      color != oldDelegate.color ||
      progress != oldDelegate.progress ||
      scale != oldDelegate.scale;
}
