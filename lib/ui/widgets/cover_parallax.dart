import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../animations/cover_parallax_motion.dart';
import '../animations/cover_layer_handoff.dart';
import '../animations/media_motion_tokens.dart';
import '../../core/cover_layers.dart';
import 'smooth_rounded_clip.dart';

class CoverParallax extends StatefulWidget {
  final double size;
  final BorderRadius borderRadius;
  final Color backgroundColor;
  final Color accentColor;
  final ImageProvider? image;
  final bool isPlaying;
  final bool enable3D;
  final bool layered;
  final Object? layerIdentity;
  final CoverLayerService? layerService;

  const CoverParallax({
    super.key,
    required this.size,
    required this.borderRadius,
    required this.backgroundColor,
    required this.accentColor,
    required this.image,
    required this.isPlaying,
    required this.enable3D,
    this.layered = false,
    this.layerIdentity,
    this.layerService,
  });

  @override
  State<CoverParallax> createState() => CoverParallaxState();
}

class CoverParallaxState extends State<CoverParallax>
    with TickerProviderStateMixin {
  late final CoverParallaxMotion motion;
  ui.FragmentShader? _sceneShader;
  _CoverRaster? _raster;
  late final AnimationController _layerReveal;
  late final Listenable _layerSignal;
  CoverLayerLease? _layers;
  Object? _requestedLayer;
  int _layerSerial = 0;
  Timer? _layerRetry;
  Offset? _lastPointer;
  bool _hovered = false;
  bool _reduced = false;
  int get materialShaderBuilds => 0;
  @visibleForTesting
  double get layerDepth => CoverLayerHandoff.depth(_layerReveal.value);
  @visibleForTesting
  double get layerSurfaceMix =>
      CoverLayerHandoff.surfaceMix(_layerReveal.value);
  @visibleForTesting
  bool get layerHandoffAnimating => _layerReveal.isAnimating;

  @override
  void initState() {
    super.initState();
    motion = CoverParallaxMotion(this);
    _layerReveal = AnimationController(
      vsync: this,
      duration: MediaMotionTokens.layerHandoff,
    );
    _layerSignal = Listenable.merge([motion, _layerReveal]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    motion.reduceMotion(_reduced);
    if (_reduced) _releaseLayers();
    if (!_reduced && _hovered) _ensureLayers();
  }

  @override
  void didUpdateWidget(covariant CoverParallax oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image ||
        oldWidget.layerIdentity != widget.layerIdentity ||
        oldWidget.layered != widget.layered ||
        oldWidget.enable3D != widget.enable3D ||
        oldWidget.layerService != widget.layerService) {
      _releaseLayers();
      if (_hovered) _ensureLayers();
    }
    if (oldWidget.size != widget.size ||
        oldWidget.enable3D != widget.enable3D) {
      _setTarget();
    }
    if (oldWidget.borderRadius != widget.borderRadius ||
        oldWidget.enable3D != widget.enable3D) {
      motion.invalidate();
    }
  }

  bool _pointerSupported(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.mouse ||
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _enter(PointerEnterEvent event) {
    if (!_pointerSupported(event.kind)) return;
    _hovered = true;
    _lastPointer = event.localPosition;
    _setTarget();
    _ensureLayers();
  }

  void _releaseLayers() {
    _layerRetry?.cancel();
    _layerRetry = null;
    _layerSerial++;
    _requestedLayer = null;
    _layerReveal.value = 0;
    _sceneShader?.dispose();
    _sceneShader = null;
    _raster?.dispose();
    _raster = null;
    _layers?.dispose();
    _layers = null;
  }

  void _ensureLayers() {
    final image = widget.image;
    if (!widget.layered || !widget.enable3D || _reduced || image == null) {
      return;
    }
    final identity = widget.layerIdentity ?? image;
    if (_requestedLayer == identity) return;
    _requestedLayer = identity;
    final serial = ++_layerSerial;
    final service = widget.layerService ?? CoverLayerService.instance;
    
    
    unawaited(
      service.acquire(identity, image).then((lease) {
        if (!mounted || serial != _layerSerial) {
          lease?.dispose();
          return;
        }
        if (lease == null) {
          if (!service.hasResult(identity)) {
            _requestedLayer = null;
            _layerRetry?.cancel();
            _layerRetry = Timer(const Duration(milliseconds: 300), () {
              _layerRetry = null;
              if (mounted && _hovered) _ensureLayers();
            });
          }
          return;
        }
        _CoverRaster? raster;
        ui.FragmentShader? shader;
        try {
          final program = lease.layers.program;
          if (program == null) {
            lease.dispose();
            return;
          }
          shader = program.fragmentShader();
          raster = _CoverRaster.borrow(lease.layers);
        } catch (_) {
          shader?.dispose();
          raster?.dispose();
          lease.dispose();
          return;
        }
        setState(() {
          _sceneShader?.dispose();
          _sceneShader = shader;
          _raster?.dispose();
          _raster = raster;
          _layers?.dispose();
          _layers = lease;
        });
        
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || serial != _layerSerial || _reduced) return;
          if (!_hovered && motion.position.distanceSquared < .000001) {
            _layerReveal.value = 1;
          } else {
            _layerReveal.forward(from: 0);
          }
        });
      }, onError: (Object _) {}),
    );
  }

  void _hover(PointerHoverEvent event) {
    if (!_pointerSupported(event.kind)) return;
    _lastPointer = event.localPosition;
    _setTarget();
  }

  void _exit(PointerExitEvent event) {
    _layerRetry?.cancel();
    _layerRetry = null;
    _hovered = false;
    _lastPointer = null;
    _setTarget();
  }

  void _setTarget() {
    final point = _lastPointer;
    final size = math.max(1.0, widget.size);
    final target = point != null && _hovered
        ? Offset(
            ((point.dx - size / 2) / (size / 2)).clamp(-1.0, 1.0),
            ((point.dy - size / 2) / (size / 2)).clamp(-1.0, 1.0),
          )
        : Offset.zero;
    motion.setTarget(target, hovered: _hovered);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final artwork = RepaintBoundary(
      child: widget.image == null
          ? ColoredBox(color: widget.backgroundColor)
          : Image(
              key: const ValueKey('cover_source_artwork'),
              image: widget.image!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
    );
    final hasScene =
        _layers != null &&
        _sceneShader != null &&
        _raster != null &&
        widget.layered &&
        widget.enable3D &&
        !_reduced;
    final layeredArtwork = Stack(
      fit: StackFit.expand,
      children: [
        
        
        Offstage(offstage: hasScene, child: artwork),
        if (hasScene)
          IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('cover_separated_layers'),
              painter: _CoverLayersPainter(
                _raster!,
                motion,
                _layerReveal,
                _layerSignal,
                _sceneShader!,
                MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
      ],
    );
    Widget shadow(double alpha, double blur, double y) => RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: alpha),
              blurRadius: blur,
              offset: Offset(0, y),
            ),
          ],
        ),
        child: const SizedBox.expand(),
      ),
    );
    final restingShadow = shadow(0.18, 10, 4);
    final raisedShadow = shadow(0.30, 16, 8);
    final face = SmoothRoundedClip(
      borderRadius: widget.borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: motion,
            child: layeredArtwork,
            builder: (context, child) => Transform.translate(
              key: const ValueKey('cover_artwork_layer'),
              offset:
                  motion.position *
                  (widget.enable3D
                      ? math.max(4.5, size * 0.028).clamp(4.5, 8.0)
                      : 3),
              child: Transform.scale(scale: 1.14, child: child),
            ),
          ),
          if (widget.image == null)
            AnimatedBuilder(
              animation: motion,
              child: LayoutBuilder(
                builder: (context, constraints) => Icon(
                  Icons.music_note_rounded,
                  size: (constraints.biggest.shortestSide * 0.25).clamp(
                    42.0,
                    72.0,
                  ),
                  color: widget.accentColor.withValues(alpha: 0.5),
                ),
              ),
              builder: (context, child) => Transform.translate(
                offset: motion.position * 7,
                child: child,
              ),
            ),
          RepaintBoundary(
            child: AnimatedContainer(
              duration: _reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              color: Colors.black.withValues(
                alpha: widget.isPlaying ? 0 : 0.45,
              ),
            ),
          ),
        ],
      ),
    );
    return MouseRegion(
      hitTestBehavior: HitTestBehavior.opaque,
      onEnter: _enter,
      onHover: _hover,
      onExit: _exit,
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: motion,
          child: face,
          builder: (context, face) {
            final depth = _reduced ? Offset.zero : motion.position;
            final hover = _reduced ? 0.0 : motion.hover;
            final tilt = widget.enable3D ? 0.14 : 0.0;
            final matrix = Matrix4.identity();
            if (depth.distanceSquared > 0.000001 && tilt != 0) {
              matrix
                ..setEntry(3, 2, 0.18 / math.max(1, size))
                ..rotateX(depth.dy * tilt)
                ..rotateY(-depth.dx * tilt);
            }
            final scale = 1 + hover * (widget.enable3D ? 0.055 : 0.04);
            matrix.scaleByDouble(scale, scale, 1, 1);
            return Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                Opacity(opacity: 1 - hover, child: restingShadow),
                Opacity(opacity: hover, child: raisedShadow),
                Transform(
                  key: const ValueKey('cover_parallax_transform'),
                  transform: matrix,
                  alignment: Alignment.center,
                  
                  
                  filterQuality: null,
                  child: face,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _layerRetry?.cancel();
    _layerSerial++;
    _layers?.dispose();
    _layerReveal.dispose();
    _sceneShader?.dispose();
    _raster?.dispose();
    motion.dispose();
    super.dispose();
  }
}



class _CoverRaster {
  final ui.Image original, mask, background;
  final ui.Image? priority, textRepair;
  _CoverRaster(
    this.original,
    this.mask,
    this.background, {
    this.priority,
    this.textRepair,
  });
  static _CoverRaster borrow(CoverLayers layers) {
    return _CoverRaster(
      layers.original.clone(),
      layers.mask.clone(),
      layers.background.clone(),
      priority: layers.priority?.clone(),
      textRepair: layers.textRepair?.clone(),
    );
  }

  void dispose() {
    original.dispose();
    mask.dispose();
    background.dispose();
    priority?.dispose();
    textRepair?.dispose();
  }
}

class _CoverLayersPainter extends CustomPainter {
  final _CoverRaster layers;
  final CoverParallaxMotion motion;
  final Animation<double> reveal;
  final ui.FragmentShader shader;
  final double pixelRatio;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _sourcePaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _mixPaint = Paint()..blendMode = BlendMode.plus;
  _CoverLayersPainter(
    this.layers,
    this.motion,
    this.reveal,
    Listenable signal,
    this.shader,
    this.pixelRatio,
  ) : super(repaint: signal) {
    shader.setImageSampler(0, layers.original);
    shader.setImageSampler(1, layers.mask);
    shader.setImageSampler(2, layers.background);
    shader.setImageSampler(3, layers.priority ?? layers.mask);
    shader.setImageSampler(4, layers.textRepair ?? layers.background);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final input = Size(
      layers.original.width.toDouble(),
      layers.original.height.toDouble(),
    );
    final fit = applyBoxFit(BoxFit.cover, input, size);
    final source = Alignment.center.inscribe(fit.source, Offset.zero & input);
    final bounds = Offset.zero & size;
    final mix = CoverLayerHandoff.surfaceMix(reveal.value);
    if (mix == 0) {
      
      _sourcePaint.color = Colors.white;
      canvas.drawImageRect(layers.original, source, bounds, _sourcePaint);
      return;
    }
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, source.left / input.width)
      ..setFloat(3, source.top / input.height)
      ..setFloat(4, source.width / input.width)
      ..setFloat(5, source.height / input.height)
      ..setFloat(6, motion.position.dx)
      ..setFloat(7, motion.position.dy)
      ..setFloat(8, CoverLayerHandoff.depth(reveal.value));
    shader
      ..setFloat(9, layers.original.width.toDouble())
      ..setFloat(10, layers.original.height.toDouble())
      ..setFloat(11, layers.mask.width.toDouble())
      ..setFloat(12, layers.mask.height.toDouble())
      ..setFloat(13, layers.background.width.toDouble())
      ..setFloat(14, layers.background.height.toDouble())
      ..setFloat(
        15,
        layers.priority != null && layers.textRepair != null ? 1 : 0,
      )
      ..setFloat(16, pixelRatio * 1.14 * (1.0 + motion.hover * 0.055));
    _paint.shader = shader;
    if (mix < 1) {
      
      
      
      canvas.saveLayer(bounds, Paint());
      _sourcePaint.color = Colors.white.withValues(alpha: 1 - mix);
      canvas.drawImageRect(layers.original, source, bounds, _sourcePaint);
      _mixPaint.color = Colors.white.withValues(alpha: mix);
      canvas.saveLayer(bounds, _mixPaint);
      canvas.drawRect(bounds, _paint);
      canvas.restore();
      canvas.restore();
    } else {
      canvas.drawRect(bounds, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CoverLayersPainter old) =>
      old.layers != layers ||
      old.motion != motion ||
      old.reveal != reveal ||
      old.shader != shader ||
      old.pixelRatio != pixelRatio;
}
