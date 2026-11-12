import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/recoverableResource.dart';
import 'settingsGlassBackdrop.dart';



class LiquidSettingsSwitch extends StatefulWidget {
  const LiquidSettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.useGlass,
    required this.scheme,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool useGlass;
  final ColorScheme scheme;

  @override
  State<LiquidSettingsSwitch> createState() => _LiquidSettingsSwitchState();
}

class _LiquidSettingsSwitchState extends State<LiquidSettingsSwitch>
    with TickerProviderStateMixin {
  static final _program = RecoverableResource<ui.FragmentProgram>(
    load: () => ui.FragmentProgram.fromAsset('shaders/switchGlass.frag'),
  );
  late final AnimationController _position, _press, _pulse;
  late final _visual = Listenable.merge([_position, _press, _pulse]);
  ui.FragmentShader? _shader;
  int? _pointer;
  bool _loading = false;
  bool _focused = false;
  bool _reduce = false;
  bool _highContrast = false;
  double _grabX = 0, _grabPosition = 0;

  bool get _glass => widget.useGlass && !_highContrast;
  bool get _active => _glass && widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _position = AnimationController(vsync: this, value: widget.value ? 1 : 0);
    _press = AnimationController(vsync: this);
    _pulse = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _highContrast = MediaQuery.highContrastOf(context);
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (!_active && _pointer != null) _end();
    if (!_active || _reduce) _pulse.value = 0;
    if (_glass) unawaited(_prepareShader());
  }

  Future<void> _prepareShader() async {
    if (_shader != null || _loading) return;
    _loading = true;
    final program = await _program.get();
    _loading = false;
    if (!mounted || program == null || !_glass) return;
    
    setState(() => _shader = program.fragmentShader());
  }

  @override
  void didUpdateWidget(covariant LiquidSettingsSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_active && _pointer != null) _end();
    if (oldWidget.value != widget.value ||
        oldWidget.useGlass != widget.useGlass) {
      if (_pointer == null) _settle();
    }
    if (_active && !_reduce && oldWidget.value != widget.value) {
      
      
      _pulse.value = 1;
      _pulse.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: const Interval(.22, 1, curve: Curves.easeInOutCubic),
      );
    } else if (!_active) {
      _pulse.value = 0;
    }
    if (_glass) unawaited(_prepareShader());
  }

  void _settle() {
    final target = widget.value ? 1.0 : 0.0;
    if (_reduce || !_active) {
      _position.value = target;
      return;
    }
    _position.animateTo(
      target,
      duration: const Duration(milliseconds: 195),
      curve: Curves.easeOutCubic,
    );
  }

  void _end() {
    _pointer = null;
    if (_reduce || !_active) {
      _press.value = 0;
    } else {
      _press.animateTo(
        0,
        duration: const Duration(milliseconds: 165),
        curve: Curves.easeOutCubic,
      );
    }
    _settle();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final glass = _glass;
    final backdrop = glass ? SettingsGlassBackdrop.of(context) : null;
    final scroll = backdrop != null
        ? Scrollable.maybeOf(context)?.position
        : null;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final scheme = widget.scheme;
    const invisible = WidgetStatePropertyAll(Colors.transparent);
    return Listener(
      onPointerDown: active
          ? (event) {
              if (_pointer != null || event.buttons & kPrimaryButton == 0) {
                return;
              }
              _pointer = event.pointer;
              _grabX = event.localPosition.dx;
              _grabPosition = _position.value;
              _position.stop();
              if (_reduce) {
                _press.value = 1;
              } else {
                _press.value = math.max(_press.value, .26);
                _press.animateTo(
                  1,
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOutCubic,
                );
              }
              unawaited(_prepareShader());
            }
          : null,
      onPointerMove: active
          ? (event) {
              if (_pointer != event.pointer) return;
              final dx = (event.localPosition.dx - _grabX) * (rtl ? -1 : 1);
              _position.value = (_grabPosition + dx / _SwitchSkin.travel).clamp(
                0.0,
                1.0,
              );
            }
          : null,
      onPointerUp: (event) {
        if (_pointer == event.pointer) _end();
      },
      onPointerCancel: (event) {
        if (_pointer == event.pointer) _end();
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (glass)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const ValueKey('settings_liquid_switch_surface'),
                      painter: _SwitchSkin(
                        _position,
                        _press,
                        _pulse,
                        scroll == null
                            ? _visual
                            : Listenable.merge([_visual, scroll]),
                        _shader,
                        backdrop,
                        () => mounted ? this.context.findRenderObject() : null,
                        scheme,
                        rtl,
                        _reduce,
                        _focused,
                        widget.onChanged != null,
                      ),
                    ),
                  ),
                ),
              ),
            
            
            Opacity(
              key: const ValueKey('settings_switch_input_layer'),
              opacity: glass ? 0 : 1,
              alwaysIncludeSemantics: true,
              child: Switch(
                key: const ValueKey('settings_switch_input'),
                value: widget.value,
                onChanged: widget.onChanged,
                dragStartBehavior: active
                    ? DragStartBehavior.down
                    : DragStartBehavior.start,
                activeThumbColor: scheme.onPrimary,
                activeTrackColor: scheme.primary,
                trackOutlineColor: invisible,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _position.dispose();
    _press.dispose();
    _pulse.dispose();
    _shader?.dispose();
    super.dispose();
  }
}

