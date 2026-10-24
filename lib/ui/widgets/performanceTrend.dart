import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/systemPerformanceProvider.dart';

class PerformanceTrend extends StatelessWidget {
  final PerformanceMetric metric;
  final List<double?> samples;
  final Color color;
  const PerformanceTrend({
    super.key,
    required this.metric,
    required this.samples,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      key: ValueKey('performance_trend_${metric.name}'),
      painter: PerformanceTrendPainter(
        metric: metric,
        samples: samples,
        color: color,
      ),
      size: Size.infinite,
    ),
  );
}

class PerformanceTrendPainter extends CustomPainter {
  final PerformanceMetric metric;
  final List<double?> samples;
  final Color color;
  PerformanceTrendPainter({
    required this.metric,
    required this.samples,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final bounds = Rect.fromLTWH(
      1,
      2,
      math.max(0, size.width - 2),
      math.max(0, size.height - 4),
    );
    if (bounds.isEmpty) return;
    canvas.drawLine(
      bounds.bottomLeft,
      bounds.bottomRight,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..strokeWidth = 1,
    );
    var ceiling = 100.0;
    if (metric == PerformanceMetric.fps) {
      final peak = samples
          .whereType<double>()
          .where((v) => v.isFinite)
          .fold(60.0, math.max);
      ceiling = math.max(60, (peak / 60).ceil() * 60).toDouble();
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final points = <Offset>[];
    void drawSegment() {
      if (points.isEmpty) return;
      if (points.length == 1) {
        canvas.drawCircle(points.first, 1, Paint()..color = color);
      } else {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (var i = 1; i < points.length - 1; i++) {
          final midpoint = (points[i] + points[i + 1]) / 2;
          path.quadraticBezierTo(
            points[i].dx,
            points[i].dy,
            midpoint.dx,
            midpoint.dy,
          );
        }
        path.lineTo(points.last.dx, points.last.dy);
        canvas.drawPath(path, line);
      }
      points.clear();
    }

    
    
    final first = samples.indexWhere((v) => v != null && v.isFinite);
    if (first < 0) return;
    final intervals = math.max(1, samples.length - 1 - first);
    for (var i = first; i < samples.length; i++) {
      final value = samples[i];
      if (value == null || !value.isFinite) {
        drawSegment();
        continue;
      }
      points.add(
        Offset(
          bounds.left + bounds.width * (i - first) / intervals,
          bounds.bottom - bounds.height * (value / ceiling).clamp(0.0, 1.0),
        ),
      );
    }
    drawSegment();
  }

  @override
  bool shouldRepaint(covariant PerformanceTrendPainter old) =>
      old.metric != metric || old.color != color || old.samples != samples;
}
