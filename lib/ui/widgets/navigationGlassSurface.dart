import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/recoverableResource.dart';
import '../../core/widgetDiagnostics.dart';
import 'backdropCaptureBoundary.dart';




class NavigationGlassSurface extends StatefulWidget {
  const NavigationGlassSurface({
    super.key,
    required this.backdropKey,
    required this.backgroundRevision,
    required this.allowCapture,
    required this.trackSize,
    required this.builder,
    this.glyphKey,
  });

  final GlobalKey backdropKey;
  final GlobalKey? glyphKey;
  final Listenable backgroundRevision;
  final bool allowCapture;
  final Size trackSize;
  final Widget Function(NavigationGlassTexture? texture) builder;

  @override
  State<NavigationGlassSurface> createState() => _NavigationGlassSurfaceState();
}

class _NavigationGlassSurfaceState extends State<NavigationGlassSurface>
    with WidgetsBindingObserver {
  static final _program = RecoverableResource<ui.FragmentProgram>(
    load: () => ui.FragmentProgram.fromAsset('shaders/navigationGlass.frag'),
  );
  static const _settle = Duration(milliseconds: 100);
  static const _backgroundSettle = Duration(milliseconds: 1050);
  static const _retryDelay = Duration(milliseconds: 85);
  static const _maxCaptureRetries = 3;
  Timer? _timer;
  int _serial = 0;
  bool _busy = false;
  int? _queuedAfterBusy;
  double _dpr = 1;
  bool _highContrast = false;
  NavigationGlassTexture? _texture;

  bool get _canCapture => widget.allowCapture && !_highContrast;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.backgroundRevision.addListener(_backgroundChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final contrast = MediaQuery.highContrastOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    
    MediaQuery.textScalerOf(context);
    Directionality.maybeOf(context);
    if (contrast != _highContrast && contrast) _clear();
    _highContrast = contrast;
    _dpr = dpr;
    _schedule(_settle);
  }

  @override
  void didUpdateWidget(NavigationGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundRevision != widget.backgroundRevision) {
      oldWidget.backgroundRevision.removeListener(_backgroundChanged);
      widget.backgroundRevision.addListener(_backgroundChanged);
    }
    if (oldWidget.trackSize != widget.trackSize ||
        oldWidget.allowCapture != widget.allowCapture ||
        oldWidget.backdropKey != widget.backdropKey ||
        oldWidget.glyphKey != widget.glyphKey ||
        oldWidget.backgroundRevision != widget.backgroundRevision) {
      _schedule(_settle);
    }
  }

  void _backgroundChanged() =>
      _schedule(_texture == null ? _settle : _backgroundSettle);

  void _schedule(Duration delay) {
    _timer?.cancel();
    _queuedAfterBusy = null;
    final serial = ++_serial;
    if (_canCapture) {
      _timer = Timer(delay, () => unawaited(_refresh(serial)));
    }
  }

  bool _isCurrent(int serial) => mounted && serial == _serial && _canCapture;

  void _retry(int serial, int attempt) {
    if (attempt >= _maxCaptureRetries || !_isCurrent(serial)) return;
    _timer?.cancel();
    _timer = Timer(
      _retryDelay,
      () => unawaited(_refresh(serial, attempt: attempt + 1)),
    );
  }

  Future<void> _refresh(int serial, {int attempt = 0}) async {
    if (!_isCurrent(serial)) return;
    if (_busy) {
      _queuedAfterBusy = serial;
      return;
    }
    _busy = true;
    ui.Image? sample;
    ui.Image? glyphSample;
    ui.FragmentShader? pendingShader;
    ui.FragmentShader? pendingTrackShader;
    try {
      final program = await _program.get();
      if (program == null || !_isCurrent(serial)) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_isCurrent(serial)) return;
      final backdrop = widget.backdropKey.currentContext?.findRenderObject();
      final target = context.findRenderObject();
      if (backdrop is! RenderBackdropCaptureBoundary ||
          !backdrop.attached ||
          !backdrop.hasSize ||
          target is! RenderBox ||
          !target.attached ||
          !target.hasSize ||
          target.size.isEmpty) {
        _retry(serial, attempt);
        return;
      }
      final area = Rect.fromPoints(
        backdrop.globalToLocal(target.localToGlobal(Offset.zero)),
        backdrop.globalToLocal(
          target.localToGlobal(target.size.bottomRight(Offset.zero)),
        ),
      );
      final bounds = Offset.zero & backdrop.size;
      if (!area.isFinite ||
          area.isEmpty ||
          !bounds.inflate(0.5).contains(area.topLeft) ||
          !bounds.inflate(0.5).contains(area.bottomRight)) {
        _retry(serial, attempt);
        return;
      }
      
      
      final crop = area.inflate(area.height * 1.2).intersect(bounds);
      final pixelRatio = math.min(
        _dpr,
        math.min(768 / crop.width, 256 / crop.height),
      );
      WidgetDiagnostics.count('navigationGlassCaptures');
      final captured = await WidgetDiagnostics.measure(
        'navigationGlass.capture',
        () => backdrop.capture(crop, pixelRatio: pixelRatio),
      );
      sample = captured;
      if (!_isCurrent(serial)) return;
      final glyphKey = widget.glyphKey;
      if (glyphKey != null) {
        final glyphs = glyphKey.currentContext?.findRenderObject();
        if (glyphs is! RenderBackdropCaptureBoundary ||
            !glyphs.attached ||
            !glyphs.hasSize ||
            glyphs.size.isEmpty) {
          _retry(serial, attempt);
          return;
        }
        final glyphDpr = math.min(
          _dpr,
          math.min(768 / glyphs.size.width, 128 / glyphs.size.height),
        );
        glyphSample = await glyphs.capture(
          Offset.zero & glyphs.size,
          pixelRatio: glyphDpr,
        );
        if (!_isCurrent(serial)) return;
      }
      final uv = Rect.fromLTWH(
        (area.left - crop.left) / crop.width,
        (area.top - crop.top) / crop.height,
        area.width / crop.width,
        area.height / crop.height,
      );
      final shader = program.fragmentShader();
      pendingShader = shader;
      shader.setImageSampler(0, captured);
      shader.setImageSampler(1, glyphSample ?? captured);
      final trackShader = program.fragmentShader();
      pendingTrackShader = trackShader;
      trackShader.setImageSampler(0, captured);
      trackShader.setImageSampler(1, captured);
      final replacement = NavigationGlassTexture._(
        captured,
        glyphSample,
        shader,
        trackShader,
        uv,
        target,
      );
      sample = null;
      glyphSample = null;
      pendingShader = null;
      pendingTrackShader = null;
      final previous = _texture;
      setState(() => _texture = replacement);
      WidgetDiagnostics.count('navigationGlassTexturesReady');
      _retire(previous);
    } catch (_) {
      
      
      _retry(serial, attempt);
    } finally {
      pendingShader?.dispose();
      pendingTrackShader?.dispose();
      sample?.dispose();
      glyphSample?.dispose();
      _busy = false;
      final queued = _queuedAfterBusy;
      _queuedAfterBusy = null;
      if (queued != null && _isCurrent(queued)) unawaited(_refresh(queued));
    }
  }

  void _retire(NavigationGlassTexture? texture) {
    if (texture == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => texture.dispose());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _clear() {
    final old = _texture;
    _texture = null;
    _retire(old);
  }

  @override
  void didHaveMemoryPressure() {
    _timer?.cancel();
    _serial++;
    if (_texture != null) setState(_clear);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _serial++;
    WidgetsBinding.instance.removeObserver(this);
    widget.backgroundRevision.removeListener(_backgroundChanged);
    _texture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: widget.trackSize,
    child: widget.builder(_highContrast ? null : _texture),
  );
}

