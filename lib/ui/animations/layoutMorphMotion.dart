import 'dart:math' as math;

import 'package:flutter/material.dart';



class LayoutMorphMotion extends ChangeNotifier {
  final AnimationController controller;
  final Curve curve;
  bool active = false, holding = false, trimRequested = false;
  bool freshBackdrop = false;
  bool towardVertical = true;
  int serial = 0;
  Rect beginFrame = Rect.zero, endFrame = Rect.zero;
  Rect stageBounds = Rect.zero, targetBounds = Rect.zero;
  Size canvas = Size.zero;

  LayoutMorphMotion({
    required TickerProvider vsync,
    required Duration duration,
    required this.curve,
  }) : controller = AnimationController(
         vsync: vsync,
         duration: duration,
         value: 1,
       ) {
    controller.addListener(notifyListeners);
  }

  double get progress => curve.transform(controller.value.clamp(0.0, 1.0));
  Rect get frame => geometry(beginFrame, endFrame, controller.value);

  Rect geometry(Rect begin, Rect end, double value, {bool cover = false}) {
    final t = value.clamp(0.0, 1.0);
    final x = towardVertical
        ? Curves.easeInOutCubic.transform(t)
        : Curves.easeOutCubic.transform((t * 2).clamp(0.0, 1.0));
    final y = towardVertical
        ? Curves.easeOutCubic.transform(t)
        : Curves.easeInOutCubic.transform(t);
    final artwork = towardVertical
        ? Curves.easeInOutCubic.transform(t)
        : Curves.easeOutQuart.transform(t);
    double mix(double a, double b, double p) => a + (b - a) * p;
    return Rect.fromLTWH(
      mix(begin.left, end.left, cover ? artwork : x),
      mix(begin.top, end.top, cover ? artwork : y),
      mix(begin.width, end.width, cover ? artwork : x),
      mix(begin.height, end.height, cover ? artwork : y),
    );
  }

  void freeze() {
    controller.stop(canceled: true);
    holding = true;
    freshBackdrop = false;
    notifyListeners();
  }

  void holdCapturedBackdrop() {
    freshBackdrop = true;
    notifyListeners();
  }

  void prepare({
    required Rect source,
    required Rect target,
    required Rect stage,
    required Rect nativeTarget,
    bool vertical = true,
  }) {
    towardVertical = vertical;
    beginFrame = source.shift(-stage.topLeft);
    endFrame = target.shift(-stage.topLeft);
    stageBounds = stage;
    targetBounds = nativeTarget;
    canvas = Size(
      math.max(source.width, target.width),
      math.max(source.height, target.height),
    );
    serial++;
    active = true;
    holding = false;
    trimRequested = false;
    freshBackdrop = false;
    controller.value = 0;
  }

  Future<bool> play({required bool reduced}) async {
    if (reduced) {
      controller.value = 1;
      return true;
    }
    try {
      await controller.forward(from: 0).orCancel;
      return true;
    } on TickerCanceled {
      return false;
    }
  }

  bool viewportIsTarget(Size viewport, double pixelRatio) {
    final tolerance = pixelRatio > 0 ? 1 / pixelRatio : 1.0;
    return (viewport.width - targetBounds.width).abs() <= tolerance &&
        (viewport.height - targetBounds.height).abs() <= tolerance;
  }

  Rect frameInViewport(Size viewport, double pixelRatio) {
    final current = frame;
    return trimRequested && viewportIsTarget(viewport, pixelRatio)
        ? current.shift(stageBounds.topLeft - targetBounds.topLeft)
        : current;
  }

  void requestTrim(Rect stage, Rect target) {
    stageBounds = stage;
    targetBounds = target;
    trimRequested = true;
    notifyListeners();
  }

  void finish() {
    controller.stop(canceled: true);
    active = holding = trimRequested = false;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(notifyListeners);
    controller.dispose();
    super.dispose();
  }
}



