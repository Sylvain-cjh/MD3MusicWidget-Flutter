import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../core/widgetDiagnostics.dart';



final class WindowPaintProbe extends SingleChildRenderObjectWidget {
  const WindowPaintProbe({super.key, required super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderWindowPaintProbe();
}

final class _RenderWindowPaintProbe extends RenderProxyBox {
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!WidgetDiagnostics.enabled ||
        WidgetDiagnostics.windowPaints.length >= 20000) {
      return;
    }
    final origin = localToGlobal(Offset.zero);
    if (!origin.isFinite) return;
    WidgetDiagnostics.windowPaints.add({
      'wallUs': DateTime.now().microsecondsSinceEpoch,
      'frameNumber': ui.PlatformDispatcher.instance.frameData.frameNumber,
      'x': origin.dx,
      'y': origin.dy,
      'width': size.width,
      'height': size.height,
    });
  }
}
