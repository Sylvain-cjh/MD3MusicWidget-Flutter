import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';



typedef ClientViewportPixels = ({Size size, Offset inset});

final class NativeClientViewport extends ValueNotifier<ClientViewportPixels?> {
  NativeClientViewport() : super(null);

  static const _channel = MethodChannel('md3_music_widget/client_viewport');
  int _revision = 0;

  Future<void> start() async {
    final revision = _revision;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'changed') return;
      _revision++;
      _apply(call.arguments);
    });
    try {
      final initial = await _channel.invokeMethod<List<Object?>>('watch');
      if (revision == _revision) _apply(initial);
    } on MissingPluginException {
      
      _channel.setMethodCallHandler(null);
    }
  }

  void _apply(Object? pixels) {
    if (pixels is! List || (pixels.length != 2 && pixels.length != 4)) return;
    final w = pixels[0], h = pixels[1];
    final x = pixels.length == 4 ? pixels[2] : 0;
    final y = pixels.length == 4 ? pixels[3] : 0;
    if (w is int &&
        h is int &&
        x is int &&
        y is int &&
        w > 0 &&
        h > 0 &&
        x >= 0 &&
        y >= 0) {
      value = (
        size: Size(w.toDouble(), h.toDouble()),
        inset: Offset(x.toDouble(), y.toDouble()),
      );
    }
  }
}

class ClientViewportProjection extends StatelessWidget {
  const ClientViewportProjection({
    super.key,
    required this.viewport,
    required this.child,
  });

  final ValueListenable<ClientViewportPixels?> viewport;
  final Widget child;

  static Offset originOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ViewportOrigin>()?.inset ??
      Offset.zero;

  @override
  Widget build(BuildContext context) {
    final surface = MediaQuery.of(context);
    return ValueListenableBuilder<ClientViewportPixels?>(
      valueListenable: viewport,
      child: child,
      builder: (context, physical, child) {
        final dpr = surface.devicePixelRatio;
        final inset = physical == null
            ? Offset.zero
            : Offset(
                math.min(surface.size.width, physical.inset.dx / dpr),
                math.min(surface.size.height, physical.inset.dy / dpr),
              );
        final visible = physical == null
            ? surface.size
            : Size(
                math.min(
                  surface.size.width - inset.dx,
                  physical.size.width / dpr,
                ),
                math.min(
                  surface.size.height - inset.dy,
                  physical.size.height / dpr,
                ),
              );
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: inset.dx, top: inset.dy),
            child: SizedBox.fromSize(
              size: visible,
              child: ClipRect(
                child: _ViewportOrigin(
                  inset: inset,
                  child: MediaQuery(
                    data: surface.copyWith(size: visible),
                    child: child!,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _ViewportOrigin extends InheritedWidget {
  const _ViewportOrigin({required this.inset, required super.child});
  final Offset inset;

  @override
  bool updateShouldNotify(_ViewportOrigin oldWidget) =>
      inset != oldWidget.inset;
}
