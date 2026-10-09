import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../animations/jelly_slider_motion.dart';
import '../animations/settings_navigation_motion.dart';
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
  late final Listenable _motion = Listenable.merge([_press, _stretch]);
  late JellySliderThumbShape _shape = JellySliderThumbShape(
    _press,
    _stretch,
    shapeKind: AppState.settingsNavigationShape,
  );
  late JellySliderTrackShape _track = JellySliderTrackShape(_shape);
  int? _pointer;
  Offset _lastPosition = Offset.zero;
  Duration _lastTime = Duration.zero;
  double _velocity = 0;
  bool _reduceMotion = false;
  Timer? _pause;

  void _target(AnimationController controller, double target) {
    if (_reduceMotion) {
      controller.stop();
      controller.value = 0;
      return;
    }
    controller.animateWith(
      JellySliderMotion.settle(
        controller.value,
        target,
        controller.isAnimating ? controller.velocity : 0,
      ),
    );
  }

  void _release() {
    _pause?.cancel();
    _pointer = null;
    _velocity = 0;
    _target(_press, 0);
    _target(_stretch, 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _press.stop();
      _stretch.stop();
      _press.value = 0;
      _stretch.value = 0;
      _pause?.cancel();
    }
  }

  @override
  void didUpdateWidget(covariant JellySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onChanged == null && oldWidget.onChanged != null) _release();
  }

  @override
  void dispose() {
    _pause?.cancel();
    _press.dispose();
    _stretch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shape.shapeKind != AppState.settingsNavigationShape) {
      _shape = JellySliderThumbShape(
        _press,
        _stretch,
        shapeKind: AppState.settingsNavigationShape,
      );
      _track = JellySliderTrackShape(_shape);
    }
    return Listener(
      onPointerDown: (event) {
        if (widget.onChanged == null ||
            _pointer != null ||
            event.buttons & kPrimaryButton == 0) {
          return;
        }
        _pointer = event.pointer;
        _lastPosition = event.localPosition;
        _lastTime = event.timeStamp;
        _velocity = 0;
        _pause?.cancel();
        _target(_press, 1);
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer || _reduceMotion) return;
        final seconds = (event.timeStamp - _lastTime).inMicroseconds / 1000000;
        final dt = seconds > 0 ? seconds : 1 / 120;
        final speed = ((event.localPosition.dx - _lastPosition.dx) / dt).clamp(
          -3000.0,
          3000.0,
        );
        _velocity = _velocity * 0.35 + speed * 0.65;
        _lastPosition = event.localPosition;
        _lastTime = event.timeStamp;
        _target(_stretch, JellySliderMotion.stretchForVelocity(_velocity));
        _pause?.cancel();
        _pause = Timer(
          JellySliderMotion.pauseDelay,
          () => _target(_stretch, 0),
        );
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
              trackHeight: 8,
              trackShape: _track,
              thumbShape: _shape,
              thumbSize: const WidgetStatePropertyAll(
                JellySliderThumbShape.baseSize,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              tickMarkShape: widget.divisions == null
                  ? null
                  : SliderTickMarkShape.noTickMark,
            ),
            child: SizedBox(
              height: 48,
              child: Slider(
                key: widget.sliderKey,
                value: widget.value,
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                label: widget.label,
                semanticFormatterCallback: widget.semanticFormatterCallback,
                onChanged: widget.onChanged,
                onChangeEnd: widget.onChangeEnd,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JellySliderThumbShape extends SliderComponentShape {
  static const baseSize = Size(44, 28);
  final Animation<double> press, stretch;
  final MD3Shape shapeKind;
  JellySliderThumbShape(
    this.press,
    this.stretch, {
    this.shapeKind = MD3Shape.roundedLarge,
  });
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => baseSize;
  ShapeBorder get outlineShape =>
      SettingsControlShape.handleBorder(shapeKind, baseSize.height);
  double get widthScale =>
      (1 +
          press.value.clamp(-0.12, 1.15) *
              (SettingsNavigationMotion.pressScale - 1)) *
      (1 + stretch.value.abs().clamp(0.0, 1.15) * 0.18);
  double get heightScale =>
      (1 +
          press.value.clamp(-0.12, 1.15) *
              (SettingsNavigationMotion.pressVerticalScale - 1)) *
      (1 - stretch.value.abs().clamp(0.0, 1.15) * 0.18 * 0.25);
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
    canvas.scale(widthScale, heightScale);
    final outline = outlineShape.getOuterPath(
      Rect.fromCenter(
        center: Offset.zero,
        width: baseSize.width,
        height: baseSize.height,
      ),
      textDirection: textDirection,
    );
    canvas.drawShadow(
      outline,
      Colors.black.withValues(alpha: 0.16 * enableAnimation.value),
      1.5,
      true,
    );
    final bounds = Rect.fromCenter(
      center: Offset.zero,
      width: baseSize.width,
      height: baseSize.height,
    );
    
    
    canvas.drawPath(
      outline,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: 0.30),
              color.withValues(alpha: 0.62),
            ),
            color.withValues(alpha: 0.42),
            color.withValues(alpha: 0.72),
          ],
          stops: const [0, 0.52, 1],
        ).createShader(bounds),
    );
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.78),
            color.withValues(alpha: 0.24),
          ],
        ).createShader(bounds),
    );
    canvas.restore();
  }
}



class JellySliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  final JellySliderThumbShape thumb;
  JellySliderTrackShape(this.thumb);
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
    final gap = JellySliderThumbShape.baseSize.width * thumb.widthScale / 2 + 2;
    void segment(double left, double right, Color color) {
      if (right <= left) return;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, rect.top, right, rect.bottom),
          Radius.circular(rect.height / 2),
        ),
        Paint()..color = color,
      );
    }

    segment(
      rect.left,
      (thumbCenter.dx - gap).clamp(rect.left, rect.right),
      textDirection == TextDirection.ltr ? active : inactive,
    );
    segment(
      (thumbCenter.dx + gap).clamp(rect.left, rect.right),
      rect.right,
      textDirection == TextDirection.ltr ? inactive : active,
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
