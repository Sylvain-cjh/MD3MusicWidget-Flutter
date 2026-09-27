import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  State<CoverParallax> createState() => _CoverParallaxState();
}

class _CoverParallaxState extends State<CoverParallax>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _motion = ValueNotifier<int>(0);
  Duration _lastTick = Duration.zero;
  Offset _position = Offset.zero;
  Offset _target = Offset.zero;
  double _hoverAmount = 0;
  double _targetHoverAmount = 0;
  bool _hovered = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_advance);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced == _reduceMotion) return;
    _reduceMotion = reduced;
    if (reduced) {
      _ticker.stop();
      _lastTick = Duration.zero;
      _position = Offset.zero;
      _target = Offset.zero;
      _hoverAmount = 0;
      _targetHoverAmount = 0;
    }
  }

  @override
  void didUpdateWidget(covariant CoverParallax oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enable3D && !widget.enable3D) {
      _target = Offset.zero;
      _startMotion();
    }
  }

  void _startMotion() {
    if (_reduceMotion || _ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _advance(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastTick).inMicroseconds / 1000000).clamp(0.001, 0.05);
    _lastTick = elapsed;
    final response = _hovered ? 0.065 : 0.115;
    final fraction = 1 - math.exp(-dt / response);
    _position = Offset.lerp(_position, _target, fraction)!;
    _hoverAmount += (_targetHoverAmount - _hoverAmount) * fraction;
    if ((_position - _target).distanceSquared < 0.000004 &&
        (_hoverAmount - _targetHoverAmount).abs() < 0.002) {
      _position = _target;
      _hoverAmount = _targetHoverAmount;
      _ticker.stop();
      _lastTick = Duration.zero;
    }
    _motion.value++;
  }

  void _onEnter(PointerEnterEvent event) {
    setState(() => _hovered = true);
    if (_reduceMotion) return;
    _targetHoverAmount = 1;
    _updateTarget(event.localPosition);
    _startMotion();
  }

  void _onHover(PointerHoverEvent event) {
    if (_reduceMotion) return;
    _updateTarget(event.localPosition);
  }

  void _updateTarget(Offset localPosition) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    final next = Offset(
      ((localPosition.dx - size.width / 2) / (size.width / 2)).clamp(-1.0, 1.0),
      ((localPosition.dy - size.height / 2) / (size.height / 2)).clamp(
        -1.0,
        1.0,
      ),
    );
    if ((next - _target).distanceSquared < 0.0001) return;
    _target = next;
    _startMotion();
  }

  void _onExit(PointerExitEvent event) {
    setState(() => _hovered = false);
    _target = Offset.zero;
    _targetHoverAmount = 0;
    _startMotion();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final image = widget.image;
    final Widget artwork = RepaintBoundary(
      child: image == null
          ? ColoredBox(color: widget.backgroundColor)
          : Image(
              image: image,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
    );
    return MouseRegion(
      onEnter: _onEnter,
      onHover: _onHover,
      onExit: _onExit,
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedContainer(
          duration: _reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.30 : 0.18),
                blurRadius: _hovered ? 16 : 10,
                offset: Offset(0, _hovered ? 8 : 4),
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _motion,
            child: artwork,
            builder: (context, artwork) {
              final depth = _reduceMotion ? Offset.zero : _position;
              final hover = _reduceMotion ? 0.0 : _hoverAmount;
              final tilt = widget.enable3D ? 0.12 : 0.0;
              final transform = Matrix4.identity()
                ..setEntry(3, 2, 0.0011)
                ..rotateX(depth.dy * tilt)
                ..rotateY(-depth.dx * tilt)
                ..scaleByDouble(
                  1 + hover * (widget.enable3D ? 0.055 : 0.04),
                  1 + hover * (widget.enable3D ? 0.055 : 0.04),
                  1,
                  1,
                );
              return Transform(
                key: const ValueKey('cover_parallax_transform'),
                transform: transform,
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: widget.borderRadius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Transform.translate(
                        key: const ValueKey('cover_artwork_layer'),
                        offset: depth * (widget.enable3D ? 4.5 : 3.0),
                        child: Transform.scale(scale: 1.14, child: artwork),
                      ),
                      if (image == null)
                        Transform.translate(
                          offset: depth * 7.0,
                          child: Icon(
                            Icons.music_note_rounded,
                            size: (size * 0.25).clamp(42.0, 72.0),
                            color: widget.accentColor.withValues(alpha: 0.5),
                          ),
                        ),
                      if (widget.enable3D && hover > 0.001)
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment(-0.9 + depth.dx * 0.45, -1),
                                end: Alignment(0.9 + depth.dx * 0.45, 1),
                                colors: [
                                  Colors.white.withValues(alpha: 0.14 * hover),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.07 * hover),
                                ],
                                stops: const [0.0, 0.48, 1.0],
                              ),
                            ),
                          ),
                        ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        color: Colors.black.withValues(
                          alpha: widget.isPlaying ? 0.0 : 0.45,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
