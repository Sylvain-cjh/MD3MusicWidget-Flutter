import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/system_performance_provider.dart';
import '../../core/performance_history.dart';
import '../../core/app_state.dart';
import 'spectrum_glass_surface.dart';
import 'pixel_aligned_text.dart';
import 'performance_trend.dart';

class PerformanceMonitorPanel extends StatefulWidget {
  final Future<SystemPerformanceSample?> Function() readSample;
  final bool isVertical;
  final bool active;
  final int? metricsMask;

  const PerformanceMonitorPanel({
    super.key,
    this.readSample = SystemPerformanceProvider.sample,
    this.isVertical = false,
    this.active = true,
    this.metricsMask,
  });

  @override
  State<PerformanceMonitorPanel> createState() =>
      _PerformanceMonitorPanelState();
}

class _PerformanceMonitorPanelState extends State<PerformanceMonitorPanel> {
  final SystemPerformanceTracker _tracker = SystemPerformanceTracker();
  final PerformanceHistory _history = PerformanceHistory();
  Timer? _timer;
  bool _sampling = false;
  SystemPerformanceReading? _reading;
  int? _configuredMask;
  String? _configuredExecutable;
  bool? _configuredActive;
  int _generation = 0;
  int get _mask =>
      (widget.metricsMask ?? AppState.performanceMetricsMask) &
      PerformanceMetric.allMask;

