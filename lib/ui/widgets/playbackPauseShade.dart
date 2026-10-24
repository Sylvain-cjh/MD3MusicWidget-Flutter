import 'package:flutter/material.dart';

import '../animations/mediaMotionTokens.dart';



class PlaybackPauseShade extends StatelessWidget {
  final bool paused;

  const PlaybackPauseShade({super.key, required this.paused});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: paused ? .28 : 0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : MediaMotionTokens.layerHandoff,
        curve: MediaMotionTokens.curve,
        builder: (context, opacity, child) => ColoredBox(
          key: const ValueKey('pause_dimming_overlay'),
          color: Colors.black.withValues(alpha: opacity),
        ),
      ),
    ),
  );
}
