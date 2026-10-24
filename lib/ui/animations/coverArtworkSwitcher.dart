import 'package:flutter/material.dart';

import '../../core/appState.dart';
import 'coverContentTransition.dart';
import 'coverMotionFrame.dart';

class CoverArtworkSwitcher extends StatefulWidget {
  final CoverTransitionStyle style;
  final int direction;
  final bool reduceMotion;
  final BorderRadius borderRadius;
  final Widget child;
  final StackFit fit;

  const CoverArtworkSwitcher({
    super.key,
    required this.style,
    required this.direction,
    required this.reduceMotion,
    required this.borderRadius,
    required this.child,
    this.fit = StackFit.loose,
  });

  @override
  State<CoverArtworkSwitcher> createState() => _CoverArtworkSwitcherState();
}

class _CoverEntry {
  final int id;
  Widget child;
  CoverTransitionStyle style;
  int direction;
  CoverMotionFrame frame = const CoverMotionFrame();
  CoverMotionFrame source = const CoverMotionFrame();
  _CoverEntry(this.id, this.child, this.style, this.direction);
}

class _CoverArtworkSwitcherState extends State<CoverArtworkSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late _CoverEntry _current;
  final List<_CoverEntry> _previous = [];
  var _serial = 0;
  late CoverTransitionStyle _style;
  late int _direction;

  @override
  void initState() {
    super.initState();
    _style = widget.style;
    _direction = widget.direction;
    _current = _CoverEntry(_serial++, widget.child, _style, _direction);
    _controller = AnimationController(vsync: this, value: 1)
      ..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || _previous.isEmpty) {
      return;
    }
    setState(_previous.clear);
  }

  @override
  void didUpdateWidget(covariant CoverArtworkSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Widget.canUpdate(_current.child, widget.child)) {
      _current.child = widget.child;
      if (!_controller.isAnimating) _current.style = widget.style;
      if (widget.reduceMotion &&
          !oldWidget.reduceMotion &&
          _controller.isAnimating) {
        _controller.value = 1;
      }
      return;
    }
    for (final entry in [..._previous, _current]) {
      entry.source = entry.frame;
    }
    _previous.add(_current);
    
    if (_previous.length > 3) _previous.removeAt(0);
    _style = widget.style;
    _direction = widget.direction;
    _current = _CoverEntry(_serial++, widget.child, _style, _direction);
    final duration = CoverMotionGeometry.durationFor(
      _style,
      _direction,
      widget.reduceMotion,
    );
    _controller.stop();
    if (duration == Duration.zero) {
      _previous.clear();
      _controller.value = 1;
    } else {
      _controller.duration = duration;
      _controller.forward(from: 0);
    }
  }

  CoverMotionFrame _exitFrame(_CoverEntry entry, double progress) {
    final effective = widget.reduceMotion ? CoverTransitionStyle.fade : _style;
    final target = CoverMotionGeometry.frameFor(
      entry.style,
      _direction,
      0,
      exiting: true,
    );
    var opacity = entry.source.opacity * (1 - progress);
    if (effective == CoverTransitionStyle.softSlide) {
      opacity =
          entry.source.opacity *
          CoverMotionGeometry.softSlideOldOpacity(_direction, progress);
    } else if (effective == CoverTransitionStyle.filmHorizontal ||
        effective == CoverTransitionStyle.filmVertical) {
      opacity = entry.source.opacity;
    } else if (effective == CoverTransitionStyle.flipHorizontal ||
        effective == CoverTransitionStyle.flipVertical) {
      opacity = entry.source.opacity * (1 - (progress * 2).clamp(0.0, 1.0));
    }
    if (widget.reduceMotion) {
      return CoverMotionFrame(opacity: opacity);
    }
    if (entry.style == _style &&
        (effective == CoverTransitionStyle.flipHorizontal ||
            effective == CoverTransitionStyle.flipVertical)) {
      final phase = (progress * 2).clamp(0.0, 1.0);
      return entry.source.towards(target, phase, opacity: opacity);
    }
    return entry.source.towards(target, progress, opacity: opacity);
  }

  Widget _view(_CoverEntry entry, bool exiting) => KeyedSubtree(
    key: ValueKey('cover_entry_${entry.id}'),
    child: CoverContentTransition(
      style: entry.style,
      animation: _controller,
      direction: entry.direction,
      borderRadius: widget.borderRadius,
      reduceMotion: widget.reduceMotion,
      frameOverride: entry.frame,
      exitingOverride: exiting,
      child: entry.child,
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final effective = widget.reduceMotion
          ? CoverTransitionStyle.fade
          : _style;
      final progress = widget.reduceMotion
          ? _controller.value
          : CoverMotionGeometry.progressFor(
              _style,
              _direction,
              _controller.value,
            );
      _current.frame = CoverMotionGeometry.frameFor(
        effective,
        _direction,
        progress,
        exiting: false,
      );
      for (final entry in _previous) {
        entry.frame = _exitFrame(entry, progress);
      }
      final current = _view(_current, false);
      final previous = [for (final entry in _previous) _view(entry, true)];
      final behind =
          _style == CoverTransitionStyle.softSlide &&
          _direction < 0 &&
          !widget.reduceMotion &&
          progress < 1;
      return ClipPath(
        clipper: CoverShadowViewportClipper(widget.borderRadius, progress),
        clipBehavior: _controller.isAnimating && !widget.reduceMotion
            ? Clip.antiAliasWithSaveLayer
            : Clip.none,
        child: Stack(
          key: const ValueKey('cover_layer_stack'),
          fit: widget.fit,
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: behind ? [current, ...previous] : [...previous, current],
        ),
      );
    },
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}



class CoverShadowViewportClipper extends CustomClipper<Path> {
  final BorderRadius radius;
  final double progress;
  const CoverShadowViewportClipper(this.radius, this.progress);

  @override
  Path getClip(Size size) {
    final reveal = const Interval(
      0.82,
      0.96,
      curve: Curves.easeOutCubic,
    ).transform(progress);
    final overflow = (size.shortestSide * .065).clamp(4.0, 12.0);
    final margin =
        overflow + (size.shortestSide * 0.12 + 24 - overflow) * reveal;
    return Path()
      ..addRRect(radius.toRRect((Offset.zero & size).inflate(margin)));
  }

  @override
  bool shouldReclip(covariant CoverShadowViewportClipper old) =>
      old.radius != radius || old.progress != progress;
}
