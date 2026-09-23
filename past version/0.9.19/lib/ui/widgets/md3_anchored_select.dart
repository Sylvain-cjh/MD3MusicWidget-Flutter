import 'package:flutter/material.dart';

class Md3AnchoredSelect<T> extends StatefulWidget {
  final T value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final double width;
  final double height;
  final bool enabled;

  const Md3AnchoredSelect({
    super.key,
    required this.value,
    required this.entries,
    required this.onSelected,
    this.width = 156,
    this.height = 48,
    this.enabled = true,
  });

  @override
  State<Md3AnchoredSelect<T>> createState() => _Md3AnchoredSelectState<T>();
}

class _Md3AnchoredSelectState<T> extends State<Md3AnchoredSelect<T>> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _expanded = false;

  DropdownMenuEntry<T> get _selectedEntry {
    for (final entry in widget.entries) {
      if (entry.value == widget.value) return entry;
    }
    return widget.entries.first;
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
    final bool disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    setState(() => _expanded = true);
    T? result;
    try {
      result = await navigator.push<T>(
        _Md3SelectRoute<T>(
          anchorRect: anchorRect,
          selectedIndex: widget.entries.indexWhere(
            (entry) => entry.value == widget.value,
          ),
          entries: widget.entries,
          width: anchorRect.width,
          itemHeight: anchorRect.height,
          visualScale: anchorRect.height / widget.height,
          disableAnimations: disableAnimations,
          barrierLabel: MaterialLocalizations.of(context).menuDismissLabel,
          capturedThemes: InheritedTheme.capture(
            from: context,
            to: navigator.context,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _expanded = false);
    }

    if (result != null && result != widget.value) {
      widget.onSelected(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextStyle? textStyle = Theme.of(context).textTheme.labelLarge;
    final DropdownMenuEntry<T> selected = _selectedEntry;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      expanded: _expanded,
      value: selected.label,
      child: Material(
        key: _anchorKey,
        color: widget.enabled
            ? scheme.surfaceContainerHighest
            : scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
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
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selected.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle?.copyWith(
                        color: widget.enabled
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.38),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 160),
                    curve: const Cubic(0.23, 1.0, 0.32, 1.0),
                    child: Icon(
                      Icons.arrow_drop_down_rounded,
                      color: widget.enabled
                          ? (_expanded
                                ? scheme.primary
                                : scheme.onSurfaceVariant)
                          : scheme.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Md3SelectRoute<T> extends PopupRoute<T> {
  final Rect anchorRect;
  final int selectedIndex;
  final List<DropdownMenuEntry<T>> entries;
  final double width;
  final double itemHeight;
  final double visualScale;
  final bool disableAnimations;
  final CapturedThemes capturedThemes;

  @override
  final String barrierLabel;

  _Md3SelectRoute({
    required this.anchorRect,
    required this.selectedIndex,
    required this.entries,
    required this.width,
    required this.itemHeight,
    required this.visualScale,
    required this.disableAnimations,
    required this.barrierLabel,
    required this.capturedThemes,
  }) : super(
         requestFocus: true,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  static const double _screenPadding = 8;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => disableAnimations
      ? const Duration(milliseconds: 120)
      : const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => disableAnimations
      ? const Duration(milliseconds: 100)
      : const Duration(milliseconds: 160);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final Widget page = Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Size viewport = constraints.biggest;
          final double menuPadding = 8 * visualScale;
          final double contentHeight =
              entries.length * itemHeight + menuPadding * 2;
          final double menuHeight = contentHeight.clamp(
            0.0,
            viewport.height - _screenPadding * 2,
          );
          final int safeSelectedIndex = selectedIndex < 0 ? 0 : selectedIndex;
          final double selectedContentCenter =
              menuPadding + safeSelectedIndex * itemHeight + itemHeight / 2;
          final double idealTop = anchorRect.center.dy - selectedContentCenter;
          final double top = idealTop.clamp(
            _screenPadding,
            viewport.height - menuHeight - _screenPadding,
          );
          final double desiredSelectedCenter = anchorRect.center.dy - top;
          final double maxScrollOffset = contentHeight - menuHeight;
          final double initialScrollOffset =
              (selectedContentCenter - desiredSelectedCenter).clamp(
                0.0,
                maxScrollOffset,
              );
          final double selectedViewportCenter =
              selectedContentCenter - initialScrollOffset;
          final double left = anchorRect.left.clamp(
            _screenPadding,
            viewport.width - width - _screenPadding,
          );

          return Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                height: menuHeight,
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final double progress = const Cubic(
                      0.23,
                      1.0,
                      0.32,
                      1.0,
                    ).transform(animation.value);
                    if (disableAnimations) {
                      return Opacity(opacity: progress, child: child);
                    }
                    return ClipPath(
                      key: const ValueKey('md3-select-reveal'),
                      clipBehavior: Clip.antiAlias,
                      clipper: _SelectedItemRevealClipper(
                        progress: progress,
                        selectedCenter: selectedViewportCenter,
                        initialHeight: itemHeight,
                        cornerRadius: 12 * visualScale,
                      ),
                      child: child,
                    );
                  },
                  child: _Md3SelectMenu<T>(
                    entries: entries,
                    selectedIndex: safeSelectedIndex,
                    initialScrollOffset: initialScrollOffset,
                    rowHeight: itemHeight,
                    visualScale: visualScale,
                  ),
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

  const _Md3SelectMenu({
    required this.entries,
    required this.selectedIndex,
    required this.initialScrollOffset,
    required this.rowHeight,
    required this.visualScale,
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
      color: scheme.surfaceContainerHighest,
      elevation: 2 * widget.visualScale,
      shadowColor: scheme.shadow.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12 * widget.visualScale),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(vertical: 8 * widget.visualScale),
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(widget.entries.length, (index) {
              final DropdownMenuEntry<T> entry = widget.entries[index];
              final bool selected = index == widget.selectedIndex;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 4 * widget.visualScale,
                ),
                child: MenuItemButton(
                  autofocus: selected,
                  onPressed: entry.enabled
                      ? () => Navigator.of(context).pop(entry.value)
                      : null,
                  trailingIcon: SizedBox.square(
                    dimension: 24 * widget.visualScale,
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 20 * widget.visualScale,
                            color: scheme.primary,
                          )
                        : null,
                  ),
                  style: ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(
                      Size(0, widget.rowHeight),
                    ),
                    maximumSize: WidgetStatePropertyAll(
                      Size(double.infinity, widget.rowHeight),
                    ),
                    padding: WidgetStatePropertyAll(
                      EdgeInsetsDirectional.only(
                        start: 12 * widget.visualScale,
                        end: 6 * widget.visualScale,
                      ),
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          8 * widget.visualScale,
                        ),
                      ),
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
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
                    foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
                    textStyle: WidgetStatePropertyAll(
                      Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize:
                            (Theme.of(context).textTheme.labelLarge?.fontSize ??
                                14) *
                            widget.visualScale,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _SelectedItemRevealClipper extends CustomClipper<Path> {
  final double progress;
  final double selectedCenter;
  final double initialHeight;
  final double cornerRadius;

  const _SelectedItemRevealClipper({
    required this.progress,
    required this.selectedCenter,
    required this.initialHeight,
    required this.cornerRadius,
  });

  @override
  Path getClip(Size size) {
    final double initialHalfHeight = initialHeight / 2;
    final double top = (selectedCenter - initialHalfHeight) * (1.0 - progress);
    final double bottom =
        selectedCenter +
        initialHalfHeight +
        (size.height - selectedCenter - initialHalfHeight) * progress;
    final Rect revealRect = Rect.fromLTRB(
      0,
      top.clamp(0.0, size.height),
      size.width,
      bottom.clamp(0.0, size.height),
    );
    return Path()..addRRect(
      RRect.fromRectAndRadius(revealRect, Radius.circular(cornerRadius)),
    );
  }

  @override
  bool shouldReclip(_SelectedItemRevealClipper oldClipper) =>
      oldClipper.progress != progress ||
      oldClipper.selectedCenter != selectedCenter ||
      oldClipper.initialHeight != initialHeight ||
      oldClipper.cornerRadius != cornerRadius;
}
