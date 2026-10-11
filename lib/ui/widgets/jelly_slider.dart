import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../animations/jelly_slider_motion.dart';
import '../../core/app_state.dart';
import 'settings_control_shape.dart';



class JellySlider extends StatefulWidget {
  final Key sliderKey;
  final double value, min, max;
  final int? divisions;
  final String label;
  final String Function(double) semanticFormatterCallback;
  final ValueChanged<double>? onChanged, onChangeEnd;
  const JellySlider({
    super.key,
    required this.sliderKey,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.label,
    required this.semanticFormatterCallback,
    required this.onChanged,
    this.onChangeEnd,
  });
  @override
  State<JellySlider> createState() => _JellySliderState();
}

class _JellySliderState extends State<JellySlider>
    with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _stretch = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _lean = AnimationController.unbounded(
    vsync: this,
  );
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _onKeyEvent)
    ..addListener(_focusChanged);
  late final Listenable _motion = Listenable.merge([_press, _stretch, _lean]);
  late JellySliderThumbShape _shape = JellySliderThumbShape(
    _press,
    _stretch,
    lean: _lean,
    shapeKind: AppState.settingsNavigationShape,
  );
  late JellySliderTrackShape _track = JellySliderTrackShape(_shape);
  late JellySliderOverlayShape _overlay = JellySliderOverlayShape(_shape);
  int? _pointer;
  Offset _lastPosition = Offset.zero;
  Duration _lastTime = Duration.zero;
  double _velocity = 0;
  bool _reduceMotion = false;
  Timer? _pause;
  double? _lastEmittedValue;

  void _focusChanged() {
    if (mounted && widget.divisions != null) setState(() {});
  }

  void _target(
    AnimationController controller,
    double target, {
    SpringDescription spring = JellySliderMotion.returnSpring,
  }) {
    if (_reduceMotion) {
      controller.stop();
      controller.value = 0;
      return;
    }
    if (!controller.isAnimating && controller.value == target) return;
    controller.animateWith(
      JellySliderMotion.settle(
        controller.value,
        target,
        controller.isAnimating ? controller.velocity : 0,
        spring: spring,
      ),
    );
  }

  void _release() {
    _pause?.cancel();
    _pointer = null;
    _velocity = 0;
    _lastEmittedValue = null;
    _target(_press, 0);
    _target(_stretch, 0);
    _target(_lean, 0);
  }

  double _quantize(double value) {
    final clamped = value.clamp(widget.min, widget.max);
    final divisions = widget.divisions;
    if (divisions == null || widget.max <= widget.min) return clamped;
    final fraction = (clamped - widget.min) / (widget.max - widget.min);
    return widget.min +
        (fraction * divisions).round() / divisions * (widget.max - widget.min);
  }

  void _changed(double value) {
    final selected = _quantize(value);
    if (selected == (_lastEmittedValue ?? widget.value)) return;
    _lastEmittedValue = selected;
    widget.onChanged?.call(selected);
  }

  double get _step => (widget.max - widget.min) / (widget.divisions ?? 20);

  void _adjust(int direction) {
    if (widget.onChanged == null || widget.max <= widget.min) return;
    final selected = _quantize(widget.value + direction * _step);
    if (selected == widget.value) return;
    widget.onChanged!(selected);
    widget.onChangeEnd?.call(selected);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    
    
    if (widget.divisions == null ||
        widget.onChanged == null ||
        event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final key = event.logicalKey;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowRight => rtl ? -1 : 1,
      LogicalKeyboardKey.arrowLeft => rtl ? 1 : -1,
      LogicalKeyboardKey.arrowUp => 1,
      LogicalKeyboardKey.arrowDown => -1,
      _ => 0,
    };
    if (direction == 0) {
      return KeyEventResult.ignored;
    }
    _adjust(direction);
    return KeyEventResult.handled;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _press.stop();
      _stretch.stop();
      _lean.stop();
      _press.value = 0;
      _stretch.value = 0;
      _lean.value = 0;
      _pause?.cancel();
    }
  }

  @override
  void didUpdateWidget(covariant JellySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onChanged == null && oldWidget.onChanged != null) _release();
    if (_pointer == null) _lastEmittedValue = null;
  }

  @override
  void dispose() {
    _pause?.cancel();
    _press.dispose();
    _stretch.dispose();
    _lean.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (_shape.shapeKind != AppState.settingsNavigationShape ||
        _shape.brightness != brightness) {
      _shape = JellySliderThumbShape(
        _press,
        _stretch,
        lean: _lean,
        shapeKind: AppState.settingsNavigationShape,
        brightness: brightness,
      );
      _track = JellySliderTrackShape(_shape);
      _overlay = JellySliderOverlayShape(_shape);
    }
    final slider = Listener(
      onPointerDown: (event) {
        if (widget.onChanged == null ||
            widget.max <= widget.min ||
            _pointer != null ||
            event.buttons & kPrimaryButton == 0) {
          return;
        }
        _pointer = event.pointer;
        _lastPosition = event.localPosition;
        _lastTime = event.timeStamp;
        _velocity = 0;
        _lastEmittedValue = null;
        _pause?.cancel();
        _target(_press, 1, spring: JellySliderMotion.pressSpring);
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer || _reduceMotion) return;
        final seconds = (event.timeStamp - _lastTime).inMicroseconds / 1000000;
        _velocity = JellySliderMotion.filteredVelocity(
          _velocity,
          event.localPosition.dx - _lastPosition.dx,
          seconds,
        );
        _lastPosition = event.localPosition;
        _lastTime = event.timeStamp;
        
        
        _target(
          _stretch,
          JellySliderMotion.stretchForVelocity(_velocity).abs(),
          spring: JellySliderMotion.followSpring,
        );
        _target(
          _lean,
          JellySliderMotion.leanForVelocity(_velocity),
          spring: JellySliderMotion.followSpring,
        );
        _pause?.cancel();
        _pause = Timer(JellySliderMotion.pauseDelay, () {
          _velocity = 0;
          _target(_stretch, 0);
          _target(_lean, 0);
        });
      },
      onPointerUp: (event) {
        if (event.pointer == _pointer) _release();
      },
      onPointerCancel: (event) {
        if (event.pointer == _pointer) _release();
      },
      child: RepaintBoundary(
        child: _RepaintOnSliderMotion(
          motion: _motion,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              trackShape: _track,
              thumbShape: _shape,
              thumbSize: const WidgetStatePropertyAll(
                JellySliderThumbShape.baseSize,
              ),
              overlayShape: _overlay,
              tickMarkShape: SliderTickMarkShape.noTickMark,
              
              
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: SizedBox(
              height: 48,
              child: Slider(
                key: widget.sliderKey,
                focusNode: _focusNode,
                value: widget.value,
                min: widget.min,
                max: widget.max,
                
                
                divisions: null,
                label: widget.label,
                semanticFormatterCallback: widget.semanticFormatterCallback,
                onChangeStart: (_) => _lastEmittedValue = null,
                onChanged: widget.onChanged == null ? null : _changed,
                onChangeEnd: (value) {
                  _lastEmittedValue = null;
                  widget.onChangeEnd?.call(_quantize(value));
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.divisions == null) return slider;
    return Semantics(
      slider: true,
      enabled: widget.onChanged != null && widget.max > widget.min,
      focusable: widget.onChanged != null && widget.max > widget.min,
      focused: _focusNode.hasFocus,
      value: widget.semanticFormatterCallback(_quantize(widget.value)),
      increasedValue: widget.semanticFormatterCallback(
        _quantize(widget.value + _step),
      ),
      decreasedValue: widget.semanticFormatterCallback(
        _quantize(widget.value - _step),
      ),
      onIncrease: widget.onChanged != null && widget.value < widget.max
          ? () => _adjust(1)
          : null,
      onDecrease: widget.onChanged != null && widget.value > widget.min
          ? () => _adjust(-1)
          : null,
      child: ExcludeSemantics(child: slider),
    );
  }
}

class JellySliderThumbShape extends SliderComponentShape {
  static const baseSize = Size(32, 20);
  final Animation<double> press, stretch, lean;
  final MD3Shape shapeKind;
  final Brightness brightness;
  JellySliderThumbShape(
    this.press,
    this.stretch, {
    this.lean = const AlwaysStoppedAnimation(0),
    this.shapeKind = MD3Shape.roundedLarge,
    this.brightness = Brightness.light,
  });
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => baseSize;
  late final ShapeBorder outlineShape = SettingsControlShape.handleBorder(
    shapeKind,
    baseSize.height,
  );
  late final Rect _bounds = Rect.fromCenter(
    center: Offset.zero,
    width: baseSize.width,
    height: baseSize.height,
  );
  late final Path _outline = outlineShape.getOuterPath(_bounds);
  @visibleForTesting
  Offset? debugPaintCenter;
  double get widthScale =>
      (1 +
          press.value.clamp(-0.12, 1.15) * (JellySliderMotion.pressWidth - 1)) *
      (1 +
          stretch.value.clamp(-0.22, 1.12) *
              JellySliderMotion.maximumElongation);
  double get heightScale =>
      (1 +
          press.value.clamp(-0.12, 1.15) *
              (JellySliderMotion.pressHeight - 1)) *
      (1 -
          stretch.value.clamp(-0.22, 1.12) *
              JellySliderMotion.maximumCompression);
  double get shear =>
      lean.value.clamp(-1.12, 1.12) * JellySliderMotion.maximumShear;
  double get horizontalExtent =>
      baseSize.width * widthScale / 2 +
      baseSize.height * heightScale / 2 * shear.abs();

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    assert(() {
      debugPaintCenter = center;
      return true;
    }());
    final color =
        Color.lerp(
          sliderTheme.disabledThumbColor,
          sliderTheme.thumbColor,
          enableAnimation.value,
        ) ??
        const Color(0xFF6750A4);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.transform((Matrix4.identity()..setEntry(0, 1, -shear)).storage);
    canvas.scale(widthScale, heightScale);
    canvas.drawShadow(
      _outline,
      Colors.black.withValues(
        alpha:
            (brightness == Brightness.dark ? 0.18 : 0.10) *
            enableAnimation.value,
      ),
      0.5 + press.value.clamp(0.0, 1.0) * 0.5,
      true,
    );
    
    canvas.drawPath(_outline, Paint()..color = color);
    canvas.restore();
  }
}


class JellySliderOverlayShape extends SliderComponentShape {
  final JellySliderThumbShape thumb;
  JellySliderOverlayShape(this.thumb);
  static const size = Size(44, 40);
  late final Path _outline = thumb.outlineShape
      .scale(1.1)
      .getOuterPath(
        Rect.fromCenter(center: Offset.zero, width: 38, height: 26),
      );
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => size;
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = sliderTheme.overlayColor ?? Colors.transparent;
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.transform(
      (Matrix4.identity()..setEntry(0, 1, -thumb.shear)).storage,
    );
    canvas.scale(thumb.widthScale, thumb.heightScale);
    canvas.drawPath(
      _outline,
      Paint()
        ..color = color.withValues(
          alpha: color.a * activationAnimation.value * enableAnimation.value,
        ),
    );
    canvas.restore();
  }
}


class JellySliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  final JellySliderThumbShape thumb;
  JellySliderTrackShape(this.thumb);
  Color? _activeColor, _inactiveColor;
  final Paint _activePaint = Paint(), _inactivePaint = Paint();
  void _updateMaterial(Color active, Color inactive) {
    if (_activeColor == active && _inactiveColor == inactive) {
      return;
    }
    _activeColor = active;
    _inactiveColor = inactive;
    _activePaint.color = active;
    _inactivePaint.color = inactive;
  }

  @override
  bool get isRounded => true;
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;
    final active =
        Color.lerp(
          sliderTheme.disabledActiveTrackColor,
          sliderTheme.activeTrackColor,
          enableAnimation.value,
        ) ??
        Colors.transparent;
    final inactive =
        Color.lerp(
          sliderTheme.disabledInactiveTrackColor,
          sliderTheme.inactiveTrackColor,
          enableAnimation.value,
        ) ??
        Colors.transparent;
    _updateMaterial(active, inactive);
    final gap = thumb.horizontalExtent + 2;
    void segment(double left, double right, Paint paint) {
      if (right <= left) return;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, rect.top, right, rect.bottom),
          Radius.circular(rect.height / 2),
        ),
        paint,
      );
    }

    segment(
      rect.left,
      (thumbCenter.dx - gap).clamp(rect.left, rect.right),
      textDirection == TextDirection.ltr ? _activePaint : _inactivePaint,
    );
    segment(
      (thumbCenter.dx + gap).clamp(rect.left, rect.right),
      rect.right,
      textDirection == TextDirection.ltr ? _inactivePaint : _activePaint,
    );
  }
}

class _RepaintOnSliderMotion extends SingleChildRenderObjectWidget {
  final Listenable motion;
  const _RepaintOnSliderMotion({required this.motion, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SliderMotionPaint(motion);
}

class _SliderMotionPaint extends RenderProxyBox {
  final Listenable motion;
  _SliderMotionPaint(this.motion);
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    motion.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    motion.removeListener(markNeedsPaint);
    super.detach();
  }
}
