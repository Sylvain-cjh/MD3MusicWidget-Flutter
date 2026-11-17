import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'smoothRoundedClip.dart';

typedef OutputVolume = ({double level, bool muted});
typedef _VolumeFeedback = ({OutputVolume? volume});

class CoverVolumeControl extends StatefulWidget {
  final Widget child;
  final ColorScheme scheme;
  final BorderRadius borderRadius;
  final Future<OutputVolume?> Function(double)? adjustVolume;
  final bool enabled;
  final int stepPercent;

  const CoverVolumeControl({
    super.key,
    required this.child,
    required this.scheme,
    required this.borderRadius,
    this.adjustVolume,
    this.enabled = true,
    this.stepPercent = 3,
  });

  @override
  State<CoverVolumeControl> createState() => _CoverVolumeControlState();
}

class _CoverVolumeControlState extends State<CoverVolumeControl> {
  static const _channel = MethodChannel('md3_music_widget/system_volume');
  static const _hold = Duration(milliseconds: 1250);
  final _feedback = ValueNotifier<_VolumeFeedback?>(null);
  Timer? _hideTimer;
  double _pending = 0;
  double _wheelRemainder = 0;
  double _pendingWheelPixels = 0;
  double? _wheelPixelsPerNotch;
  bool _readingWheelScale = false;
  Size? _coverSize;
  Path? _coverHitPath;
  int _requestEpoch = 0;
  bool _busy = false;
  bool _focused = false;

  double get _step => widget.stepPercent.clamp(1, 15) / 100;

  @override
  void didUpdateWidget(covariant CoverVolumeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.borderRadius != oldWidget.borderRadius) _coverHitPath = null;
    if (!widget.enabled && oldWidget.enabled) {
      _requestEpoch++;
      _hideTimer?.cancel();
      _pending = _wheelRemainder = _pendingWheelPixels = 0;
      _feedback.value = null;
      _focused = false;
    }
  }

  Future<OutputVolume?> _adjustWindows(double delta) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'adjust',
      delta,
    );
    final level = result?['level'];
    if (level is! double || !level.isFinite) return null;
    return (level: level.clamp(0.0, 1.0), muted: result?['muted'] == true);
  }

  void _adjust(double delta) {
    if (!widget.enabled) return;
    _pending = (_pending + delta).clamp(-1.0, 1.0);
    _hideTimer?.cancel();
    if (!_busy) unawaited(_flush());
  }

  Future<void> _flush() async {
    _busy = true;
    while (mounted && widget.enabled && _pending != 0) {
      final delta = _pending;
      final epoch = _requestEpoch;
      _pending = 0;
      OutputVolume? result;
      try {
        result = await (widget.adjustVolume ?? _adjustWindows)(delta);
      } on PlatformException {
        result = null;
      } on MissingPluginException {
        result = null;
      }
      if (!mounted) break;
      if (!widget.enabled || epoch != _requestEpoch) continue;
      _feedback.value = (volume: result);
    }
    _busy = false;
    if (!mounted || !widget.enabled || _feedback.value == null) return;
    _hideTimer = Timer(_hold, () => _feedback.value = null);
  }

  void _applyWheelNotches(double notches) {
    _wheelRemainder = (_wheelRemainder + notches).clamp(-100.0, 100.0);
    
    
    final whole = (_wheelRemainder.abs() + 0.000001).floor();
    if (whole == 0) return;
    final signed = whole * _wheelRemainder.sign;
    _wheelRemainder -= signed;
    _adjust(signed * _step);
  }

  Future<void> _loadWheelScale() async {
    _readingWheelScale = true;
    double? units;
    try {
      units = await _channel.invokeMethod<double>('wheelUnitsPerNotch');
    } on PlatformException {
      units = null;
    } on MissingPluginException {
      units = null;
    }
    if (!mounted) return;
    _wheelPixelsPerNotch = units != null && units.isFinite && units > 0
        ? units
        : 100.0;
    _readingWheelScale = false;
    if (!widget.enabled) return;
    final pixels = _pendingWheelPixels;
    _pendingWheelPixels = 0;
    _applyWheelNotches(pixels / _wheelPixelsPerNotch!);
  }

  void _wheel(double logicalPixels) {
    if (!mounted || !widget.enabled) return;
    if (widget.adjustVolume != null) {
      _applyWheelNotches(logicalPixels / 120.0);
      return;
    }
    final physicalPixels = logicalPixels * View.of(context).devicePixelRatio;
    if (_wheelPixelsPerNotch case final scale?) {
      _applyWheelNotches(physicalPixels / scale);
    } else {
      _pendingWheelPixels += physicalPixels;
      if (!_readingWheelScale) unawaited(_loadWheelScale());
    }
  }

  void _onPointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent ||
        signal.kind != PointerDeviceKind.mouse) {
      return;
    }
    final vertical = signal.scrollDelta.dy;
    if (!vertical.isFinite ||
        vertical == 0 ||
        vertical.abs() < signal.scrollDelta.dx.abs()) {
      return;
    }
    final size = context.size;
    if (size != null) {
      if (_coverSize != size || _coverHitPath == null) {
        _coverSize = size;
        _coverHitPath = SmoothSurfaceCorners.shape(
          widget.borderRadius,
        ).getOuterPath(Offset.zero & size);
      }
      if (!_coverHitPath!.contains(signal.localPosition)) return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      signal,
      (_) => _wheel(-vertical),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && widget.adjustVolume == null) return widget.child;
    final scheme = widget.scheme;
    return FocusableActionDetector(
      enabled: widget.enabled,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
          TraversalDirection.up,
        ),
        SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
          TraversalDirection.down,
        ),
      },
      actions: {
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) {
            _adjust(intent.direction == TraversalDirection.up ? _step : -_step);
            return null;
          },
        ),
      },
      child: Semantics(
        label: widget.enabled ? '封面，滚轮或聚焦后按上下键调节系统音量' : null,
        onIncrease: widget.enabled ? () => _adjust(_step) : null,
        onDecrease: widget.enabled ? () => _adjust(-_step) : null,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerSignal: widget.enabled ? _onPointerSignal : null,
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              widget.child,
              if (widget.enabled && _focused)
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: SmoothSurfaceCorners.shape(
                        widget.borderRadius,
                        side: BorderSide(color: scheme.primary, width: 2),
                      ),
                    ),
                  ),
                ),
              if (widget.enabled)
                Positioned(
                  left: 7,
                  right: 7,
                  bottom: 7,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 194),
                        child: _VolumeHud(feedback: _feedback, scheme: scheme),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VolumeHud extends StatefulWidget {
  final ValueListenable<_VolumeFeedback?> feedback;
  final ColorScheme scheme;
  const _VolumeHud({required this.feedback, required this.scheme});

  @override
  State<_VolumeHud> createState() => _VolumeHudState();
}

