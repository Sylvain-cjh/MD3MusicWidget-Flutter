import 'package:flutter/material.dart';
import 'lawnicons_brand_geometry.dart';



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
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * .34),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * .06),
        child: switch (source) {
          'qqMusic' || 'neteaseCloud' => CustomPaint(
            painter: ProviderBrandPainter(source, scheme.onPrimaryContainer),
          ),
          'lrclib' => ClipRRect(
            borderRadius: BorderRadius.circular(size * .2),
            child: Image.asset('assets/brand/lrclib.png'),
          ),
          'amll' => Icon(
            Icons.library_music_rounded,
            color: scheme.onPrimaryContainer,
            size: size * .76,
          ),
          _ => Icon(
            source == 'localLrc' ? Icons.folder_rounded : Icons.lyrics_rounded,
            color: scheme.onPrimaryContainer,
            size: size * .76,
          ),
        },
      ),
    ),
  );
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