final class NavigationGlassTexture {
  const NavigationGlassTexture._(
    this.image,
    this.glyphs,
    this.shader,
    this.trackShader,
    this.uv,
    this.track,
  );

  final ui.Image image;
  final ui.Image? glyphs;
  final ui.FragmentShader shader;
  final ui.FragmentShader trackShader;
  final Rect uv;
  final RenderBox track;

  void dispose() {
    shader.dispose();
    trackShader.dispose();
    image.dispose();
    glyphs?.dispose();
  }
}



class NavigationGlassTrack extends StatelessWidget {
  const NavigationGlassTrack({
    super.key,
    required this.texture,
    required this.shape,
    required this.color,
    required this.radius,
  });

  final NavigationGlassTexture texture;
  final ShapeBorder shape;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _GlassTrackPainter(texture, shape, color, radius),
      child: const SizedBox.expand(),
    ),
  );
}

class _GlassTrackPainter extends CustomPainter {
  const _GlassTrackPainter(this.texture, this.shape, this.color, this.radius);

  final NavigationGlassTexture texture;
  final ShapeBorder shape;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final uv = texture.uv;
    final shader = texture.trackShader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, uv.left)
      ..setFloat(3, uv.top)
      ..setFloat(4, uv.width)
      ..setFloat(5, uv.height)
      ..setFloat(6, color.r)
      ..setFloat(7, color.g)
      ..setFloat(8, color.b)
      ..setFloat(9, color.a)
      ..setFloat(10, math.min(radius, size.shortestSide / 2))
      ..setFloat(24, .5 / texture.image.width)
      ..setFloat(25, .5 / texture.image.height)
      ..setFloat(27, 1);
    canvas.drawPath(
      shape.getOuterPath(Offset.zero & size),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_GlassTrackPainter oldDelegate) =>
      oldDelegate.texture != texture ||
      oldDelegate.shape != shape ||
      oldDelegate.color != color ||
      oldDelegate.radius != radius;
}



