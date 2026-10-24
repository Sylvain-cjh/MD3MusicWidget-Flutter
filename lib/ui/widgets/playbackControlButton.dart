import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';

import '../animations/coverParallaxMotion.dart';
import '../animations/transportTactileMotion.dart';



class PlaybackControlButton extends StatefulWidget {
  final double width, height, iconSize;
  final BorderRadius borderRadius;
  final Color background, foreground;
  final IconData icon;
  final bool? isPlaying;
  final int direction;
  final String label;
  final VoidCallback? onPressed;
  const PlaybackControlButton({
    super.key,
    required this.width,
    required this.height,
    required this.iconSize,
    required this.borderRadius,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPlaying,
    this.direction = 0,
  });
  @override
  State<PlaybackControlButton> createState() => PlaybackControlButtonState();
}

class PlaybackControlButtonState extends State<PlaybackControlButton>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final CoverParallaxMotion motion = CoverParallaxMotion(this);
  late final AnimationController _glyph = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: widget.isPlaying == true ? 1 : 0,
  );
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );
  late final Listenable _visual = Listenable.merge([motion, _press]);
  bool _pressed = false, _hovered = false;
  int? _pointer;
  int builds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _release();
    _hovered = false;
    motion.setTarget(Offset.zero, hovered: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.reduceMotion(true);
      _glyph.stop();
      _glyph.value = widget.isPlaying == true ? 1 : 0;
      _press.stop();
      _press.value = 0;
    } else {
      motion.reduceMotion(false);
    }
  }

  void _pressTo(bool pressed) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _press.value = 0;
    } else {
      _press.animateWith(
        SpringSimulation(
          pressed
              ? TransportTactileMotion.pressSpring
              : TransportTactileMotion.releaseSpring,
          _press.value,
          pressed ? 1 : 0,
          _press.velocity,
        ),
      );
    }
  }

  void _release() {
    _pointer = null;
    if (_pressed && mounted) {
      _pressTo(false);
      setState(() => _pressed = false);
    }
  }

  void _point(Offset local, PointerDeviceKind kind) {
    if (widget.onPressed == null ||
        (kind != PointerDeviceKind.mouse && kind != PointerDeviceKind.stylus)) {
      return;
    }
    motion.setTarget(
      TransportTactileMotion.pointerTarget(
        local,
        context.size ?? Size(widget.width, widget.height),
      ),
      hovered: true,
    );
  }

  void _enter(PointerEnterEvent event) {
    if (widget.onPressed == null || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    if (!_hovered) setState(() => _hovered = true);
    _point(event.localPosition, event.kind);
  }

  void _exit(PointerExitEvent event) {
    if (_hovered) setState(() => _hovered = false);
    motion.setTarget(Offset.zero, hovered: false);
  }

  @override
  void didUpdateWidget(covariant PlaybackControlButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      final target = widget.isPlaying == true ? 1.0 : 0.0;
      if (MediaQuery.disableAnimationsOf(context)) {
        _glyph.value = target;
      } else {
        _glyph.animateTo(target, curve: Curves.easeOutCubic);
      }
    }
    if (widget.onPressed == null) {
      _release();
      _hovered = false;
      motion.setTarget(Offset.zero, hovered: false);
    }
    if (oldWidget.width != widget.width || oldWidget.height != widget.height) {
      motion.setTarget(Offset.zero, hovered: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    motion.dispose();
    _press.dispose();
    _glyph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final shape = RoundedRectangleBorder(borderRadius: widget.borderRadius);
    final surface = RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.background,
          borderRadius: widget.borderRadius,
        ),
        child: const SizedBox.expand(),
      ),
    );
    final glyph = RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = widget.iconSize * constraints.maxHeight / widget.height;
          return Center(
            child: widget.isPlaying != null
                ? AnimatedIcon(
                    key: const ValueKey('transport_play_icon'),
                    icon: AnimatedIcons.play_pause,
                    progress: _glyph,
                    size: size,
                    color: widget.foreground,
                  )
                : Icon(widget.icon, size: size, color: widget.foreground),
          );
        },
      ),
    );
    const shadowMargin = 24.0;
    Widget shadow(double blur, double dy, double alpha) => RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.all(shadowMargin),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: alpha),
                blurRadius: blur,
                offset: Offset(0, dy),
              ),
            ],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    final raisedShadow = shadow(16, 8, .30);
    final pressedShadow = shadow(4, 2, .10);
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: MouseRegion(
          cursor: widget.onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: _enter,
          onExit: _exit,
          onHover: (event) => _point(event.localPosition, event.kind),
          child: Listener(
            onPointerDown: (event) {
              if (_pointer != null ||
                  widget.onPressed == null ||
                  event.buttons & kPrimaryButton == 0) {
                return;
              }
              _pointer = event.pointer;
              _point(event.localPosition, event.kind);
              _pressTo(true);
              setState(() => _pressed = true);
            },
            onPointerMove: (event) {
              if (event.pointer == _pointer) {
                _point(event.localPosition, event.kind);
              }
            },
            onPointerUp: (event) {
              if (event.pointer == _pointer) _release();
            },
            onPointerCancel: (event) {
              if (event.pointer == _pointer) _release();
            },
            child: Tooltip(
              message: widget.label,
              child: Semantics(
                button: true,
                label: widget.label,
                enabled: widget.onPressed != null,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _visual,
                        builder: (context, _) {
                          final point = reduced ? Offset.zero : motion.position;
                          final springPress = reduced
                              ? 0.0
                              : _press.value.clamp(-.08, 1.0);
                          final press = springPress.clamp(0.0, 1.0);
                          final hover = reduced ? 0.0 : motion.hover;
                          final tiltPoint = TransportTactileMotion.inertialTilt(
                            point,
                            reduced ? Offset.zero : motion.velocity,
                          );
                          Matrix4 layer(double distance, double tilt) {
                            final transform = Matrix4.identity();
                            if (!reduced &&
                                (point.distanceSquared > .000001 ||
                                    press > .000001)) {
                              transform.setEntry(3, 2, .0015);
                              transform.rotateX(
                                tiltPoint.dy * tilt * (1 - press * .65),
                              );
                              transform.rotateY(
                                -tiltPoint.dx * tilt * (1 - press * .65),
                              );
                              transform.translateByDouble(
                                point.dx * distance * (1 - press * .5),
                                point.dy * distance * (1 - press * .5) + press,
                                0,
                                1,
                              );
                            }
                            return transform;
                          }

                          final scale = 1 + hover * .018 - springPress * .055;
                          return Transform.scale(
                            key: const ValueKey('transport_press_transform'),
                            scale: scale,
                            child: Stack(
                              fit: StackFit.expand,
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: -shadowMargin,
                                  top: -shadowMargin,
                                  width: widget.width + shadowMargin * 2,
                                  height: widget.height + shadowMargin * 2,
                                  child: Opacity(
                                    opacity: hover * (1 - press),
                                    child: raisedShadow,
                                  ),
                                ),
                                Positioned(
                                  left: -shadowMargin,
                                  top: -shadowMargin,
                                  width: widget.width + shadowMargin * 2,
                                  height: widget.height + shadowMargin * 2,
                                  child: Opacity(
                                    opacity: press,
                                    child: pressedShadow,
                                  ),
                                ),
                                Transform(
                                  key: const ValueKey(
                                    'transport_surface_transform',
                                  ),
                                  transform: layer(1.5, .035),
                                  alignment: Alignment.center,
                                  child: surface,
                                ),
                                Transform(
                                  key: const ValueKey(
                                    'transport_foreground_transform',
                                  ),
                                  transform: layer(4, .0385),
                                  alignment: Alignment.center,
                                  child: glyph,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    
                    Material(
                      color: Colors.transparent,
                      shape: shape,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: widget.onPressed,
                        onTapCancel: _release,
                        customBorder: shape,
                        hoverColor: widget.foreground.withValues(alpha: .08),
                        focusColor: widget.foreground.withValues(alpha: .12),
                        highlightColor: widget.foreground.withValues(
                          alpha: .12,
                        ),
                        splashColor: widget.foreground.withValues(alpha: .12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
