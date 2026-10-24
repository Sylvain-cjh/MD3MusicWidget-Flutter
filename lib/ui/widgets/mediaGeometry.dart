import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';



RRect roundedMediaFragment(Rect rect, {required bool horizontal}) =>
    RRect.fromRectAndRadius(
      rect,
      Radius.elliptical(
        horizontal ? math.min(rect.width, rect.height) / 2 : rect.width / 2,
        horizontal ? rect.height / 2 : math.min(rect.height, rect.width) / 2,
      ),
    );

int spectrumDisplayCount(double width, int bands, double thickness) {
  if (width <= 0 || bands <= 0) return 0;
  final baseWidth = math.max(1.4, width / bands - 2);
  return (width / (baseWidth * thickness.clamp(0.35, 3.0) + 2)).round().clamp(
    1,
    128,
  );
}

({double width, double gap, double left}) spectrumBarLayout(
  double areaWidth,
  int bands,
  double thickness,
  int count,
) {
  if (areaWidth <= 0 || bands <= 0 || count <= 0) {
    return (width: 0, gap: 0, left: 0);
  }
  final preferred = math.max(1.4, areaWidth / bands - 2) * thickness;
  final width = math.min(preferred, areaWidth / count * 0.92);
  final gap = count == 1
      ? 0.0
      : math.max(0.0, math.min(2.0, (areaWidth - width * count) / (count - 1)));
  final used = width * count + gap * (count - 1);
  return (width: width, gap: gap, left: (areaWidth - used) / 2);
}

double displaySpectrumLevel(List<double> levels, int column, int count) {
  if (levels.isEmpty || count <= 0) return 0;
  double value(int i) => levels[i].isFinite ? levels[i].clamp(0.0, 1.0) : 0;
  if (count < levels.length) {
    final start = column * levels.length ~/ count;
    final end = (column + 1) * levels.length ~/ count;
    var energy = 0.0;
    for (var i = start; i < end; i++) {
      final level = value(i);
      energy += level * level;
    }
    return math.sqrt(energy / math.max(1, end - start));
  }
  final index = column / math.max(1, count - 1) * (levels.length - 1);
  final lower = index.floor(), upper = math.min(levels.length - 1, lower + 1);
  return value(lower) + (value(upper) - value(lower)) * (index - lower);
}



class SpectrumCurveBuffers {
  final Float64List smooth;
  final Float64List y = Float64List(64), tangent = Float64List(64);
  SpectrumCurveBuffers(int bands) : smooth = Float64List(bands);
}

Path smoothSpectrumPath(
  List<double> levels,
  Size size,
  double strokeWidth, {
  SpectrumCurveBuffers? buffers,
}) {
  final path = Path();
  if (levels.isEmpty || size.isEmpty) return path;
  final inset = strokeWidth / 2 + 0.5;
  final bounds = Rect.fromLTRB(
    inset,
    inset,
    math.max(inset, size.width - inset),
    math.max(inset, size.height - inset),
  );
  if (bounds.isEmpty) return path;
  double at(int index) {
    final value = levels[index.clamp(0, levels.length - 1)];
    return value.isFinite ? value.clamp(0.0, 1.0) : 0;
  }

  final scratch = buffers != null && buffers.smooth.length == levels.length
      ? buffers
      : SpectrumCurveBuffers(levels.length);
  final smooth = scratch.smooth;
  for (var i = 0; i < levels.length; i++) {
    smooth[i] =
        (at(i - 2) + at(i - 1) * 4 + at(i) * 6 + at(i + 1) * 4 + at(i + 2)) /
        16;
  }
  const count = 64;
  final y = scratch.y;
  for (var i = 0; i < count; i++) {
    final index = i / (count - 1) * (smooth.length - 1);
    final lower = index.floor(), upper = math.min(smooth.length - 1, lower + 1);
    final level =
        smooth[lower] + (smooth[upper] - smooth[lower]) * (index - lower);
    y[i] = bounds.bottom - bounds.height * level * 0.9;
  }
  final tangent = scratch.tangent;
  tangent.first = y[1] - y[0];
  tangent.last = y.last - y[count - 2];
  for (var i = 1; i < count - 1; i++) {
    final before = y[i] - y[i - 1], after = y[i + 1] - y[i];
    tangent[i] = before * after <= 0
        ? 0
        : 2 * before * after / (before + after);
  }
  double x(int i) => bounds.left + bounds.width * i / (count - 1);
  path.moveTo(x(0), y[0]);
  for (var i = 0; i < count - 1; i++) {
    final dx = (x(i + 1) - x(i)) / 3;
    path.cubicTo(
      x(i) + dx,
      y[i] + tangent[i] / 3,
      x(i + 1) - dx,
      y[i + 1] - tangent[i + 1] / 3,
      x(i + 1),
      y[i + 1],
    );
  }
  return path;
}
