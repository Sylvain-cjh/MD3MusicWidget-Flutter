import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'artworkResources.dart';
import 'widgetDiagnostics.dart';


const waterfallColorBand = 0.50;


const waterfallFadeStop = 0.42;


const waterfallOverlapFraction = 0.22;



const ambientSaturation = 1.10;
const ambientContrast = 0.90;
const ambientOverscale = 1.06;

List<double> ambientGradeMatrix({
  double saturation = ambientSaturation,
  double contrast = ambientContrast,
}) {
  const weights = <double>[0.2126, 0.7152, 0.0722];
  final inv = 1 - saturation;
  final lift = (1 - contrast) / 2 * 255;
  final matrix = <double>[];
  for (var row = 0; row < 3; row++) {
    for (var column = 0; column < 3; column++) {
      final saturated =
          inv * weights[column] + (row == column ? ambientSaturation : 0);
      matrix.add(ambientContrast * saturated);
    }
    matrix
      ..add(0)
      ..add(lift);
  }
  matrix.addAll(const <double>[0, 0, 0, 1, 0]);
  return matrix;
}



@immutable
class BlurredArtworkProvider extends ImageProvider<BlurredArtworkProvider> {
  final ImageProvider source;
  final String identity;
  final bool waterfall;

  
  final bool ambient;
  final double blurSigma;
  final double colorBand;
  final double fadeStop;
  final double overlapFraction;
  final double gradeSaturation;
  final double gradeContrast;
  final double gradeScale;
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
    this.ambient = false,
    this.blurSigma = 80,
    this.colorBand = waterfallColorBand,
    this.fadeStop = waterfallFadeStop,
    this.overlapFraction = waterfallOverlapFraction,
    this.gradeSaturation = ambientSaturation,
    this.gradeContrast = ambientContrast,
    this.gradeScale = ambientOverscale,
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
            sigmaX: blurSigma,
            sigmaY: blurSigma,
            tileMode: TileMode.clamp,
          ),
      );
      final input = Size(original.width.toDouble(), original.height.toDouble());
      final paint = Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ambient
            ? ColorFilter.matrix(
                ambientGradeMatrix(
                  saturation: gradeSaturation,
                  contrast: gradeContrast,
                ),
              )
            : null;
      if (!waterfall) {
        final fitted = applyBoxFit(BoxFit.cover, input, canvasSize);
        final sourceRect = Alignment.center.inscribe(
          fitted.source,
          Offset.zero & input,
        );
        if (!ambient) {
          canvas.drawImageRect(original, sourceRect, bounds, paint);
        } else {
          final center = bounds.center;
          canvas
            ..save()
            ..clipRect(bounds)
            ..translate(center.dx, center.dy)
            ..scale(gradeScale)
            ..translate(-center.dx, -center.dy)
            ..drawImageRect(original, sourceRect, bounds, paint)
            ..restore();
        }
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
        final requested = headerHeight * overlapFraction;
        final overlap =
            (overlapFraction - waterfallOverlapFraction).abs() < 0.0001
            ? requested.clamp(32.0, 56.0)
            : requested.clamp(12.0, math.max(12.0, headerHeight * 0.6));
        final tail = Rect.fromLTRB(
          0,
          header.bottom - overlap,
          canvasSize.width,
          canvasSize.height,
        );
        
        
        final bandHeight = math.min(
          crop.height,
          math.max(crop.height * colorBand, 1),
        );
        final band = Rect.fromLTRB(
          crop.left,
          math.max(crop.top, crop.bottom - bandHeight),
          crop.right,
          crop.bottom,
        );
        canvas.drawImageRect(original, band, tail, paint);
        canvas.saveLayer(header, Paint());
        canvas.drawImageRect(original, crop, header, paint);
        canvas.drawRect(
          header,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Color(0xffffffff),
                Color(0xffffffff),
                Color(0x00ffffff),
              ],
              stops: [0, fadeStop, 1],
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
      other.ambient == ambient &&
      other.blurSigma == blurSigma &&
      other.colorBand == colorBand &&
      other.fadeStop == fadeStop &&
      other.overlapFraction == overlapFraction &&
      other.gradeSaturation == gradeSaturation &&
      other.gradeContrast == gradeContrast &&
      other.gradeScale == gradeScale &&
      other.headerHeight == headerHeight &&
      other.pixelScale == pixelScale &&
      other.canvasSize == canvasSize &&
      other.rasterCrop == rasterCrop;
  @override
  int get hashCode => Object.hash(
    source,
    identity,
    waterfall,
    ambient,
    blurSigma,
    colorBand,
    fadeStop,
    overlapFraction,
    gradeSaturation,
    gradeContrast,
    gradeScale,
    headerHeight,
    pixelScale,
    canvasSize,
    rasterCrop,
  );
}
