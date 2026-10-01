import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

enum LockedResizeEdge {
  topLeft,
  top,
  topRight,
  left,
  right,
  bottomLeft,
  bottom,
  bottomRight,
}

final class LockedAspectResizeGeometry {
  static Rect targetBounds({
    required Rect startBounds,
    required Size designSize,
    required LockedResizeEdge edge,
    required Offset dragDelta,
    required double minimumScale,
    required double maximumScale,
  }) {
    if (designSize.width <= 0 || designSize.height <= 0) {
      return startBounds;
    }

    final bool movesLeft = switch (edge) {
      LockedResizeEdge.topLeft ||
      LockedResizeEdge.left ||
      LockedResizeEdge.bottomLeft => true,
      _ => false,
    };
    final bool movesRight = switch (edge) {
      LockedResizeEdge.topRight ||
      LockedResizeEdge.right ||
      LockedResizeEdge.bottomRight => true,
      _ => false,
    };
    final bool movesTop = switch (edge) {
      LockedResizeEdge.topLeft ||
      LockedResizeEdge.top ||
      LockedResizeEdge.topRight => true,
      _ => false,
    };
    final bool movesBottom = switch (edge) {
      LockedResizeEdge.bottomLeft ||
      LockedResizeEdge.bottom ||
      LockedResizeEdge.bottomRight => true,
      _ => false,
    };

    final double startScale = math.min(
      startBounds.width / designSize.width,
      startBounds.height / designSize.height,
    );
    final double horizontalScale =
        (startBounds.width +
            (movesLeft
                ? -dragDelta.dx
                : movesRight
                ? dragDelta.dx
                : 0.0)) /
        designSize.width;
    final double verticalScale =
        (startBounds.height +
            (movesTop
                ? -dragDelta.dy
                : movesBottom
                ? dragDelta.dy
                : 0.0)) /
        designSize.height;

    final bool hasHorizontalMotion = movesLeft || movesRight;
    final bool hasVerticalMotion = movesTop || movesBottom;
    double targetScale;
    if (hasHorizontalMotion && hasVerticalMotion) {
      targetScale =
          (horizontalScale - startScale).abs() >=
              (verticalScale - startScale).abs()
          ? horizontalScale
          : verticalScale;
    } else if (hasHorizontalMotion) {
      targetScale = horizontalScale;
    } else {
      targetScale = verticalScale;
    }
    targetScale = targetScale.clamp(minimumScale, maximumScale).toDouble();

    final double targetWidth = designSize.width * targetScale;
    final double targetHeight = designSize.height * targetScale;
    final double targetLeft = movesLeft
        ? startBounds.right - targetWidth
        : startBounds.left;
    final double targetTop = movesTop
        ? startBounds.bottom - targetHeight
        : startBounds.top;
    return Rect.fromLTWH(targetLeft, targetTop, targetWidth, targetHeight);
  }
}

class LockedAspectResizeArea extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Size designSize;
  final double minimumScale;
  final double maximumScale;
  final double edgeSize;
  final VoidCallback? onResizeEnd;

  const LockedAspectResizeArea({
    super.key,
    required this.child,
    this.enabled = true,
    required this.designSize,
    required this.minimumScale,
    required this.maximumScale,
    this.edgeSize = 8,
    this.onResizeEnd,
  });

  @override
  State<LockedAspectResizeArea> createState() => _LockedAspectResizeAreaState();
}

class _LockedAspectResizeAreaState extends State<LockedAspectResizeArea> {
  Rect? _startBounds;
  Offset _dragDelta = Offset.zero;
  Rect? _pendingBounds;
  bool _frameScheduled = false;
  bool _writeInFlight = false;
  int _dragSerial = 0;

  Future<void> _startResize(LockedResizeEdge edge) async {
    if (!widget.enabled) return;
    final int serial = ++_dragSerial;
    _dragDelta = Offset.zero;
    final Rect bounds = await windowManager.getBounds();
    if (!mounted || !widget.enabled || serial != _dragSerial) return;
    _startBounds = bounds;
  }

