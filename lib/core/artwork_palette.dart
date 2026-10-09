import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';



final class ArtworkPalette {
  static const neutralSeed = Color(0xFF607D8B);
  final Color seed;
  final double whiteFraction;
  const ArtworkPalette(this.seed, this.whiteFraction);

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
