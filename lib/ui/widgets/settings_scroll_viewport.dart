import 'dart:math' as math;

import 'package:flutter/material.dart';



class SettingsScrollViewport extends StatefulWidget {
  final Widget child;
  final double radius;
  final double fadeExtent;

  const SettingsScrollViewport({
    super.key,
    required this.child,
    this.radius = 24,
    this.fadeExtent = 28,
  });

  @override
  State<SettingsScrollViewport> createState() => _SettingsScrollViewportState();
}

class _SettingsScrollViewportState extends State<SettingsScrollViewport> {
  final _edges = ValueNotifier<(double, double)>((0, 0));

  void _update(ScrollMetrics metrics) {
    final extent = math.min(widget.fadeExtent, metrics.viewportDimension / 4);
    final top = math.min(extent, metrics.extentBefore).clamp(0.0, extent);
    final bottom = math.min(extent, metrics.extentAfter).clamp(0.0, extent);
    final current = _edges.value;
    
    if ((current.$1 - top).abs() > 0.25 ||
        (current.$2 - bottom).abs() > 0.25 ||
        (top == 0 && current.$1 != 0) ||
        (bottom == 0 && current.$2 != 0)) {
      _edges.value = (top, bottom);
    }
  }

  @override
  void dispose() {
    _edges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (event) {
          if (event.depth == 0) _update(event.metrics);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (event) {
            if (event.depth == 0) _update(event.metrics);
            return false;
          },
          child: ClipRRect(
            key: const ValueKey('settings_scroll_clip'),
            borderRadius: BorderRadius.circular(widget.radius),
            child: ValueListenableBuilder<(double, double)>(
              valueListenable: _edges,
              child: widget.child,
              builder: (context, edges, child) => ShaderMask(
                key: const ValueKey('settings_scroll_fade'),
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) {
                  final h = math.max(1.0, bounds.height);
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      edges.$1 > 0 ? Colors.transparent : Colors.white,
                      Colors.white,
                      Colors.white,
                      edges.$2 > 0 ? Colors.transparent : Colors.white,
                    ],
                    stops: [0, edges.$1 / h, 1 - edges.$2 / h, 1],
                  ).createShader(bounds);
                },
                child: child,
              ),
            ),
          ),
        ),
      );
}
