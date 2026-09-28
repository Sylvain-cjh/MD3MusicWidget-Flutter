import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/system_performance_provider.dart';
import '../../core/app_state.dart';
import 'spectrum_glass_surface.dart';

class PerformanceMonitorPanel extends StatefulWidget {
  final Future<SystemPerformanceSample?> Function() readSample;

  const PerformanceMonitorPanel({
    super.key,
    this.readSample = SystemPerformanceProvider.sample,
  });

  @override
  State<PerformanceMonitorPanel> createState() =>
      _PerformanceMonitorPanelState();
}

class _PerformanceMonitorPanelState extends State<PerformanceMonitorPanel> {
  final SystemPerformanceTracker _tracker = SystemPerformanceTracker();
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  bool _sampling = false;
  SystemPerformanceReading? _reading;

  @override
  void initState() {
    super.initState();
    _clock.start();
    unawaited(_sample());
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_sample()),
    );
  }

  Future<void> _sample() async {
    if (_sampling) return;
    _sampling = true;
    try {
      final sample = await widget.readSample();
      if (!mounted) return;
      if (sample == null) {
        setState(() => _reading = null);
        return;
      }
      _clock.stop();
      final reading = _tracker.update(sample, elapsed: _clock.elapsed);
      _clock
        ..reset()
        ..start();
      setState(() => _reading = reading);
    } catch (_) {
      if (mounted) setState(() => _reading = null);
    } finally {
      _sampling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppState.currentScheme;
    final reading = _reading;
    final fps = reading?.desktopFramesPerSecond;
    final cpu = reading?.cpuPercent;
    return IgnorePointer(
      child: RepaintBoundary(
        child: SpectrumGlassSurface(
          key: const ValueKey('system_performance_panel'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: DefaultTextStyle(
              style: TextStyle(
                fontSize: 10,
                height: 1.3,
                color: colors.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '桌面 ${fps == null
                              ? '—'
                              : fps < 1
                              ? '静止'
                              : '${fps.toStringAsFixed(0)} FPS'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'CPU ${cpu == null ? '—' : '${cpu.toStringAsFixed(0)}%'}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reading == null
                        ? '内存 —'
                        : '内存 ${reading.usedMemoryGiB.toStringAsFixed(1)} / ${reading.totalMemoryGiB.toStringAsFixed(1)} GiB',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant),
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
