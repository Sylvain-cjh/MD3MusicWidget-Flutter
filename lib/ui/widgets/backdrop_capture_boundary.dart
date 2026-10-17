import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';



class BackdropCaptureBoundary extends SingleChildRenderObjectWidget {
  const BackdropCaptureBoundary({super.key, required super.child});

  @override
  RenderBackdropCaptureBoundary createRenderObject(BuildContext context) =>
      RenderBackdropCaptureBoundary();
}

class RenderBackdropCaptureBoundary extends RenderRepaintBoundary {
  Future<ui.Image> capture(Rect bounds, {required double pixelRatio}) {
    assert(!debugNeedsPaint);
    return (layer! as OffsetLayer).toImage(bounds, pixelRatio: pixelRatio);
  }
}
