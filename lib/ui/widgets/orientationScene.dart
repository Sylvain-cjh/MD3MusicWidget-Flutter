import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';



final class OrientationScene extends Stack {
  OrientationScene({
    super.key,
    required this.protectPlayer,
    required Widget settings,
    required Widget player,
  }) : super(clipBehavior: Clip.none, children: [settings, player]);

  final bool protectPlayer;

  @override
  RenderStack createRenderObject(BuildContext context) =>
      _RenderOrientationScene(
        protectPlayer,
        alignment: alignment,
        textDirection: textDirection ?? Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderStack renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _RenderOrientationScene).protectPlayer = protectPlayer;
  }
}

final class _RenderOrientationScene extends RenderStack {
  _RenderOrientationScene(
    this._protectPlayer, {
    required super.alignment,
    required super.textDirection,
  }) : super(clipBehavior: Clip.none);

  final _clip = LayerHandle<ClipPathLayer>();
  bool _protectPlayer;
  set protectPlayer(bool value) {
    if (_protectPlayer == value) return;
    _protectPlayer = value;
    markNeedsPaint();
  }

  Rect _box(RenderBox child) =>
      (child.parentData! as StackParentData).offset & child.size;

  @override
  void paintStack(PaintingContext context, Offset offset) {
    final settings = firstChild;
    final player = lastChild;
    if (!_protectPlayer || settings == null || player == null) {
      _clip.layer = null;
      super.paintStack(context, offset);
      return;
    }
    final settingsRect = _box(settings);
    final playerRect = _box(player);
    final overlap = settingsRect.intersect(playerRect);
    if (overlap.isEmpty) {
      _clip.layer = null;
      super.paintStack(context, offset);
      return;
    }
    final visible = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(settingsRect)
      ..addRect(overlap);
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      settingsRect,
      visible,
      (context, offset) =>
          context.paintChild(settings, offset + settingsRect.topLeft),
      clipBehavior: Clip.hardEdge,
      oldLayer: _clip.layer,
    );
    context.paintChild(player, offset + playerRect.topLeft);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final player = lastChild;
    if (_protectPlayer && player != null) {
      final playerRect = _box(player);
      if (playerRect.contains(position)) {
        return result.addWithPaintOffset(
          offset: playerRect.topLeft,
          position: position,
          hitTest: (result, local) => player.hitTest(result, position: local),
        );
      }
    }
    return super.hitTestChildren(result, position: position);
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}