class MorphPositioned extends StatefulWidget {
  final double left, top, width, height;
  final Duration duration;
  final Curve curve;
  final LayoutMorphMotion? motion;
  final bool cover;
  final Widget child;
  const MorphPositioned({
    super.key,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.duration,
    required this.curve,
    this.motion,
    this.cover = false,
    required this.child,
  });
  Rect get rect => Rect.fromLTWH(left, top, width, height);
  @override
  State<MorphPositioned> createState() => _MorphPositionedState();
}

class _MorphPositionedState extends State<MorphPositioned>
    with SingleTickerProviderStateMixin {
  late final AnimationController _local = AnimationController(
    vsync: this,
    value: 1,
  );
  late Rect _begin = widget.rect, _end = widget.rect, _current = widget.rect;
  bool _shared = false;
  int _serial = -1;
  double _phaseStart = 0;

  @override
  void initState() {
    super.initState();
    widget.motion?.addListener(_changed);
    _local.addListener(_changed);
  }

  void _changed() {
    if (widget.motion?.holding == true && !_shared) _local.stop();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MorphPositioned oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion != widget.motion) {
      oldWidget.motion?.removeListener(_changed);
      widget.motion?.addListener(_changed);
    }
    final motion = widget.motion;
    final changedClock = motion?.active == true && _serial != motion!.serial;
    if (_end == widget.rect && !changedClock) return;
    _begin = _current;
    _end = widget.rect;
    _shared = motion?.active == true;
    if (_shared) {
      _serial = motion!.serial;
      _phaseStart = changedClock ? 0 : motion.controller.value;
      _local.stop();
    } else if (widget.duration == Duration.zero ||
        MediaQuery.disableAnimationsOf(context)) {
      _local.value = 1;
      _current = _end;
    } else {
      _local.duration = widget.duration;
      _local.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _shared
        ? ((widget.motion!.controller.value - _phaseStart) /
                  (1 - _phaseStart).clamp(.000001, 1.0))
              .clamp(0.0, 1.0)
        : widget.curve.transform(_local.value);
    _current = _shared
        ? widget.motion!.geometry(_begin, _end, p, cover: widget.cover)
        : Rect.lerp(_begin, _end, p)!;
    return Positioned(
      left: _current.left,
      top: _current.top,
      width: _current.width,
      height: _current.height,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    widget.motion?.removeListener(_changed);
    _local.removeListener(_changed);
    _local.dispose();
    super.dispose();
  }
}

class MorphTextStyle extends StatefulWidget {
  final TextStyle style;
  final LayoutMorphMotion? motion;
  final Widget Function(TextStyle) builder;
  const MorphTextStyle({
    super.key,
    required this.style,
    this.motion,
    required this.builder,
  });
  @override
  State<MorphTextStyle> createState() => _MorphTextStyleState();
}

class _MorphTextStyleState extends State<MorphTextStyle> {
  late TextStyle _begin = widget.style, _current = widget.style;
  int _serial = -1;
  double _start = 0;
  @override
  void initState() {
    super.initState();
    widget.motion?.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MorphTextStyle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion != widget.motion) {
      oldWidget.motion?.removeListener(_changed);
      widget.motion?.addListener(_changed);
    }
    final motion = widget.motion;
    if (motion != null &&
        motion.active &&
        (oldWidget.style != widget.style || _serial != motion.serial)) {
      _begin = _current;
      _start = _serial != motion.serial ? 0 : motion.progress;
      _serial = motion.serial;
    } else if (motion?.active != true) {
      _begin = _current = widget.style;
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = widget.motion;
    final p = motion?.active == true
        ? ((motion!.progress - _start) / (1 - _start).clamp(.000001, 1.0))
              .clamp(0.0, 1.0)
        : 1.0;
    _current = TextStyle.lerp(_begin, widget.style, p)!;
    return widget.builder(_current);
  }

  @override
  void dispose() {
    widget.motion?.removeListener(_changed);
    super.dispose();
  }
}