class _VolumeHudState extends State<_VolumeHud>
    with SingleTickerProviderStateMixin {
  static const _enter = Duration(milliseconds: 110);
  static const _exit = Duration(milliseconds: 155);
  AnimationController? _presenceController;
  AnimationController get _presence =>
      _presenceController ??= _createPresence();

  AnimationController _createPresence() => AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.dismissed &&
          widget.feedback.value == null) {
        setState(() => _shown = null);
      }
    });
  _VolumeFeedback? _shown;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    widget.feedback.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduceMotion ||
        (_shown == null && widget.feedback.value != null)) {
      _reduceMotion = reduce;
      _sync();
    }
  }

  void _sync() {
    final next = widget.feedback.value;
    if (next == null) {
      if (_shown == null) return;
      if (_reduceMotion || _presence.value == 0) {
        _presence.value = 0;
        setState(() => _shown = null);
      } else {
        _presence.animateBack(0, duration: _exit, curve: Curves.easeInQuad);
      }
      return;
    }
    setState(() => _shown = next);
    if (_reduceMotion) {
      _presence.value = 1;
    } else if (_presence.value < 1 &&
        _presence.status != AnimationStatus.forward) {
      _presence.animateTo(
        1,
        duration: _enter,
        curve: const Cubic(.22, 1, .36, 1),
      );
    }
  }

  @override
  void dispose() {
    widget.feedback.removeListener(_sync);
    _presenceController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();
    return FadeTransition(
      opacity: _presence,
      child: AnimatedBuilder(
        animation: _presence,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, (1 - _presence.value) * 4),
          child: child,
        ),
        child: _VolumeBar(
          key: const ValueKey('cover-volume-bar'),
          volume: shown.volume,
          scheme: widget.scheme,
          reduceMotion: _reduceMotion,
        ),
      ),
    );
  }
}

class _VolumeBar extends StatelessWidget {
  final OutputVolume? volume;
  final ColorScheme scheme;
  final bool reduceMotion;

  const _VolumeBar({
    super.key,
    required this.volume,
    required this.scheme,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    final value = volume;
    final muted = value?.muted == true;
    final level = muted ? 0.0 : value?.level ?? 0.0;
    final text = value == null
        ? '音量不可用'
        : muted
        ? '静音'
        : '${(level * 100).round()}%';
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: scheme.onSurface,
      ),
    );
    return Semantics(
      liveRegion: true,
      label: value == null ? text : '系统音量 $text',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: SmoothSurfaceCorners.shape(
              SmoothSurfaceCorners.small,
              side: BorderSide(
                width: RoundedRasterScale.hairline(context),
                color: scheme.outlineVariant.withValues(alpha: 0.75),
              ),
            ),
            gradient: LinearGradient(
              colors: [
                scheme.surfaceContainerHigh.withValues(alpha: 0.96),
                Color.lerp(
                  scheme.surfaceContainerHigh,
                  scheme.primaryContainer,
                  0.32,
                )!.withValues(alpha: 0.97),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 76;
                final gap = compact ? 3.0 : 5.0;
                return Row(
                  children: [
                    Icon(
                      muted || value == null
                          ? Icons.volume_off_rounded
                          : level <= 0
                          ? Icons.volume_mute_rounded
                          : level < 0.45
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                      size: compact ? 12 : 15,
                      color: scheme.onSurface,
                    ),
                    SizedBox(width: gap),
                    if (value == null)
                      Flexible(child: label)
                    else ...[
                      Expanded(
                        child: RepaintBoundary(
                          child: SizedBox(
                            height: 4,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: level),
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 108),
                              curve: Curves.easeOutCubic,
                              builder: (_, level, _) => CustomPaint(
                                painter: _VolumeRail(
                                  level: level,
                                  fill: scheme.primary,
                                  track: scheme.outlineVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: gap),
                      SizedBox(
                        width: (constraints.maxWidth * .40).clamp(0.0, 36.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: label,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeRail extends CustomPainter {
  final double level;
  final Color fill;
  final Color track;
  const _VolumeRail({
    required this.level,
    required this.fill,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..color = track;
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      paint,
    );
    final width = (level * size.width).clamp(0.0, size.width);
    if (width <= 0) return;
    paint.color = fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, size.height), radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _VolumeRail oldDelegate) =>
      level != oldDelegate.level ||
      fill != oldDelegate.fill ||
      track != oldDelegate.track;
}
