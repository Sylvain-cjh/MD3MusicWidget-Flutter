import 'package:flutter/material.dart';
import 'media_motion_tokens.dart';



class SettingsDisclosure extends StatefulWidget {
  final bool open;
  final Axis axis;
  final bool fromLeft;
  final Widget child;
  const SettingsDisclosure({
    super.key,
    required this.open,
    required this.axis,
    this.fromLeft = false,
    required this.child,
  });
  @override
  State<SettingsDisclosure> createState() => _SettingsDisclosureState();
}

class _SettingsDisclosureState extends State<SettingsDisclosure>
    with SingleTickerProviderStateMixin {
  late final _progress = AnimationController(
    vsync: this,
    value: widget.open ? 1 : 0,
  );
  bool _reduced = false;
  void _update() {
    final target = widget.open ? 1.0 : 0.0;
    if (_reduced) {
      _progress.value = target;
    } else {
      _progress.animateTo(
        target,
        duration: MediaMotionTokens.settingsDisclosure,
        curve: MediaMotionTokens.settingsDisclosureCurve,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _update();
  }

  @override
  void didUpdateWidget(SettingsDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) _update();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: !widget.open,
    child: ExcludeFocus(
      excluding: !widget.open,
      child: IgnorePointer(
        ignoring: !widget.open,
        child: AnimatedBuilder(
          animation: _progress,
          child: widget.child,
          builder: (context, child) {
            final delta = _reduced ? 0.0 : 18 * (1 - _progress.value);
            return TickerMode(
              enabled: widget.open || _progress.isAnimating,
              child: ClipRect(
                child: Opacity(
                  opacity: _progress.value,
                  child: Transform.translate(
                    offset: widget.axis == Axis.vertical
                        ? Offset(0, delta)
                        : Offset(widget.fromLeft ? -delta : delta, 0),
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }
}