  void _updateResize(LockedResizeEdge edge, DragUpdateDetails details) {
    if (!widget.enabled) return;
    _dragDelta += details.delta;
    final Rect? startBounds = _startBounds;
    if (startBounds == null) return;
    _pendingBounds = LockedAspectResizeGeometry.targetBounds(
      startBounds: startBounds,
      designSize: widget.designSize,
      edge: edge,
      dragDelta: _dragDelta,
      minimumScale: widget.minimumScale,
      maximumScale: widget.maximumScale,
    );
    _scheduleBoundsWrite();
  }

  void _scheduleBoundsWrite() {
    if (_frameScheduled || _writeInFlight || _pendingBounds == null) return;
    _frameScheduled = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      unawaited(_flushBounds());
    });
  }

  Future<void> _flushBounds() async {
    if (!mounted ||
        !widget.enabled ||
        _writeInFlight ||
        _pendingBounds == null) {
      return;
    }
    _writeInFlight = true;
    final Rect target = _pendingBounds!;
    _pendingBounds = null;
    try {
      await windowManager.setBounds(target, animate: false);
    } finally {
      _writeInFlight = false;
      if (mounted && _pendingBounds != null) _scheduleBoundsWrite();
    }
  }

  void _endResize() {
    _dragSerial++;
    _startBounds = null;
    widget.onResizeEnd?.call();
  }

  @override
  void didUpdateWidget(covariant LockedAspectResizeArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _dragSerial++;
      _startBounds = null;
      _pendingBounds = null;
      _dragDelta = Offset.zero;
    }
  }

  Widget _edge({
    required LockedResizeEdge edge,
    required MouseCursor cursor,
    double? width,
    double? height,
  }) {
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => unawaited(_startResize(edge)),
        onPanUpdate: (details) => _updateResize(edge, details),
        onPanEnd: (_) => _endResize(),
        onPanCancel: _endResize,
        child: SizedBox(width: width, height: height),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double edgeSize = widget.edgeSize;
    return Stack(
      children: [
        widget.child,
        if (widget.enabled) ...[
          Positioned(
            left: 0,
            top: 0,
            width: edgeSize,
            height: edgeSize,
            child: _edge(
              edge: LockedResizeEdge.topLeft,
              cursor: SystemMouseCursors.resizeUpLeft,
            ),
          ),
          Positioned(
            left: edgeSize,
            right: edgeSize,
            top: 0,
            height: edgeSize,
            child: _edge(
              edge: LockedResizeEdge.top,
              cursor: SystemMouseCursors.resizeUp,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            width: edgeSize,
            height: edgeSize,
            child: _edge(
              edge: LockedResizeEdge.topRight,
              cursor: SystemMouseCursors.resizeUpRight,
            ),
          ),
          Positioned(
            left: 0,
            top: edgeSize,
            bottom: edgeSize,
            width: edgeSize,
            child: _edge(
              edge: LockedResizeEdge.left,
              cursor: SystemMouseCursors.resizeLeft,
            ),
          ),
          Positioned(
            right: 0,
            top: edgeSize,
            bottom: edgeSize,
            width: edgeSize,
            child: _edge(
              edge: LockedResizeEdge.right,
              cursor: SystemMouseCursors.resizeRight,
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            width: edgeSize,
            height: edgeSize,
            child: _edge(
              edge: LockedResizeEdge.bottomLeft,
              cursor: SystemMouseCursors.resizeDownLeft,
            ),
          ),
          Positioned(
            left: edgeSize,
            right: edgeSize,
            bottom: 0,
            height: edgeSize,
            child: _edge(
              edge: LockedResizeEdge.bottom,
              cursor: SystemMouseCursors.resizeDown,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            width: edgeSize,
            height: edgeSize,
            child: _edge(
              edge: LockedResizeEdge.bottomRight,
              cursor: SystemMouseCursors.resizeDownRight,
            ),
          ),
        ],
      ],
    );
  }
}
