import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../animations/mediaMotionTokens.dart';

final class _ArtworkFrame {
  final ui.Image image;
  final double weight;
  final Rect? normalizedRegion;
  final Object? identity;
  const _ArtworkFrame(
    this.image,
    this.weight, [
    this.normalizedRegion,
    this.identity,
  ]);
  _ArtworkFrame weighted(double weight) =>
      _ArtworkFrame(image, weight, normalizedRegion, identity);
}



class StableArtworkSurface extends StatefulWidget {
  final ImageProvider provider;
  final BoxFit fit;
  final Alignment alignment;
  final bool animateReplacement;

  
  
  final Rect? clampedImageRect;
  final Rect? normalizedImageRegion;
  final Object? artworkIdentity;
  final bool deferArtworkReplacement;
  const StableArtworkSurface({
    super.key,
    required this.provider,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.animateReplacement = true,
    this.clampedImageRect,
    this.normalizedImageRegion,
    this.artworkIdentity,
    this.deferArtworkReplacement = false,
  });
  @override
  State<StableArtworkSurface> createState() => StableArtworkSurfaceState();
}

class StableArtworkSurfaceState extends State<StableArtworkSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  final List<_ArtworkFrame> _base = [];
  _ArtworkFrame? _incoming;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _serial = 0;
  int _paintRevision = 0;
  Object? _request;
  Object? _requestedIdentity;
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
      ..add(_incoming!.weighted(1));
    _incoming = null;
    _paintRevision++;
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
    final request = (
      widget.provider,
      configuration,
      widget.normalizedImageRegion,
      widget.artworkIdentity,
    );
    if (_request == request) return;
    final defer =
        widget.deferArtworkReplacement &&
        widget.animateReplacement &&
        !_reduced &&
        _request != null &&
        _requestedIdentity != widget.artworkIdentity;
    _request = request;
    _requestedIdentity = widget.artworkIdentity;
    final serial = ++_serial;
    _detach();
    if (!defer) {
      _beginResolve(serial, request.$1, configuration, request.$3, request.$4);
      return;
    }
    final scheduler = SchedulerBinding.instance;
    
    
    scheduler.addPostFrameCallback((_) {
      if (!mounted || serial != _serial) return;
      scheduler.scheduleFrameCallback((_) {
        if (!mounted || serial != _serial) return;
        scheduler.addPostFrameCallback((_) {
          _beginResolve(
            serial,
            request.$1,
            configuration,
            request.$3,
            request.$4,
          );
        });
      });
    });
    scheduler.ensureVisualUpdate();
  }

  void _beginResolve(
    int serial,
    ImageProvider provider,
    ImageConfiguration configuration,
    Rect? region,
    Object? identity,
  ) {
    if (!mounted || serial != _serial) return;
    _stream = provider.resolve(configuration);
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
          _accept(_ArtworkFrame(image, 1, region, identity), serial);
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
      for (final frame in _base) frame.weighted(frame.weight * (1 - p)),
      _incoming!.weighted(p),
    ];
  }

  Future<void> _accept(_ArtworkFrame incoming, int serial) async {
    final current = _visibleFrames();
    final sameArtwork =
        incoming.identity != null &&
        current.length == 1 &&
        current.single.identity == incoming.identity;
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
        clampedImageRect: widget.clampedImageRect == null
            ? null
            : Offset.zero & snapshotSize,
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
          incoming.image.dispose();
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
        
        incoming.image.dispose();
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
      incoming.image.dispose();
      return;
    }
    setState(() {
      _incoming = incoming;
      _paintRevision++;
    });
    if (_base.isEmpty ||
        _reduced ||
        !widget.animateReplacement ||
        sameArtwork) {
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
            _paintRevision,
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
    _incoming?.image.dispose();
    super.dispose();
  }
}

class _ArtworkPainter extends CustomPainter {
  final List<_ArtworkFrame> base;
  final _ArtworkFrame? incoming;
  final Animation<double> motion;
  final BoxFit fit;
  final Alignment alignment;
  final Rect? clampedImageRect;
  final int revision;
  _ArtworkPainter(
    this.base,
    this.incoming,
    this.motion,
    this.fit,
    this.alignment,
    this.clampedImageRect,
    this.revision,
  ) : super(repaint: motion);
  static void draw(
    Canvas canvas,
    Size size,
    List<_ArtworkFrame> frames,
    BoxFit fit,
    Alignment alignment, {
    Rect? clampedImageRect,
    _ArtworkFrame? incoming,
    double progress = 0,
  }) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final outgoingOpacity = incoming == null ? 1.0 : 1.0 - progress;
    final drawIncoming = incoming != null && progress > 0;
    var active = drawIncoming ? 1 : 0;
    if (outgoingOpacity > 0) {
      for (final frame in frames) {
        if (frame.weight > 0) active++;
      }
    }
    if (active == 0) return;
    if (active > 1) canvas.saveLayer(bounds, Paint());
    if (clampedImageRect != null) {
      canvas.save();
      canvas.clipRect(bounds);
    }
    final paint = Paint()
      
      ..isAntiAlias = clampedImageRect == null
      ..filterQuality = FilterQuality.medium
      ..blendMode = active > 1 ? BlendMode.plus : BlendMode.srcOver;

    void drawFrame(_ArtworkFrame frame, double opacity) {
      final input = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      paint.color = Colors.white.withValues(alpha: opacity);
      if (clampedImageRect case final placement?) {
        final region = frame.normalizedRegion;
        final rect = region == null
            ? placement
            : Rect.fromLTRB(
                placement.left + region.left * placement.width,
                placement.top + region.top * placement.height,
                placement.left + region.right * placement.width,
                placement.top + region.bottom * placement.height,
              );
        if (rect.left <= bounds.left &&
            rect.top <= bounds.top &&
            rect.right >= bounds.right &&
            rect.bottom >= bounds.bottom) {
          canvas.drawImageRect(frame.image, Offset.zero & input, rect, paint);
          return;
        }
        
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
      } else {
        final fitted = applyBoxFit(fit, input, size);
        canvas.drawImageRect(
          frame.image,
          alignment.inscribe(fitted.source, Offset.zero & input),
          alignment.inscribe(fitted.destination, bounds),
          paint,
        );
      }
    }

    if (outgoingOpacity > 0) {
      for (final frame in frames) {
        if (frame.weight > 0) drawFrame(frame, frame.weight * outgoingOpacity);
      }
    }
    if (drawIncoming) drawFrame(incoming, progress);
    if (clampedImageRect != null) canvas.restore();
    if (active > 1) canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    draw(
      canvas,
      size,
      base,
      fit,
      alignment,
      clampedImageRect: clampedImageRect,
      incoming: incoming,
      progress: incoming == null
          ? 0
          : MediaMotionTokens.curve.transform(motion.value),
    );
  }

  @override
  bool shouldRepaint(_ArtworkPainter old) =>
      revision != old.revision ||
      fit != old.fit ||
      alignment != old.alignment ||
      clampedImageRect != old.clampedImageRect;
}