  @override
  void didUpdateWidget(covariant PerformanceMonitorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.metricsMask != widget.metricsMask) {
      _configure();
    }
  }

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
    final mask = _mask;
    final executable = AppState.performanceProcessExecutable;
    if (_configuredMask == mask &&
        _configuredExecutable == executable &&
        _configuredActive == widget.active) {
      return;
    }
    if (_configuredMask != null) {
      ++_generation;
      for (final metric in PerformanceMetric.values) {
        if (metric.enabledIn(mask) && !metric.enabledIn(_configuredMask!)) {
          _history.clearMetric(metric);
        }
      }
      if (executable != _configuredExecutable) {
        _history.clearMetric(PerformanceMetric.fps);
        final reading = _reading;
        if (reading != null) {
          _reading = SystemPerformanceReading(
            cpuPercent: reading.cpuPercent,
            framesPerSecond: null,
            gpuPercent: reading.gpuPercent,
            usedMemoryGiB: reading.usedMemoryGiB,
            totalMemoryGiB: reading.totalMemoryGiB,
          );
        }
      }
    }
    _configuredMask = mask;
    _configuredExecutable = executable;
    _configuredActive = widget.active;
    if (mounted) setState(() {});
    unawaited(
      SystemPerformanceProvider.configure(
        enabled: widget.active && mask != 0,
        executable: executable,
        metricsMask: mask,
      ),
    );
  }

  Future<void> _sample() async {
    if (_sampling || !widget.active || _mask == 0) return;
    _sampling = true;
    final generation = _generation;
    try {
      final sample = await widget.readSample();
      if (!mounted || generation != _generation) return;
      if (sample == null) {
        _history.add(null, _mask);
        setState(() => _reading = null);
        return;
      }
      final reading = _tracker.update(sample);
      _history.add(reading, _mask);
      setState(
        () => _reading = SystemPerformanceReading(
          cpuPercent: reading.cpuPercent ?? _reading?.cpuPercent,
          framesPerSecond: reading.framesPerSecond,
          gpuPercent: reading.gpuPercent,
          usedMemoryGiB: reading.usedMemoryGiB,
          totalMemoryGiB: reading.totalMemoryGiB,
        ),
      );
    } catch (_) {
      if (mounted && generation == _generation) {
        _history.add(null, _mask);
        setState(() => _reading = null);
      }
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
    final metrics = [
      for (final metric in PerformanceMetric.values)
        if (metric.enabledIn(_mask)) metric,
    ];
    final reading = _reading;
    final memoryText = reading == null
        ? '内存 —'
        : widget.isVertical || metrics.length == 2
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
                        fontSize: 11,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        fontVariations: AppState.variationsFor(
                          500,
                          fontSize: 11,
                        ),
                        color: colors.onSurface,
                        fontFamily: AppState.effectiveGlobalFontFamily,
                        fontFamilyFallback: AppState.textFontFallback,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: metrics.length <= 2
                    ? _buildTrends(metrics, memoryText)
                    : Column(
                        key: ValueKey('performance_values_$_mask'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _valueRow(metrics.take(2).toList(), memoryText),
                          const SizedBox(height: 2),
                          _valueRow(metrics.skip(2).toList(), memoryText),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _text(PerformanceMetric metric, String memoryText) {
    final r = _reading;
    String percent(double? value) =>
        value == null ? '—' : '${value.toStringAsFixed(0)}%';
    return switch (metric) {
      PerformanceMetric.fps =>
        'FPS ${r?.framesPerSecond?.toStringAsFixed(0) ?? '—'}',
      PerformanceMetric.cpu => 'CPU ${percent(r?.cpuPercent)}',
      PerformanceMetric.gpu => 'GPU ${percent(r?.gpuPercent)}',
      PerformanceMetric.memory => memoryText,
    };
  }

  Widget _label(
    PerformanceMetric metric,
    String memoryText, {
    TextAlign? align,
  }) => PixelAlignedText(
    child: Text(
      _text(metric, memoryText),
      maxLines: 1,
      textHeightBehavior: AppState.crispTextHeightBehavior,
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: metric == PerformanceMetric.memory
          ? TextStyle(color: AppState.currentScheme.onSurfaceVariant)
          : null,
    ),
  );

  Widget _valueRow(List<PerformanceMetric> metrics, String memoryText) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    if (metrics.length == 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _label(metrics.first, memoryText),
      );
    }
    final memoryLast = metrics.last == PerformanceMetric.memory;
    return Row(
      children: [
        if (memoryLast)
          _label(metrics.first, memoryText)
        else
          Expanded(child: _label(metrics.first, memoryText)),
        const SizedBox(width: 4),
        if (memoryLast)
          Expanded(
            child: _label(metrics.last, memoryText, align: TextAlign.end),
          )
        else
          _label(metrics.last, memoryText),
      ],
    );
  }

  Widget _buildTrends(List<PerformanceMetric> metrics, String memoryText) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    Widget trend(PerformanceMetric metric) => PerformanceTrend(
      metric: metric,
      samples: _history.values(metric),
      color: switch (metric) {
        PerformanceMetric.fps ||
        PerformanceMetric.cpu => AppState.currentScheme.primary,
        PerformanceMetric.gpu => AppState.currentScheme.secondary,
        PerformanceMetric.memory => AppState.currentScheme.tertiary,
      },
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style;
        final measure = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        var labelWidth = 0.0;
        for (final metric in metrics) {
          final reserved = switch (metric) {
            PerformanceMetric.cpu => 'CPU 100%',
            PerformanceMetric.gpu => 'GPU 100%',
            PerformanceMetric.fps => 'FPS 9999',
            PerformanceMetric.memory => '内存 999.9G',
          };
          for (final text in [_text(metric, memoryText), reserved]) {
            measure.text = TextSpan(text: text, style: style);
            measure.layout();
            labelWidth = math.max(labelWidth, measure.width.ceilToDouble());
          }
        }
        measure.dispose();
        labelWidth = math.min(labelWidth, constraints.maxWidth * .5);
        return Column(
          key: ValueKey('performance_trends_$_mask'),
          children: [
            if (metrics.length == 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: _label(metrics.single, memoryText),
              ),
              const SizedBox(height: 1),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: trend(metrics.single),
                ),
              ),
            ] else ...[
              for (final metric in metrics)
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: labelWidth,
                        child: _label(metric, memoryText),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: trend(metric)),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