class NavigationGlassThumb extends StatelessWidget {
  const NavigationGlassThumb({
    super.key,
    required this.texture,
    required this.shape,
    required this.position,
    required this.engaged,
    required this.trackColor,
    required this.trackRadius,
  });

  final NavigationGlassTexture texture;
  final ShapeBorder shape;
  final double position;
  final bool engaged;
  final Color trackColor;
  final double trackRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final tint = dark
        ? Color.lerp(scheme.secondaryContainer, scheme.surface, .18)!
        : scheme.secondaryContainer;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: engaged && !reduced ? 1 : 0),
      duration: reduced
          ? Duration.zero
          : Duration(milliseconds: engaged ? 110 : 170),
      curve: Curves.easeOutCubic,
      builder: (context, press, _) => CustomPaint(
        painter: _GlassPainter(
          texture,
          shape,
          tint,
          trackColor,
          trackRadius,
          dark,
          press,
          position,
          () => context.mounted ? context.findRenderObject() : null,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

final class _GlassPainter extends CustomPainter {
  const _GlassPainter(
    this.texture,
    this.shape,
    this.tint,
    this.trackColor,
    this.trackRadius,
    this.dark,
    this.press,
    this.position,
    this.findThumb,
  );

  final NavigationGlassTexture texture;
  final ShapeBorder shape;
  final Color tint;
  final Color trackColor;
  final double trackRadius;
  final bool dark;
  final double press;
  final double position;
  final RenderObject? Function() findThumb;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final path = shape.getOuterPath(bounds);
    final thumb = findThumb();
    final track = texture.track;
    if (thumb is! RenderBox ||
        !thumb.attached ||
        !track.attached ||
        !track.hasSize ||
        track.size.isEmpty) {
      canvas.drawPath(path, Paint()..color = tint);
      return;
    }
    final rect = MatrixUtils.transformRect(thumb.getTransformTo(track), bounds);
    if (!rect.isFinite || rect.isEmpty) {
      canvas.drawPath(path, Paint()..color = tint);
      return;
    }
    final radius = switch (shape) {
      final RoundedSuperellipseBorder rounded => math.min(
        rounded.borderRadius.resolve(TextDirection.ltr).topLeft.x,
        size.shortestSide / 2,
      ),
      _ => size.shortestSide / 2,
    };
    final uv = texture.uv;
    final trackW = track.size.width, trackH = track.size.height;
    final shader = texture.shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, uv.left + rect.left / trackW * uv.width)
      ..setFloat(3, uv.top + rect.top / trackH * uv.height)
      ..setFloat(4, rect.width / trackW * uv.width)
      ..setFloat(5, rect.height / trackH * uv.height)
      ..setFloat(6, tint.r)
      ..setFloat(7, tint.g)
      ..setFloat(8, tint.b)
      ..setFloat(9, (dark ? .19 : .17) - .07 * press)
      ..setFloat(10, radius)
      ..setFloat(11, press)
      ..setFloat(12, dark ? 1 : 0)
      ..setFloat(13, rect.left / trackW)
      ..setFloat(14, rect.top / trackH)
      ..setFloat(15, rect.width / trackW)
      ..setFloat(16, rect.height / trackH)
      ..setFloat(17, trackW)
      ..setFloat(18, trackH)
      ..setFloat(19, trackColor.r)
      ..setFloat(20, trackColor.g)
      ..setFloat(21, trackColor.b)
      ..setFloat(22, trackColor.a)
      ..setFloat(23, trackRadius)
      ..setFloat(24, .5 / texture.image.width)
      ..setFloat(25, .5 / texture.image.height)
      ..setFloat(26, texture.glyphs == null ? 0 : 1)
      ..setFloat(27, 0);
    WidgetDiagnostics.count('navigationGlassPaints');
    
    canvas.drawPath(path, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GlassPainter oldDelegate) =>
      oldDelegate.texture != texture ||
      oldDelegate.shape != shape ||
      oldDelegate.tint != tint ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.trackRadius != trackRadius ||
      oldDelegate.dark != dark ||
      oldDelegate.press != press ||
      oldDelegate.position != position;
}
