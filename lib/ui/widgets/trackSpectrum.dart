part of 'trackControls.dart';

class MusicSpectrumPanel extends StatefulWidget {
  final SpectrumMode mode;
  final bool isPlaying;

  const MusicSpectrumPanel({
    super.key,
    required this.mode,
    required this.isPlaying,
  });

  @override
  State<MusicSpectrumPanel> createState() => _MusicSpectrumPanelState();
}

class _MusicSpectrumPanelState extends State<MusicSpectrumPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Float32List _displayLevels = Float32List(AppState.spectrumBandCount);
  final Float32List _startLevels = Float32List(AppState.spectrumBandCount);
  final Float32List _targetLevels = Float32List(AppState.spectrumBandCount);

  @override
  void initState() {
    super.initState();
    AppState.spectrumRevision.addListener(_handleSpectrumChanged);
    AppState.spectrumStyleRevision.addListener(_handleSpectrumStyleChanged);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    )..addListener(_updateDisplayLevels);
    _handleSpectrumChanged();
  }

  @override
  void didUpdateWidget(covariant MusicSpectrumPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.isPlaying != widget.isPlaying) {
      _handleSpectrumChanged();
    }
  }

  void _handleSpectrumChanged() {
    if (widget.mode == SpectrumMode.off) {
      _controller.stop();
      _displayLevels.fillRange(0, _displayLevels.length, 0.0);
      _startLevels.fillRange(0, _startLevels.length, 0.0);
      _targetLevels.fillRange(0, _targetLevels.length, 0.0);
      return;
    }

    for (int i = 0; i < _displayLevels.length; i++) {
      _startLevels[i] = _displayLevels[i];
      _targetLevels[i] = AppState.spectrumLevels[i];
    }
    _controller.forward(from: 0.0);
  }

  void _updateDisplayLevels() {
    final double progress = Curves.easeOutCubic.transform(_controller.value);
    for (int i = 0; i < _displayLevels.length; i++) {
      _displayLevels[i] =
          _startLevels[i] + (_targetLevels[i] - _startLevels[i]) * progress;
      if (_displayLevels[i] < 0.002) _displayLevels[i] = 0;
    }
  }

  void _handleSpectrumStyleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppState.spectrumRevision.removeListener(_handleSpectrumChanged);
    AppState.spectrumStyleRevision.removeListener(_handleSpectrumStyleChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = AppState.currentScheme;
    return SpectrumGlassSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SpectrumPainter(
                    mode: widget.mode,
                    levels: _displayLevels,
                    color: scheme.primary,
                    autoContrast: AppState.enableProgressAutoContrast,
                    thickness: AppState.spectrumThickness,
                    automaticColumns: AppState.automaticSpectrumColumns,
                    columnCount: AppState.spectrumColumnCount,
                    repaint: _controller,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  late final SpectrumCurveBuffers _curveBuffers = SpectrumCurveBuffers(
    levels.length,
  );
  final SpectrumMode mode;
  final Float32List levels;
  final Color color;
  final bool autoContrast;
  final double thickness;
  final bool automaticColumns;
  final int columnCount;

  _SpectrumPainter({
    required this.mode,
    required this.levels,
    required this.color,
    required this.autoContrast,
    required this.thickness,
    required this.automaticColumns,
    required this.columnCount,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.isEmpty) return;
    final int count = automaticColumns
        ? spectrumDisplayCount(size.width, levels.length, thickness)
        : columnCount.clamp(1, 128);
    bool hasSignal = false;
    for (final level in levels) {
      if (level > 0.005) {
        hasSignal = true;
        break;
      }
    }
    final Paint paint = Paint()
      ..color = (autoContrast ? Colors.white : color).withValues(
        alpha: hasSignal ? 0.82 : 0.26,
      )
      ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver
      ..isAntiAlias = true;
    final layout = spectrumBarLayout(
      size.width,
      levels.length,
      thickness,
      count,
    );
    final double barWidth = layout.width;

    if (mode == SpectrumMode.waveform) {
      if (!hasSignal) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * thickness
          ..strokeCap = StrokeCap.round;
        final inset = paint.strokeWidth / 2 + 0.5;
        final double baselineY = size.height - inset;
        canvas.drawLine(
          Offset(inset, baselineY),
          Offset(size.width - inset, baselineY),
          paint,
        );
        return;
      }
      final Path path = smoothSpectrumPath(
        levels,
        size,
        1.6 * thickness,
        buffers: _curveBuffers,
      );
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * thickness
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, paint);
      return;
    }

    paint.style = PaintingStyle.fill;
    for (int i = 0; i < count; i++) {
      final double x = layout.left + i * (barWidth + layout.gap);
      final double level = hasSignal
          ? displaySpectrumLevel(levels, i, count)
          : 0.075;
      if (hasSignal && level <= 0) continue;
      if (mode == SpectrumMode.mirror) {
        final double halfHeight = size.height * 0.46 * level;
        final double center = size.height / 2.0;
        canvas.drawRRect(
          roundedMediaFragment(
            Rect.fromLTWH(x, center - halfHeight - 0.5, barWidth, halfHeight),
            horizontal: false,
          ),
          paint,
        );
        canvas.drawRRect(
          roundedMediaFragment(
            Rect.fromLTWH(x, center + 0.5, barWidth, halfHeight),
            horizontal: false,
          ),
          paint,
        );
      } else {
        final double height = size.height * level;
        final Rect rect = Rect.fromLTWH(
          x,
          size.height - height,
          barWidth,
          height,
        );
        canvas.drawRRect(roundedMediaFragment(rect, horizontal: false), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.mode != mode ||
      oldDelegate.color != color ||
      oldDelegate.autoContrast != autoContrast ||
      oldDelegate.thickness != thickness ||
      oldDelegate.automaticColumns != automaticColumns ||
      oldDelegate.columnCount != columnCount;
}
