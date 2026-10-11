import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../animations/cover_parallax_motion.dart';
import 'smooth_rounded_clip.dart';

class CoverParallax extends StatefulWidget {
  final double size;
  final BorderRadius borderRadius;
  final Color backgroundColor;
  final Color accentColor;
  final ImageProvider? image;
  final bool isPlaying;
  final bool enable3D;

  const CoverParallax({
    super.key,
    required this.size,
    required this.borderRadius,
    required this.backgroundColor,
    required this.accentColor,
    required this.image,
    required this.isPlaying,
    required this.enable3D,
  });

  @override
  State<CoverParallax> createState() => CoverParallaxState();
}

class CoverParallaxState extends State<CoverParallax>
    with SingleTickerProviderStateMixin {
  late final CoverParallaxMotion motion;
  late final _CoverMaterialPainter _material;
  Offset? _lastPointer;
  bool _hovered = false;
  bool _reduced = false;
  int get materialShaderBuilds => _material.shaderBuilds;

  @override
  void initState() {
    super.initState();
    motion = CoverParallaxMotion(this);
    _material = _CoverMaterialPainter(motion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    motion.reduceMotion(_reduced);
    _material.hairline = RoundedRasterScale.hairline(context);
  }

  @override
  void didUpdateWidget(covariant CoverParallax oldWidget) {
    super.didUpdateWidget(oldWidget);
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
  }

  void _hover(PointerHoverEvent event) {
    if (!_pointerSupported(event.kind)) return;
    _lastPointer = event.localPosition;
    _setTarget();
  }

  void _exit(PointerExitEvent event) {
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
    _material.enabled = widget.enable3D && !_reduced;
    _material.radius = widget.borderRadius;
    final artwork = RepaintBoundary(
      child: widget.image == null
          ? ColoredBox(color: widget.backgroundColor)
          : Image(
              image: widget.image!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
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
            child: artwork,
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
          IgnorePointer(child: CustomPaint(painter: _material)),
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
                  filterQuality: hover > 0.001 ? FilterQuality.medium : null,
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
    _material.disposeShaders();
    motion.dispose();
    super.dispose();
  }
}

class _CoverMaterialPainter extends CustomPainter {
  final CoverParallaxMotion motion;
  bool enabled = true;
  BorderRadius radius = BorderRadius.zero;
  double hairline = 1;
  ui.Shader? _wash, _highlight;
  final Paint _paint = Paint();
  int shaderBuilds = 0;

  _CoverMaterialPainter(this.motion) : super(repaint: motion);

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || motion.hover < 0.001 || size.isEmpty) return;
    if (_wash == null) {
      shaderBuilds++;
      _wash = ui.Gradient.linear(
        Offset.zero,
        const Offset(1, 1),
        const [Color(0x1AFFFFFF), Colors.transparent, Color(0x12000000)],
        const [0, 0.48, 1],
      );
      _highlight = ui.Gradient.radial(const Offset(0.25, 0.16), 0.75, const [
        Color(0x0DFFFFFF),
        Colors.transparent,
      ]);
    }
    canvas.save();
    canvas.scale(size.width, size.height);
    canvas.translate(motion.position.dx * 0.12, motion.position.dy * 0.10);
    _paint
      ..style = PaintingStyle.fill
      ..shader = _wash
      ..color = Colors.white.withValues(alpha: motion.hover);
    canvas.drawRect(const Rect.fromLTWH(-0.25, -0.25, 1.5, 1.5), _paint);
    _paint.shader = _highlight;
    canvas.drawRect(const Rect.fromLTWH(-0.25, -0.25, 1.5, 1.5), _paint);
    canvas.restore();
    _paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = hairline
      ..color = Colors.white.withValues(alpha: 0.12 * motion.hover);
    canvas.drawRRect(
      radius.toRRect((Offset.zero & size).deflate(hairline / 2)),
      _paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CoverMaterialPainter old) =>
      old.motion != motion || old.radius != radius || old.enabled != enabled;

  void disposeShaders() {
    _paint.shader = null;
    _wash?.dispose();
    _highlight?.dispose();
    _wash = _highlight = null;
  }
}
