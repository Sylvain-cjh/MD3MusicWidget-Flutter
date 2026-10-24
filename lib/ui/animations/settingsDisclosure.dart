import 'package:flutter/material.dart';
import 'mediaMotionTokens.dart';



class SettingsDisclosure extends StatefulWidget {
  final bool open;
  final Axis axis;
  final bool fromLeft;
  final Widget child;
  final ValueChanged<bool>? onSettled;
  const SettingsDisclosure({
    super.key,
    required this.open,
    required this.axis,
    this.fromLeft = false,
    required this.child,
    this.onSettled,
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
  bool _initialized = false;
  int _generation = 0;
  void _update() {
    final generation = ++_generation;
    final open = widget.open;
    final target = widget.open ? 1.0 : 0.0;
    if (_reduced) {
      _progress.value = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) widget.onSettled?.call(open);
      });
    } else {
      _progress
          .animateTo(
            target,
            duration: MediaMotionTokens.settingsDisclosure,
            curve: MediaMotionTokens.settingsDisclosureCurve,
          )
          .orCancel
          .then(
            (_) {
              if (mounted && generation == _generation) {
                widget.onSettled?.call(open);
              }
            },
            onError: (Object error) {
              if (error is! TickerCanceled) {
                FlutterError.reportError(
                  FlutterErrorDetails(
                    exception: error,
                    library: 'settings disclosure',
                  ),
                );
              }
            },
          );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (!_initialized || reduced != _reduced) {
      _initialized = true;
      _reduced = reduced;
      _update();
    }
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
