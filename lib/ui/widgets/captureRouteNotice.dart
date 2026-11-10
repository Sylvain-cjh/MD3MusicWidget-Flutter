import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/appState.dart';
import '../../core/mediaProvider.dart';
import 'smoothRoundedClip.dart';

class CaptureRouteNotice extends StatefulWidget {
  const CaptureRouteNotice({
    super.key,
    required this.route,
    this.compact = false,
  });

  final MediaCaptureRoute route;
  final bool compact;
  static const height = 20.0;
  static const visibleFor = Duration(milliseconds: 2400);
  static const message = 'UIA 备用采集';
  static const compactMessage = 'UIA 备用';

  @override
  State<CaptureRouteNotice> createState() => _CaptureRouteNoticeState();
}

class _CaptureRouteNoticeState extends State<CaptureRouteNotice> {
  Timer? _timeout;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    if (widget.route.usesUiAutomation) _show();
  }

  @override
  void didUpdateWidget(CaptureRouteNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route.usesUiAutomation == widget.route.usesUiAutomation) {
      return;
    }
    if (widget.route.usesUiAutomation) {
      _show();
    } else {
      _timeout?.cancel();
      _visible = false;
    }
  }

  void _show() {
    _timeout?.cancel();
    _visible = true;
    _timeout = Timer(CaptureRouteNotice.visibleFor, () {
      setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: Semantics(
        liveRegion: _visible,
        label: _visible ? '网易云音乐：已启用 UI Automation 备用采集' : null,
        excludeSemantics: true,
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          reverseDuration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 140),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: reduceMotion
                ? child
                : SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.14),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
          ),
          child: !_visible
              ? null
              : Builder(
                  key: const ValueKey('capture_route_notice'),
                  builder: _buildSurface,
                ),
        ),
      ),
    );
  }

  Widget _buildSurface(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = colors.tertiaryContainer;
    final foreground = _legibleOn(background, colors.onTertiaryContainer);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: StadiumBorder(
          side: BorderSide(
            color: foreground.withValues(alpha: 0.20),
            width: RoundedRasterScale.hairline(context),
          ),
        ),
        shadows: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.12),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 4 : 8,
          vertical: 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.compact) ...[
              SizedBox.square(
                dimension: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: foreground,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                widget.compact
                    ? CaptureRouteNotice.compactMessage
                    : CaptureRouteNotice.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: widget.compact ? 10 : 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppState.effectiveGlobalFontFamily,
                  fontFamilyFallback: AppState.textFontFallback,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  
  
  static Color _legibleOn(Color fill, Color onFill) {
    final surface = fill.computeLuminance();
    final ink = onFill.computeLuminance();
    final lighter = surface > ink ? surface : ink;
    final darker = surface > ink ? ink : surface;
    if ((lighter + .05) / (darker + .05) >= 4.5) return onFill;
    return (surface + .05) / .05 >= 1.05 / (surface + .05)
        ? Colors.black
        : Colors.white;
  }
}
