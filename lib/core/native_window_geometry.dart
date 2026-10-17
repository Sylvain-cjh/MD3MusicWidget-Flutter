import 'dart:ui';




abstract final class NativeWindowGeometry {
  static bool sameBounds(Rect a, Rect b, {required double pixelRatio}) {
    final ratio = pixelRatio.isFinite && pixelRatio > 0 ? pixelRatio : 1.0;
    int pixel(double value) =>
        (value * ratio + value.sign * .000001).truncate();
    return pixel(a.left) == pixel(b.left) &&
        pixel(a.top) == pixel(b.top) &&
        pixel(a.width) == pixel(b.width) &&
        pixel(a.height) == pixel(b.height);
  }
}
