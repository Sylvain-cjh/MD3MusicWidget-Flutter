import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import 'performance_monitor_panel.dart';
import 'track_controls.dart';

class SpectrumPerformanceRow extends StatefulWidget {
  final SpectrumMode spectrumMode;
  final bool isPlaying;
  final bool showPerformance;
  final bool isVertical;

  const SpectrumPerformanceRow({
    super.key,
    required this.spectrumMode,
    required this.isPlaying,
    required this.showPerformance,
    this.isVertical = false,
  });

  @override
  State<SpectrumPerformanceRow> createState() => _SpectrumPerformanceRowState();
}

class _SpectrumPerformanceRowState extends State<SpectrumPerformanceRow>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 250);
  late final AnimationController _progress;
  bool _initialized = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: _duration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_initialized) {
      _initialized = true;
      if (widget.showPerformance) {
        if (_reduceMotion) {
          _progress.value = 1;
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _moveToTarget();
          });
        }
      }
    } else if (_reduceMotion) {
      _progress.value = widget.showPerformance ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant SpectrumPerformanceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showPerformance != widget.showPerformance) {
      _moveToTarget();
    }
  }

  void _moveToTarget() {
    final target = widget.showPerformance ? 1.0 : 0.0;
    if (_reduceMotion) {
      _progress.value = target;
      return;
    }
    final milliseconds =
        (_duration.inMilliseconds * (target - _progress.value).abs()).round();
    if (milliseconds == 0) {
      _progress.value = target;
      return;
    }
    unawaited(
      _progress.animateTo(
        target,
        duration: Duration(milliseconds: milliseconds),
        curve: AppState.layoutSwitchCurve,
      ),
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spectrumVisible = widget.spectrumMode != SpectrumMode.off;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const gap = 8.0;
        final halfWidth = (width - gap) / 2;
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            final value = _progress.value;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (spectrumVisible)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: width - (halfWidth + gap) * value,
                    child: RepaintBoundary(
                      child: MusicSpectrumPanel(
                        mode: widget.spectrumMode,
                        isPlaying: widget.isPlaying,
                      ),
                    ),
                  ),
                if (widget.showPerformance || value > 0)
                  Positioned(
                    key: const ValueKey('performance_slide'),
                    left: spectrumVisible
                        ? width - halfWidth * value
                        : width * (1 - value),
                    top: 0,
                    bottom: 0,
                    width: spectrumVisible ? halfWidth : width,
                    child: PerformanceMonitorPanel(
                      isVertical: widget.isVertical,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
