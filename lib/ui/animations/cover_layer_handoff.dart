import 'media_motion_tokens.dart';



abstract final class CoverLayerHandoff {
  static const samplerPhase = .2;

  static double surfaceMix(double progress) =>
      (progress / samplerPhase).clamp(0.0, 1.0);

  static double depth(double progress) =>
      MediaMotionTokens.layerHandoffCurve.transform(
        ((progress - samplerPhase) / (1 - samplerPhase)).clamp(0.0, 1.0),
      );
}
