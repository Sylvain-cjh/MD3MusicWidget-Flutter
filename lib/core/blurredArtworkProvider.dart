import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'artworkResources.dart';
import 'widgetDiagnostics.dart';



@immutable
class BlurredArtworkProvider extends ImageProvider<BlurredArtworkProvider> {
  final ImageProvider source;
  final String identity;
  final bool waterfall;
  final double headerHeight;
  final double pixelScale;
  final Size canvasSize;

  
  final Rect? rasterCrop;
  static int rasterizations = 0;
  const BlurredArtworkProvider({
    required this.source,
    required this.identity,
    required this.waterfall,
    required this.headerHeight,
    required this.pixelScale,
    this.canvasSize = const Size(700, 800),
    this.rasterCrop,
  });

  Size get rasterSize => Size(
    (canvasSize.width * pixelScale).ceilToDouble(),
    (canvasSize.height * pixelScale).ceilToDouble(),
  );

  static Rect? visibleRasterCrop(Rect placement, Size viewport, Size raster) {
    final visible = placement.intersect(Offset.zero & viewport);
    if (visible.isEmpty || !visible.isFinite || raster.isEmpty) return null;
    final scaleX = raster.width / placement.width;
    final scaleY = raster.height / placement.height;
    
    const guard = 4;
    final crop = Rect.fromLTRB(
      math
          .max(0, ((visible.left - placement.left) * scaleX).floor() - guard)
          .toDouble(),
      math
          .max(0, ((visible.top - placement.top) * scaleY).floor() - guard)
          .toDouble(),
      math.min(
        raster.width,
        (((visible.right - placement.left) * scaleX).ceil() + guard).toDouble(),
      ),
      math.min(
        raster.height,
        (((visible.bottom - placement.top) * scaleY).ceil() + guard).toDouble(),
      ),
    );
    return crop == (Offset.zero & raster) ? null : crop;
  }

  Rect? get normalizedRegion {
    final crop = rasterCrop;
    if (crop == null) return null;
    final size = rasterSize;
    return Rect.fromLTRB(
      crop.left / size.width,
      crop.top / size.height,
      crop.right / size.width,
      crop.bottom / size.height,
    );
  }

  @override
  Future<BlurredArtworkProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    BlurredArtworkProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
    CachedArtwork.trackVariant(source, this);
    final stream = source.resolve(
      ImageConfiguration(devicePixelRatio: pixelScale),
    );
    final ready = Completer<ui.Image>();
    var accepting = true;
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, sync) {
        if (accepting && !ready.isCompleted) ready.complete(info.image.clone());
        info.dispose();
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    ui.Image? original;
    try {
      original = await ready.future.timeout(const Duration(seconds: 5));
      final recorder = ui.PictureRecorder();
      final crop = rasterCrop ?? (Offset.zero & rasterSize);
      final canvas = Canvas(recorder)
        ..translate(-crop.left, -crop.top)
        ..scale(pixelScale);
      final bounds = Offset.zero & canvasSize;
      canvas.saveLayer(
        bounds,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 80,
            sigmaY: 80,
            tileMode: TileMode.clamp,
          ),
      );
      final input = Size(original.width.toDouble(), original.height.toDouble());
      final paint = Paint()..filterQuality = FilterQuality.medium;
      if (!waterfall) {
        final fitted = applyBoxFit(BoxFit.cover, input, canvasSize);
        canvas.drawImageRect(
          original,
          Alignment.center.inscribe(fitted.source, Offset.zero & input),
          bounds,
          paint,
        );
      } else {
        final header = Rect.fromLTWH(
          0,
          (canvasSize.height - headerHeight) / 2,
          canvasSize.width,
          headerHeight,
        );
        final fitted = applyBoxFit(BoxFit.cover, input, header.size);
        final crop = Alignment.topCenter.inscribe(
          fitted.source,
          Offset.zero & input,
        );
        final overlap = (headerHeight * .16).clamp(24.0, 48.0);
        final tail = Rect.fromLTRB(
          0,
          header.bottom - overlap,
          canvasSize.width,
          canvasSize.height,
        );
        final row = Rect.fromLTRB(
          crop.left,
          crop.bottom - crop.height / headerHeight,
          crop.right,
          crop.bottom,
        );
        canvas.drawImageRect(original, row, tail, paint);
        canvas.saveLayer(header, Paint());
        canvas.drawImageRect(original, crop, header, paint);
        canvas.drawRect(
          header,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xffffffff), Color(0xffffffff), Color(0x00ffffff)],
              stops: [0, .85, 1],
            ).createShader(header),
        );
        canvas.restore();
      }
      canvas.restore();
      final picture = recorder.endRecording();
      try {
        rasterizations++;
        return ImageInfo(
          image: await WidgetDiagnostics.measure(
            rasterCrop == null
                ? 'artwork.blurFullRaster'
                : 'artwork.blurVisibleRaster',
            () => picture.toImage(crop.width.toInt(), crop.height.toInt()),
          ),
        );
      } finally {
        picture.dispose();
      }
    } finally {
      accepting = false;
      stream.removeListener(listener);
      original?.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is BlurredArtworkProvider &&
      other.source == source &&
      other.identity == identity &&
      other.waterfall == waterfall &&
      other.headerHeight == headerHeight &&
      other.pixelScale == pixelScale &&
      other.canvasSize == canvasSize &&
      other.rasterCrop == rasterCrop;
  @override
  int get hashCode => Object.hash(
    source,
    identity,
    waterfall,
    headerHeight,
    pixelScale,
    canvasSize,
    rasterCrop,
  );
}
