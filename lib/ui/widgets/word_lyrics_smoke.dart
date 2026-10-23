import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import '../../core/recoverable_resource.dart';
import '../../core/runtime_capabilities.dart';
import 'lyric_row_ink.dart';




final class WordLyricsSmoke {
  static final _program = RecoverableResource<ui.FragmentProgram>(
    load: () => ui.FragmentProgram.fromAsset('shaders/lyrics_smoke.frag'),
  );
  static bool get canRetry => _program.canRetry;
  static DateTime? get retryAt => _program.retryAt;
  static Future<ui.FragmentProgram?> program() async {
    final value = await _program.get();
    RuntimeCapabilities.instance.set(
      RuntimeCapability.lyricSmoke,
      CapabilityStatus(
        value == null
            ? CapabilityPhase.temporarilyUnavailable
            : CapabilityPhase.ready,
        reason: value == null ? 'shader_load_failed' : '',
        retryAt: retryAt,
      ),
    );
    return value;
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
    double pixelRatio, {
    LyricRowInk? rowInk,
  }) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return null;
    }
    final ratio = pixelRatio.clamp(1.0, 4.0);
    final width = (size.width * ratio).ceil();
    final rowHeight = (size.height * ratio).ceil();
    final lines = paragraph.computeLineMetrics();
    final rowCount = lines.isEmpty ? 1 : lines.length;
    final height = rowHeight * rowCount;
    if (width > 8192 || height > 2048) return null;
    final recorder = ui.PictureRecorder();
    ui.Picture? picture;
    ui.Image? image;
    LyricRowInk? ownedInk;
    final allocated = <ui.FragmentShader>[];
    try {
      final ink =
          rowInk ??
          (ownedInk = LyricRowInk.create(paragraph, boxes, size.width));
      final canvas = Canvas(recorder)..scale(ratio);
      for (var row = 0; row < rowCount; row++) {
        canvas.save();
        canvas.translate(0, row * rowHeight / ratio);
        ink.paragraphs[row].paint(canvas, Offset.zero);
        canvas.restore();
      }
      picture = recorder.endRecording();
      image = picture.toImageSync(width, height);
      final patches = <List<(Rect, ui.FragmentShader)>>[];
      for (var i = 0; i < boxes.length; i++) {
        final word = <(Rect, ui.FragmentShader)>[];
        for (final box in boxes[i]) {
          final rect = box.toRect();
          if (rect.isEmpty || !rect.overlaps(Offset.zero & size)) continue;
          final row = ink.rowForRect(rect);
          final shader = program.fragmentShader();
          allocated.add(shader);
          shader
            ..setImageSampler(0, image)
            ..setFloat(0, width / ratio)
            ..setFloat(1, rowHeight / ratio)
            ..setFloat(2, rect.left)
            ..setFloat(3, rect.top - 1)
            ..setFloat(4, rect.width)
            ..setFloat(5, rect.height + 2)
            ..setFloat(7, (i + 1) * 1.618)
            ..setFloat(8, row / rowCount)
            ..setFloat(9, 1 / rowCount);
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
      ownedInk?.dispose();
      if (recorder.isRecording) recorder.endRecording().dispose();
      picture?.dispose();
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
