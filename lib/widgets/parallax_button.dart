import 'package:flutter/material.dart';

class WpfParallaxItem extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final Color bgColor;
  final ImageProvider? bgImage;
  final Widget? foreground;
  final VoidCallback onTap;
  final bool showOverlay;

  final double hoverScale;
  final double bgParallaxMultiplier;
  final double fgParallaxMultiplier;
  final double tiltMultiplier;
  final Widget? customBgOverlay;

  final bool enable3D;
  final bool enableHover;

  const WpfParallaxItem({
    super.key,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.bgColor,
    this.bgImage,
    this.foreground,
    required this.onTap,
    this.showOverlay = true,
    this.hoverScale = 1.02,
    this.bgParallaxMultiplier = 1.5,
    this.fgParallaxMultiplier = 4.0,
    this.tiltMultiplier = 0.0,
    this.customBgOverlay,
    this.enable3D = false,
    this.enableHover = true,
  });

  @override
  State<WpfParallaxItem> createState() => _WpfParallaxItemState();
}

class _WpfParallaxItemState extends State<WpfParallaxItem> {
  bool _isHovered = false;
  bool _isPressed = false;
  Offset _mouseOffset = Offset.zero;

  bool get isH => _isHovered && widget.enableHover;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final overlayColor = isDark ? Colors.white : Colors.black;

    final int overlayAlpha = widget.showOverlay
        ? (_isPressed ? 31 : (isH ? 20 : 0))
        : 0;

    final double targetScale = _isPressed
        ? 0.95
        : (isH ? widget.hoverScale : 1.0);
    final Duration scaleDuration = _isPressed
        ? const Duration(milliseconds: 100)
        : const Duration(milliseconds: 300);
    final Curve scaleCurve = _isPressed
        ? Curves.easeOutQuad
        : Curves.easeOutCubic;

    final double bgOffsetX = isH
        ? _mouseOffset.dx * widget.bgParallaxMultiplier
        : 0.0;
    final double bgOffsetY = isH
        ? _mouseOffset.dy * widget.bgParallaxMultiplier
        : 0.0;
    final double fgOffsetX = isH
        ? _mouseOffset.dx * widget.fgParallaxMultiplier
        : 0.0;
    final double fgOffsetY = isH
        ? _mouseOffset.dy * widget.fgParallaxMultiplier
        : 0.0;

    
    final double rotateX = isH ? _mouseOffset.dy * widget.tiltMultiplier : 0.0;
    final double rotateY = isH ? -_mouseOffset.dx * widget.tiltMultiplier : 0.0;

    final Matrix4 bgTransform = Matrix4.identity();
    if (widget.enable3D) bgTransform.setEntry(3, 2, 0.0015);
    bgTransform
      ..rotateX(widget.enable3D ? rotateX : 0)
      ..rotateY(widget.enable3D ? rotateY : 0)
      ..translateByDouble(bgOffsetX, bgOffsetY, 0.0, 1.0);

    final Matrix4 fgTransform = Matrix4.identity();
    if (widget.enable3D) fgTransform.setEntry(3, 2, 0.0015);
    fgTransform
      ..rotateX(widget.enable3D ? rotateX * 1.1 : 0)
      ..rotateY(widget.enable3D ? rotateY * 1.1 : 0)
      ..translateByDouble(fgOffsetX, fgOffsetY, 0.0, 1.0);

    final Duration parallaxDuration = isH
        ? const Duration(milliseconds: 80)
        : const Duration(milliseconds: 400);
    final Curve parallaxCurve = isH ? Curves.easeOutCubic : Curves.easeOutBack;

    final BoxShadow hoverShadow = widget.enable3D
        ? BoxShadow(
            color: Colors.black.withAlpha(76),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        : BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 10,
            offset: const Offset(0, 4),
          );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
        _mouseOffset = Offset.zero;
      }),
      onHover: (details) {
        final Offset nextOffset = Offset(
          (details.localPosition.dx - widget.width / 2) / (widget.width / 2),
          (details.localPosition.dy - widget.height / 2) / (widget.height / 2),
        );
        
        
        
        if ((nextOffset - _mouseOffset).distanceSquared < 0.000025) return;
        setState(() => _mouseOffset = nextOffset);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: targetScale,
          duration: scaleDuration,
          curve: scaleCurve,
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                
                RepaintBoundary(
                  child: AnimatedContainer(
                    duration: parallaxDuration,
                    curve: parallaxCurve,
                    transform: bgTransform,
                    transformAlignment: Alignment.center,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubicEmphasized,
                      width: widget.width,
                      height: widget.height,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: widget.borderRadius,
                        color: widget.bgColor,
                        image: widget.bgImage != null
                            ? DecorationImage(
                                image: widget.bgImage!,
                                fit: BoxFit.cover,
                              )
                            : null,
                        boxShadow: isH && !_isPressed
                            ? [hoverShadow]
                            : (_isPressed
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(26),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : []),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            color: overlayColor.withAlpha(overlayAlpha),
                          ),
                          if (widget.customBgOverlay != null)
                            widget.customBgOverlay!,
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.foreground != null)
                  
                  RepaintBoundary(
                    child: AnimatedContainer(
                      duration: parallaxDuration,
                      curve: parallaxCurve,
                      transform: fgTransform,
                      transformAlignment: Alignment.center,
                      child: widget.foreground!,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
