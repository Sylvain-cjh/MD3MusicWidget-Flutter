import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/system_performance_provider.dart';
import '../../core/app_state.dart';
import 'spectrum_glass_surface.dart';

class PerformanceMonitorPanel extends StatefulWidget {
  final Future<SystemPerformanceSample?> Function() readSample;
  final bool isVertical;

  const PerformanceMonitorPanel({
    super.key,
    this.readSample = SystemPerformanceProvider.sample,
    this.isVertical = false,
  });

  @override
  State<PerformanceMonitorPanel> createState() =>
      _PerformanceMonitorPanelState();
}

class _PerformanceMonitorPanelState extends State<PerformanceMonitorPanel> {
  final SystemPerformanceTracker _tracker = SystemPerformanceTracker();
  Timer? _timer;
  bool _sampling = false;
  SystemPerformanceReading? _reading;

  @override
  void initState() {
    super.initState();
    AppState.performanceRevision.addListener(_configure);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _configure();
    });
    unawaited(_sample());
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_sample()),
    );
  }

  void _configure() {
    if (mounted) setState(() => _reading = null);
    unawaited(
      SystemPerformanceProvider.configure(
        enabled: true,
        executable: AppState.performanceProcessExecutable,
      ),
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
      final reading = _tracker.update(sample);
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
    AppState.performanceRevision.removeListener(_configure);
    unawaited(
      SystemPerformanceProvider.configure(enabled: false, executable: ''),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppState.currentScheme;
    final reading = _reading;
    final fps = reading?.framesPerSecond;
    final cpu = reading?.cpuPercent;
    final gpu = reading?.gpuPercent;
    final memoryText = reading == null
        ? '内存 —'
        : widget.isVertical
        ? '内存 ${reading.usedMemoryGiB.toStringAsFixed(1)}G'
        : '内存 ${reading.usedMemoryGiB.toStringAsFixed(1)}/${reading.totalMemoryGiB.toStringAsFixed(0)}G';
    return IgnorePointer(
      child: RepaintBoundary(
        child: SpectrumGlassSurface(
          key: const ValueKey('system_performance_panel'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: DefaultTextStyle(
              style:
                  (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
                      .copyWith(
                        fontSize: 10,
                        height: 1.3,
                        color: colors.onSurface,
                        fontFamily:
                            AppState.currentFontFamily == 'System Default'
                            ? null
                            : AppState.currentFontFamily,
                        fontFamilyFallback: AppState.textFontFallback,
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
                          'FPS ${fps == null ? '—' : fps.toStringAsFixed(0)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'CPU ${cpu == null ? '—' : '${cpu.toStringAsFixed(0)}%'}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'GPU ${gpu == null ? '—' : '${gpu.toStringAsFixed(0)}%'}',
                        maxLines: 1,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          memoryText,
                          maxLines: 1,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
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
