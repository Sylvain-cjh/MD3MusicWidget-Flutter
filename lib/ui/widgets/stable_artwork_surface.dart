import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../animations/media_motion_tokens.dart';

final class _ArtworkFrame {
  final ui.Image image;
  final double weight;
  const _ArtworkFrame(this.image, this.weight);
}



class StableArtworkSurface extends StatefulWidget {
  final ImageProvider provider;
  final BoxFit fit;
  final Alignment alignment;
  final bool animateReplacement;

  
  
  final Rect? clampedImageRect;
  const StableArtworkSurface({
    super.key,
    required this.provider,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.animateReplacement = true,
    this.clampedImageRect,
  });
  @override
  State<StableArtworkSurface> createState() => StableArtworkSurfaceState();
}

class StableArtworkSurfaceState extends State<StableArtworkSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  final List<_ArtworkFrame> _base = [];
  ui.Image? _incoming;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _serial = 0;
  Object? _request;
  Size _paintSize = Size.zero;
  double _dpi = 1;
  bool _reduced = false;
  @visibleForTesting
  int get retainedFrames => _base.length + (_incoming == null ? 0 : 1);
  @visibleForTesting
  double get transitionProgress => _motion.value;

  @override
  void initState() {
    super.initState();
    _motion =
        AnimationController(
          vsync: this,
          duration: MediaMotionTokens.replacement,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _settleFrames();
        });
  }

  void _settleFrames() {
    if (_incoming == null) return;
    for (final frame in _base) {
      frame.image.dispose();
    }
    _base
      ..clear()
      ..add(_ArtworkFrame(_incoming!, 1));
    _incoming = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dpi = MediaQuery.devicePixelRatioOf(context);
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced && _motion.isAnimating) _motion.value = 1;
    _resolve();
  }

  @override
  void didUpdateWidget(StableArtworkSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animateReplacement && _motion.isAnimating) {
      
      
      _motion.value = 1;
    }
    _resolve();
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = null;
    _stream = null;
  }

  void _resolve() {
    final configuration = createLocalImageConfiguration(context);
    final request = (widget.provider, configuration);
    if (_request == request) return;
    _request = request;
    final serial = ++_serial;
    _detach();
    _stream = widget.provider.resolve(configuration);
    var delivered = false;
    _listener = ImageStreamListener(
      (info, synchronous) {
        if (delivered) {
          info.dispose();
          return;
        }
        delivered = true;
        final image = info.image.clone();
        info.dispose();
        if (!mounted || serial != _serial) {
          image.dispose();
          return;
        }
        
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || serial != _serial) {
            image.dispose();
            return;
          }
          _detach();
          _accept(image, serial);
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      },
      onError: (Object error, StackTrace? stack) {
        
        if (mounted && serial == _serial) _detach();
      },
    );
    _stream!.addListener(_listener!);
  }

  List<_ArtworkFrame> _visibleFrames() {
    if (_incoming == null) return List.of(_base);
    final p = MediaMotionTokens.curve.transform(_motion.value);
    return [
      for (final frame in _base)
        _ArtworkFrame(frame.image, frame.weight * (1 - p)),
      _ArtworkFrame(_incoming!, p),
    ];
  }

  Future<void> _accept(ui.Image image, int serial) async {
    final current = _visibleFrames();
    _motion.stop();
    if (current.length >= 4 && !_paintSize.isEmpty) {
      
      
      final box = context.findRenderObject();
      var rasterScale = _dpi;
      if (box is RenderBox && box.hasSize) {
        final origin = box.localToGlobal(Offset.zero);
        final xScale =
            (box.localToGlobal(const Offset(1, 0)) - origin).distance;
        final yScale =
            (box.localToGlobal(const Offset(0, 1)) - origin).distance;
        final scale = xScale > yScale ? xScale : yScale;
        if (scale.isFinite && scale > 0) rasterScale *= scale;
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(rasterScale);
      final snapshotSize = widget.clampedImageRect?.size ?? _paintSize;
      _ArtworkPainter.draw(
        canvas,
        snapshotSize,
        current,
        widget.fit,
        widget.alignment,
      );
      final picture = recorder.endRecording();
      ui.Image? snapshot;
      try {
        snapshot = await picture.toImage(
          (snapshotSize.width * rasterScale).ceil(),
          (snapshotSize.height * rasterScale).ceil(),
        );
        if (!mounted || serial != _serial) {
          snapshot.dispose();
          image.dispose();
          return;
        }
        for (final frame in current) {
          frame.image.dispose();
        }
        _base
          ..clear()
          ..add(_ArtworkFrame(snapshot, 1));
        _incoming = null;
      } catch (_) {
        
        image.dispose();
        if (mounted && _incoming != null) _motion.forward();
        return;
      } finally {
        picture.dispose();
      }
    } else {
      _base
        ..clear()
        ..addAll(current);
      _incoming = null;
    }
    if (!mounted || serial != _serial) {
      image.dispose();
      return;
    }
    setState(() {
      _incoming = image;
    });
    if (_base.isEmpty || _reduced || !widget.animateReplacement) {
      _motion.value = 1;
      
      _settleFrames();
    } else {
      _motion.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _paintSize = constraints.biggest;
      return RepaintBoundary(
        child: CustomPaint(
          painter: _ArtworkPainter(
            _base,
            _incoming,
            _motion,
            widget.fit,
            widget.alignment,
            widget.clampedImageRect,
          ),
          size: Size.infinite,
        ),
      );
    },
  );
  @override
  void dispose() {
    _serial++;
    _detach();
    _motion.dispose();
    for (final frame in _base) {
      frame.image.dispose();
    }
    _incoming?.dispose();
    super.dispose();
  }
}

