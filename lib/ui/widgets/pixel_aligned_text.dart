import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';



class PixelAlignedText extends SingleChildRenderObjectWidget {
  const PixelAlignedText({super.key, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      PixelAlignedTextRenderBox(MediaQuery.devicePixelRatioOf(context));
  @override
  void updateRenderObject(
    BuildContext context,
    covariant PixelAlignedTextRenderBox renderObject,
  ) {
    renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class PixelAlignedTextRenderBox extends RenderProxyBox {
  PixelAlignedTextRenderBox(double devicePixelRatio)
    : _devicePixelRatio = _validRatio(devicePixelRatio);
  static double _validRatio(double value) =>
      value.isFinite && value > 0 ? value : 1;
  double _devicePixelRatio;
  Offset _paintCorrection = Offset.zero;
  bool _alignmentDirty = true;
  set devicePixelRatio(double value) {
    value = _validRatio(value);
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    _alignmentDirty = true;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    super.performLayout();
    _alignmentDirty = true;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_alignmentDirty) {
      
      _paintCorrection = Offset.zero;
      final matrix = getTransformTo(null);
      final values = matrix.storage;
      if (values.every((value) => value.isFinite) &&
          values[0] > 0.000001 &&
          values[1].abs() < 0.000001 &&
          values[4].abs() < 0.000001 &&
          values[3].abs() < 0.000001 &&
          values[7].abs() < 0.000001 &&
          values[5] > 0.000001 &&
          (values[15] - 1).abs() < 0.000001) {
        final baseline = child?.getDistanceToBaseline(
          TextBaseline.alphabetic,
          onlyReal: true,
        );
        if (baseline != null) {
          final y = MatrixUtils.transformPoint(matrix, Offset(0, baseline)).dy;
          final correction =
              ((y * _devicePixelRatio).round() / _devicePixelRatio - y) /
              values[5];
          _paintCorrection = Offset(0, correction);
        }
        _alignmentDirty = false;
      }
    }
    super.paint(context, offset + _paintCorrection);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    transform.translateByDouble(0, _paintCorrection.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _paintCorrection,
        position: position,
        hitTest: (result, transformed) =>
            super.hitTestChildren(result, position: transformed),
      );
}
