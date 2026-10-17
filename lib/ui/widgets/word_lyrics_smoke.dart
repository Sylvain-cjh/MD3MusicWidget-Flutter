import 'dart:ui' as ui;

import 'package:flutter/painting.dart';



final class WordLyricsSmoke {
  static Future<ui.FragmentProgram?>? _program;
  static Future<ui.FragmentProgram?> program() => _program ??= _load();
  static Future<ui.FragmentProgram?> _load() async {
    try {
      return await ui.FragmentProgram.fromAsset('shaders/lyrics_smoke.frag');
    } catch (_) {
      return null; 
    }
  }

  final ui.Image _image;
  final Size size;
  final List<List<(Rect, ui.FragmentShader)>> _patches;
  final Paint _paint = Paint();
  bool _disposed = false;
  int get approximateBytes => _image.width * _image.height * 4;

  WordLyricsSmoke._(this._image, this.size, this._patches);

  static WordLyricsSmoke? create(
    ui.FragmentProgram program,
    TextPainter paragraph,
    List<List<ui.TextBox>> boxes,
    Size size,
    double pixelRatio,
  ) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return null;
    }
    final ratio = pixelRatio.clamp(1.0, 4.0);
    final width = (size.width * ratio).ceil();
    final height = (size.height * ratio).ceil();
    if (width > 8192 || height > 2048) return null;
    final recorder = ui.PictureRecorder();
    paragraph.paint(Canvas(recorder)..scale(ratio), Offset.zero);
    final picture = recorder.endRecording();
    ui.Image? image;
    final allocated = <ui.FragmentShader>[];
    try {
      image = picture.toImageSync(width, height);
      final patches = <List<(Rect, ui.FragmentShader)>>[];
      for (var i = 0; i < boxes.length; i++) {
        final word = <(Rect, ui.FragmentShader)>[];
        for (final box in boxes[i]) {
          final rect = box.toRect();
          if (rect.isEmpty || !rect.overlaps(Offset.zero & size)) continue;
          final shader = program.fragmentShader();
          allocated.add(shader);
          shader
            ..setImageSampler(0, image)
            ..setFloat(0, width / ratio)
            ..setFloat(1, height / ratio)
            ..setFloat(2, rect.left)
            ..setFloat(3, rect.top - 1)
            ..setFloat(4, rect.width)
            ..setFloat(5, rect.height + 2)
            ..setFloat(7, (i + 1) * 1.618);
          word.add((rect, shader));
        }
        patches.add(word);
      }
      return WordLyricsSmoke._(image, size, patches);
    } catch (_) {
      for (final shader in allocated) {
        shader.dispose();
      }
      image?.dispose();
      return null;
    } finally {
      picture.dispose();
    }
  }

  bool paintWord(Canvas canvas, int index, double phase) {
    if (_disposed || index >= _patches.length || _patches[index].isEmpty) {
      return false;
    }
    for (final (rect, shader) in _patches[index]) {
      shader.setFloat(6, phase);
      _paint.shader = shader;
      canvas.drawRect(rect.inflate(rect.height * .85 + 2), _paint);
    }
    return true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _paint.shader = null;
    for (final word in _patches) {
      for (final (_, shader) in word) {
        shader.dispose();
      }
    }
    _image.dispose();
  }
}
