import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import 'pixel_aligned_text.dart';



class AdaptiveMediaText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Key? textKey;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextHeightBehavior? textHeightBehavior;
  const AdaptiveMediaText(
    this.text, {
    super.key,
    required this.style,
    this.textKey,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textHeightBehavior,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      AppState.mediaTextColor,
      AppState.backgroundRevision,
    ]),
    builder: (context, _) => PixelAlignedText(
      child: Text(
        text,
        key: textKey,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
        textHeightBehavior: textHeightBehavior,
        style: style.copyWith(
          color: AppState.readableMediaColor(AppState.estimatedMediaBackdrop),
          shadows: const [],
        ),
      ),
    ),
  );
}