class _SwitchSkin extends CustomPainter {
  _SwitchSkin(
    this.position,
    this.press,
    this.pulse,
    Listenable repaint,
    this.shader,
    this.backdrop,
    this.findControl,
    this.scheme,
    this.rtl,
    this.reduced,
    this.focused,
    this.enabled,
  ) : super(repaint: repaint);

  static const travel = 20.0;
  static final ui.Image _fallbackSampler = _makeFallbackSampler();

  static ui.Image _makeFallbackSampler() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.black, BlendMode.src);
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(1, 1);
    } finally {
      picture.dispose();
    }
  }

  final Animation<double> position, press, pulse;
  final ui.FragmentShader? shader;
  final SettingsGlassSample? backdrop;
  final RenderObject? Function() findControl;
  final ColorScheme scheme;
  final bool rtl, reduced, focused, enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final value = position.value;
    final energy = math.max(press.value, pulse.value);
    final lift = reduced ? 0.0 : energy;
    final center = size.center(Offset.zero);
    final track = Rect.fromCenter(center: center, width: 52, height: 30);
    final start = rtl ? 1 - value : value;
    final thumb = Rect.fromCenter(
      center: center + Offset((start - .5) * travel, 0),
      width: 28 + lift * 4,
      height: 22 + lift * 5,
    );
    final tint = Color.lerp(
      scheme.surfaceContainerHighest,
      scheme.primary,
      value,
    )!;
    final trackColor = enabled ? tint : Color.lerp(tint, scheme.surface, .60)!;
    final neutral = Color.lerp(
      scheme.onSurfaceVariant,
      scheme.onPrimary,
      value,
    )!;
    final knobColor = enabled
        ? neutral
        : Color.lerp(neutral, scheme.surfaceContainerHighest, .60)!;
    final trackShape = RRect.fromRectAndRadius(
      track,
      const Radius.circular(15),
    );
    final knob = RRect.fromRectAndRadius(
      thumb,
      Radius.circular(thumb.height / 2),
    );
    if (focused) {
      canvas.drawRRect(
        trackShape.inflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.35
          ..color = scheme.primary,
      );
    }
    final lens = shader;
    if (lens == null) {
      canvas.drawRRect(
        trackShape,
        Paint()
          ..shader = ui.Gradient.linear(track.topCenter, track.bottomCenter, [
            Color.lerp(trackColor, scheme.surface, .34)!,
            trackColor,
          ]),
      );
      canvas.drawRRect(
        knob.shift(const Offset(0, 1)),
        Paint()..color = scheme.shadow.withValues(alpha: .18),
      );
      canvas.drawRRect(
        knob,
        Paint()
          ..shader = ui.Gradient.linear(
            thumb.topCenter,
            thumb.bottomCenter,
            [
              Color.lerp(trackColor, knobColor, .60)!,
              Color.lerp(trackColor, knobColor, .30)!,
              Color.lerp(trackColor, knobColor, .52)!,
            ],
            const [0, .63, 1],
          ),
      );
      canvas.drawRRect(
        knob.deflate(.55),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .9
          ..shader = ui.Gradient.linear(
            thumb.topLeft,
            thumb.bottomRight,
            [
              Colors.white.withValues(alpha: .28 + energy * .30),
              Colors.transparent,
              Colors.black.withValues(alpha: .12 + energy * .10),
            ],
            const [0, .54, 1],
          ),
      );
      return;
    }
    final surrounding = scheme.surfaceContainerLow;
    final sample = backdrop;
    final sampleUv = sample?.uvFor(findControl(), size);
    final uv = sampleUv ?? Rect.zero;
    lens
      ..setFloat(0, track.left)
      ..setFloat(1, track.top)
      ..setFloat(2, track.width)
      ..setFloat(3, track.height)
      ..setFloat(4, thumb.left)
      ..setFloat(5, thumb.top)
      ..setFloat(6, thumb.width)
      ..setFloat(7, thumb.height)
      ..setFloat(8, trackColor.r)
      ..setFloat(9, trackColor.g)
      ..setFloat(10, trackColor.b)
      ..setFloat(11, surrounding.r)
      ..setFloat(12, surrounding.g)
      ..setFloat(13, surrounding.b)
      ..setFloat(14, knobColor.r)
      ..setFloat(15, knobColor.g)
      ..setFloat(16, knobColor.b)
      ..setFloat(17, energy)
      ..setFloat(18, uv.left)
      ..setFloat(19, uv.top)
      ..setFloat(20, uv.width)
      ..setFloat(21, uv.height)
      ..setFloat(22, sampleUv == null ? 0 : (enabled ? 1 : .62))
      ..setFloat(23, size.width)
      ..setFloat(24, size.height)
      ..setFloat(25, value)
      ..setImageSampler(0, sample?.image ?? _fallbackSampler);
    canvas.drawPath(
      Path()
        ..addRRect(trackShape)
        ..addRRect(knob),
      Paint()..shader = lens,
    );
  }

  @override
  bool shouldRepaint(_SwitchSkin old) =>
      old.shader != shader ||
      old.backdrop != backdrop ||
      old.scheme != scheme ||
      old.rtl != rtl ||
      old.reduced != reduced ||
      old.focused != focused ||
      old.enabled != enabled;
}
