import 'package:flutter/material.dart';
import 'lawniconsBrandGeometry.dart';


class ProviderBrandMark extends StatelessWidget {
  final String source;
  final ColorScheme scheme;
  final double size;
  const ProviderBrandMark({
    super.key,
    required this.source,
    required this.scheme,
    this.size = 27,
  });

  @override
  Widget build(BuildContext context) {
    final ink = scheme.onSurface;
    return SizedBox.square(
      dimension: size,
      child: Padding(
        padding: EdgeInsets.all(size * .06),
        child: switch (source) {
          'qqMusic' || 'neteaseCloud' => CustomPaint(
            painter: ProviderBrandPainter(source, ink),
          ),
          'lrclib' => Center(
            child: ExcludeSemantics(
              child: Text(
                'LRC\nLIB',
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  fontSize: size * .38,
                  height: .94,
                  letterSpacing: .35,
                ),
              ),
            ),
          ),
          'amll' => Icon(
            Icons.library_music_rounded,
            color: ink,
            size: size * .76,
          ),
          _ => Icon(
            source == 'localLrc' ? Icons.folder_rounded : Icons.lyrics_rounded,
            color: ink,
            size: size * .76,
          ),
        },
      ),
    );
  }
}

class ProviderBrandPainter extends CustomPainter {
  final String source;
  final Color color;
  ProviderBrandPainter(this.source, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / LawniconsBrandGeometry.viewport;
    canvas.save();
    canvas.translate(
      (size.width - size.shortestSide) / 2,
      (size.height - size.shortestSide) / 2,
    );
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = LawniconsBrandGeometry.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      source == 'qqMusic'
          ? LawniconsBrandGeometry.qqMusic
          : LawniconsBrandGeometry.neteaseCloud,
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(ProviderBrandPainter oldDelegate) =>
      oldDelegate.source != source || oldDelegate.color != color;
}