class _ArtworkPainter extends CustomPainter {
  final List<_ArtworkFrame> base;
  final ui.Image? incoming;
  final Animation<double> motion;
  final BoxFit fit;
  final Alignment alignment;
  final Rect? clampedImageRect;
  _ArtworkPainter(
    this.base,
    this.incoming,
    this.motion,
    this.fit,
    this.alignment,
    this.clampedImageRect,
  ) : super(repaint: motion);
  static void draw(
    Canvas canvas,
    Size size,
    List<_ArtworkFrame> frames,
    BoxFit fit,
    Alignment alignment, {
    Rect? clampedImageRect,
  }) {
    if (size.isEmpty || frames.isEmpty) return;
    final bounds = Offset.zero & size;
    final active = frames.where((f) => f.weight > 0).toList();
    if (active.isEmpty) return;
    if (active.length > 1) canvas.saveLayer(bounds, Paint());
    for (final frame in active) {
      final input = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      final fitted = applyBoxFit(fit, input, size);
      final paint = Paint()
        
        
        
        ..isAntiAlias = clampedImageRect == null
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: frame.weight)
        ..blendMode = active.length > 1 ? BlendMode.plus : BlendMode.srcOver;
      if (clampedImageRect case final rect?) {
        
        
        
        canvas.save();
        canvas.clipRect(bounds);
        final xs = [
          (bounds.left, rect.left, 0.0, 1.0),
          (rect.left, rect.right, 0.0, input.width),
          (rect.right, bounds.right, input.width - 1, input.width),
        ];
        final ys = [
          (bounds.top, rect.top, 0.0, 1.0),
          (rect.top, rect.bottom, 0.0, input.height),
          (rect.bottom, bounds.bottom, input.height - 1, input.height),
        ];
        for (final x in xs) {
          if (x.$2 <= x.$1) continue;
          for (final y in ys) {
            if (y.$2 <= y.$1) continue;
            final destination = Rect.fromLTRB(x.$1, y.$1, x.$2, y.$2);
            if (!destination.overlaps(bounds)) continue;
            canvas.drawImageRect(
              frame.image,
              Rect.fromLTRB(x.$3, y.$3, x.$4, y.$4),
              destination,
              paint,
            );
          }
        }
        canvas.restore();
      } else {
        canvas.drawImageRect(
          frame.image,
          alignment.inscribe(fitted.source, Offset.zero & input),
          alignment.inscribe(fitted.destination, bounds),
          paint,
        );
      }
    }
    if (active.length > 1) canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = MediaMotionTokens.curve.transform(motion.value);
    draw(
      canvas,
      size,
      [
        for (final frame in base)
          _ArtworkFrame(
            frame.image,
            incoming == null ? frame.weight : frame.weight * (1 - p),
          ),
        if (incoming != null) _ArtworkFrame(incoming!, p),
      ],
      fit,
      alignment,
      clampedImageRect: clampedImageRect,
    );
  }

  @override
  bool shouldRepaint(_ArtworkPainter old) => true;
}
