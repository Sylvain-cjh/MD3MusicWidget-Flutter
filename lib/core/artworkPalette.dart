import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

Future<int> _materialSeed(Uint32List pixels) async {
  final result = await QuantizerCelebi().quantize(pixels, 128);
  final argb = result.colorToCount.map(
    (abgr, count) => MapEntry(
      (abgr & 0xff00ff00) | ((abgr & 0xff) << 16) | ((abgr >> 16) & 0xff),
      count,
    ),
  );
  return Score.score(argb, desired: 1).first;
}



final class ArtworkPalette {
  static const neutralSeed = Color(0xFF607D8B);
  final Color seed;
  final double whiteFraction;
  const ArtworkPalette(this.seed, this.whiteFraction);

  
  
  
  static Future<Color> materialSeedFromProvider(ImageProvider provider) async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final ready = Completer<ImageInfo>();
    var accepting = true;
    final listener = ImageStreamListener(
      (info, _) {
        if (!accepting || ready.isCompleted) {
          info.dispose();
        } else {
          ready.complete(info);
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    ImageInfo? info;
    ui.Picture? picture;
    ui.Image? sampled;
    try {
      info = await ready.future.timeout(const Duration(seconds: 5));
      final image = info.image;
      final scale = math.min(1.0, 112 / math.max(image.width, image.height));
      final width = image.width * scale, height = image.height * scale;
      final recorder = ui.PictureRecorder();
      paintImage(
        canvas: Canvas(recorder),
        rect: Rect.fromLTWH(0, 0, width, height),
        image: image,
        filterQuality: FilterQuality.none,
      );
      picture = recorder.endRecording();
      sampled = await picture.toImage(
        math.max(1, width.toInt()),
        math.max(1, height.toInt()),
      );
      final data = await sampled.toByteData();
      if (data == null) return neutralSeed;
      final pixels = data.buffer.asUint32List(
        data.offsetInBytes,
        data.lengthInBytes ~/ 4,
      );
      return Color(await compute(_materialSeed, pixels));
    } finally {
      accepting = false;
      stream.removeListener(listener);
      info?.dispose();
      sampled?.dispose();
      picture?.dispose();
      if (info == null) {
        unawaited(
          ready.future.then(
            (lateInfo) => lateInfo.dispose(),
            onError: (Object _) {},
          ),
        );
      }
    }
  }

  static ArtworkPalette fromRgba(ByteData rgba) {
    final buckets = <int, _ColorBucket>{};
    var opaque = 0, white = 0;
    for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4) {
      final alpha = rgba.getUint8(i + 3);
      if (alpha < 160) continue;
      opaque++;
      final r = (rgba.getUint8(i) * 255 / alpha).round().clamp(0, 255);
      final g = (rgba.getUint8(i + 1) * 255 / alpha).round().clamp(0, 255);
      final b = (rgba.getUint8(i + 2) * 255 / alpha).round().clamp(0, 255);
      final high = math.max(r, math.max(g, b));
      final low = math.min(r, math.min(g, b));
      if (low >= 222 && high - low <= 32) {
        white++;
        continue;
      }
      if (high <= 28) continue;
      final key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      final bucket = buckets.putIfAbsent(key, _ColorBucket.new);
      bucket.add(r, g, b);
    }
    Color selected = neutralSeed;
    double best = -1;
    final support = math.max(2, (opaque * 0.002).ceil());
    for (final bucket in buckets.values) {
      if (bucket.count < support) continue;
      final color = bucket.color;
      final hsv = HSVColor.fromColor(color);
      
      
      final score =
          math.sqrt(bucket.count) *
          (0.10 + hsv.saturation * hsv.saturation * 3) *
          (0.4 + (1 - (hsv.value - 0.58).abs()).clamp(0.0, 1.0));
      if (score > best && hsv.saturation >= 0.10) {
        best = score;
        selected = color;
      }
    }
    return ArtworkPalette(selected, opaque == 0 ? 0 : white / opaque);
  }

  static Future<ArtworkPalette> fromProvider(ImageProvider provider) async {
    final stream = ResizeImage.resizeIfNeeded(
      48,
      48,
      provider,
    ).resolve(ImageConfiguration.empty);
    final ready = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (ready.isCompleted) {
          info.dispose();
        } else {
          ready.complete(info);
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    ImageInfo? info;
    try {
      info = await ready.future;
      final data = await info.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return data == null
          ? const ArtworkPalette(neutralSeed, 0)
          : fromRgba(data);
    } finally {
      stream.removeListener(listener);
      info?.dispose();
    }
  }
}

final class _ColorBucket {
  int count = 0, red = 0, green = 0, blue = 0;
  void add(int r, int g, int b) {
    count++;
    red += r;
    green += g;
    blue += b;
  }

  Color get color => Color.fromARGB(
    255,
    (red / count).round(),
    (green / count).round(),
    (blue / count).round(),
  );
}
