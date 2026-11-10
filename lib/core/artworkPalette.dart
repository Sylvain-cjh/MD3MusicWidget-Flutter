import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'widgetDiagnostics.dart';



final class ArtworkPalette {
  static const fallbackSeed = Color(0xFF1B6EF3);
  static const sampleMaxSide = 128;
  final Color seed;
  final double whiteFraction;
  const ArtworkPalette(this.seed, this.whiteFraction);

  
  
  static Future<ArtworkPalette> fromRgba(ByteData rgba) async {
    final pixels = Uint32List(rgba.lengthInBytes ~/ 4);
    var opaque = 0, white = 0, count = 0;
    for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4) {
      if (rgba.getUint8(i + 3) < 160) continue;
      opaque++;
      final r = rgba.getUint8(i);
      final g = rgba.getUint8(i + 1);
      final b = rgba.getUint8(i + 2);
      final high = math.max(r, math.max(g, b));
      final low = math.min(r, math.min(g, b));
      if (low >= 222 && high - low <= 32) {
        white++;
        continue;
      }
      if (high <= 28) continue;
      pixels[count++] = 0xff000000 | (r << 16) | (g << 8) | b;
    }
    final whiteFraction = opaque == 0 ? 0.0 : white / opaque;
    
    final minimumSupport = math.max(2, (opaque * .002).ceil());
    if (count < minimumSupport) {
      return ArtworkPalette(fallbackSeed, whiteFraction);
    }
    final result = await QuantizerCelebi().quantize(
      Uint32List.sublistView(pixels, 0, count),
      128,
    );
    final supported = Map<int, int>.of(result.colorToCount)
      ..removeWhere((_, population) => population < minimumSupport);
    final seed = Score.score(
      supported,
      desired: 1,
      fallbackColorARGB: fallbackSeed.toARGB32(),
    ).first;
    return ArtworkPalette(Color(seed), whiteFraction);
  }

  static Future<ArtworkPalette> fromProvider(ImageProvider provider) async {
    WidgetDiagnostics.count('paletteSamples');
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
    ui.Image? sample;
    ByteData? data;
    try {
      info = await ready.future.timeout(const Duration(seconds: 5));
      final source = info.image;
      final maxSide = math.max(source.width, source.height);
      if (maxSide > sampleMaxSide) {
        final scale = sampleMaxSide / maxSide;
        final width = math.max(1, (source.width * scale).round());
        final height = math.max(1, (source.height * scale).round());
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawImageRect(
          source,
          Rect.fromLTWH(
            0,
            0,
            source.width.toDouble(),
            source.height.toDouble(),
          ),
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint()..filterQuality = FilterQuality.low,
        );
        picture = recorder.endRecording();
        sample = await picture.toImage(width, height);
      }
      data = await (sample ?? source).toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
    } finally {
      accepting = false;
      stream.removeListener(listener);
      sample?.dispose();
      picture?.dispose();
      info?.dispose();
      if (info == null) {
        unawaited(
          ready.future.then(
            (lateInfo) => lateInfo.dispose(),
            onError: (Object _) {},
          ),
        );
      }
    }
    final rgba = data;
    if (rgba == null) return const ArtworkPalette(fallbackSeed, 0);
    WidgetDiagnostics.count('materialQuantizations');
    return WidgetDiagnostics.measure(
      'artwork.materialSeed',
      () => compute(fromRgba, rgba, debugLabel: 'artwork.monet'),
    );
  }
}
