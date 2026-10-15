import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';



@immutable
class BlurredArtworkProvider extends ImageProvider<BlurredArtworkProvider> {
  final ImageProvider source;
  final String identity;
  final bool waterfall;
  final double headerHeight;
  final double pixelScale;
  final Size canvasSize;
  static int rasterizations = 0;
  const BlurredArtworkProvider({
    required this.source,
    required this.identity,
    required this.waterfall,
    required this.headerHeight,
    required this.pixelScale,
    this.canvasSize = const Size(700, 800),
  });
  @override
  Future<BlurredArtworkProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
    BlurredArtworkProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load());

  Future<ImageInfo> _load() async {
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
      final canvas = Canvas(recorder)..scale(pixelScale);
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
          image: await picture.toImage(
            (canvasSize.width * pixelScale).ceil(),
            (canvasSize.height * pixelScale).ceil(),
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
      other.canvasSize == canvasSize;
  @override
  int get hashCode => Object.hash(
    source,
    identity,
    waterfall,
    headerHeight,
    pixelScale,
    canvasSize,
  );
}
