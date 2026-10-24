import 'package:flutter/material.dart';
import '../../core/appState.dart';
import 'pixelAlignedText.dart';



class AdaptiveMediaText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Key? textKey;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextHeightBehavior? textHeightBehavior;
  final TextScaler? textScaler;
  final TextDirection? textDirection;
  const AdaptiveMediaText(
    this.text, {
    super.key,
    required this.style,
    this.textKey,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.textHeightBehavior,
    this.textScaler,
    this.textDirection,
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
        textHeightBehavior:
            textHeightBehavior ?? AppState.crispTextHeightBehavior,
        textScaler: textScaler,
        textDirection: textDirection,
        style: style.copyWith(
          color: AppState.readableMediaColor(AppState.estimatedMediaBackdrop),
          shadows: const [],
        ),
      ),
    ),
  );
}
