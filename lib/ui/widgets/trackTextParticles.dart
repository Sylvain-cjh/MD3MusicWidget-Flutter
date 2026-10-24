part of 'trackControls.dart';

class _TextInfoWidget extends StatelessWidget {
  final String text;
  final bool isPlaceholder;
  final TextStyle style;
  final double measuredWidth;
  final double measuredHeight;
  final LayoutMorphMotion? layoutMotion;
  const _TextInfoWidget({
    required super.key,
    required this.text,
    required this.isPlaceholder,
    required this.style,
    required this.measuredWidth,
    required this.measuredHeight,
    this.layoutMotion,
  });
  @override
  Widget build(BuildContext context) => MorphTextStyle(
    motion: layoutMotion,
    style: style,
    builder: (style) => AdaptiveMediaText(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textHeightBehavior: AppState.crispTextHeightBehavior,
      style: style,
    ),
  );
}

class _PixelDissolveTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;
  final bool isIncoming;
  final int direction;
  final String text;
  final double targetWidth;
  final double targetHeight;

  const _PixelDissolveTransition({
    required this.child,
    required this.animation,
    required this.isIncoming,
    required this.direction,
    required this.text,
    required this.targetWidth,
    required this.targetHeight,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final double t = animation.value;
        final double progress = isIncoming ? (1.0 - t) : t;
        final double textOpacity = isIncoming
            ? ((0.38 - progress) / 0.38).clamp(0.0, 1.0)
            : (1.0 - progress / 0.22).clamp(0.0, 1.0);
        return CustomPaint(
          foregroundPainter: _PixelParticlePainter(
            progress: progress,
            isIncoming: isIncoming,
            direction: direction,
            text: text,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            primaryColor: AppState.currentScheme.primary,
            onSurfaceColor: AppState.currentScheme.onSurface,
          ),
          child: Opacity(opacity: textOpacity, child: child),
        );
      },
    );
  }
}

class _ParticleSeed {
  final double x;
  final double y;
  final double horizontalNoise;
  final double verticalNoise;
  final bool usesPrimary;

  const _ParticleSeed({
    required this.x,
    required this.y,
    required this.horizontalNoise,
    required this.verticalNoise,
    required this.usesPrimary,
  });
}

class _ParticleBuffers {
  static const int bucketCount = 4;
  final List<Float32List> primary;
  final List<Float32List> surface;
  final List<int> primaryCounts = List<int>.filled(bucketCount, 0);
  final List<int> surfaceCounts = List<int>.filled(bucketCount, 0);

  _ParticleBuffers(int particleCapacity)
    : primary = List<Float32List>.generate(
        bucketCount,
        (_) => Float32List(particleCapacity * 2),
        growable: false,
      ),
      surface = List<Float32List>.generate(
        bucketCount,
        (_) => Float32List(particleCapacity * 2),
        growable: false,
      );

  void reset() {
    primaryCounts.fillRange(0, bucketCount, 0);
    surfaceCounts.fillRange(0, bucketCount, 0);
  }

  void add({
    required bool usesPrimary,
    required int bucket,
    required double x,
    required double y,
  }) {
    final lists = usesPrimary ? primary : surface;
    final counts = usesPrimary ? primaryCounts : surfaceCounts;
    final int index = counts[bucket];
    lists[bucket][index] = x;
    lists[bucket][index + 1] = y;
    counts[bucket] = index + 2;
  }
}

class _PixelParticlePainter extends CustomPainter {
  static const double _particleStep = 3.0;
  static final Map<String, List<_ParticleSeed>> _seedCache =
      <String, List<_ParticleSeed>>{};
  static final Map<String, _ParticleBuffers> _bufferCache =
      <String, _ParticleBuffers>{};

  final double progress;
  final bool isIncoming;
  final int direction;
  final String text;
  final double targetWidth;
  final double targetHeight;
  final Color primaryColor;
  final Color onSurfaceColor;

  _PixelParticlePainter({
    required this.progress,
    required this.isIncoming,
    required this.direction,
    required this.text,
    required this.targetWidth,
    required this.targetHeight,
    required this.primaryColor,
    required this.onSurfaceColor,
  });

  String get _particleKey =>
      '$text|${targetWidth.toStringAsFixed(1)}|${targetHeight.toStringAsFixed(1)}';

  List<_ParticleSeed> _particlesForText() {
    final String key = _particleKey;
    final cached = _seedCache[key];
    if (cached != null) return cached;

    final particles = <_ParticleSeed>[];
    for (double y = 0; y < targetHeight; y += _particleStep) {
      for (double x = 0; x < targetWidth; x += _particleStep) {
        final int row = (y / _particleStep).toInt();
        final int column = (x / _particleStep).toInt();
        final int h1 = (row * 129898 + column * 78233) % 43758;
        final int h2 = (row * 45123 + column * 13789) % 23456;
        particles.add(
          _ParticleSeed(
            x: x,
            y: y,
            horizontalNoise: (h1 / 43758.0) * 2.0 - 1.0,
            verticalNoise: (h2 / 23456.0) * 2.0 - 1.0,
            usesPrimary: (row + column).isEven,
          ),
        );
      }
    }
    if (_seedCache.length >= 12) {
      final String oldestKey = _seedCache.keys.first;
      _seedCache.remove(oldestKey);
      _bufferCache.remove(oldestKey);
    }
    _seedCache[key] = particles;
    return particles;
  }

  _ParticleBuffers _buffersForText(int particleCapacity) {
    return _bufferCache.putIfAbsent(
      _particleKey,
      () => _ParticleBuffers(particleCapacity),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01 || progress >= 0.99) return;
    final Paint paint = Paint()
      ..isAntiAlias = false
      ..strokeCap = StrokeCap.square;

    final int textLength = text.runes.length;
    final double dynamicScatterRange = (targetWidth * 0.38 + textLength * 0.8)
        .clamp(36.0, 140.0);
    final double releaseSpan = (0.18 + textLength * 0.004).clamp(0.18, 0.34);
    final particles = _particlesForText();
    final buffers = _buffersForText(particles.length)..reset();

    for (final particle in particles) {
      final double releaseThreshold =
          particle.horizontalNoise.abs() * releaseSpan;

      if (progress <= releaseThreshold) continue;
      final double age =
          (progress - releaseThreshold) / (1.0 - releaseThreshold);
      final double visibility = (1.0 - age).clamp(0.0, 1.0);
      final int bucket = (visibility * _ParticleBuffers.bucketCount).ceil() - 1;
      if (bucket < 0) continue;

      final double easedAge = age * age * (1.0 + 0.35 * age);
      final double offsetX =
          direction * particle.horizontalNoise * dynamicScatterRange * easedAge;
      final double offsetY = (particle.verticalNoise - 0.45) * 30.0 * age;
      buffers.add(
        usesPrimary: particle.usesPrimary,
        bucket: bucket.clamp(0, _ParticleBuffers.bucketCount - 1),
        x: particle.x + offsetX,
        y: particle.y + offsetY,
      );
    }

    for (int bucket = 0; bucket < _ParticleBuffers.bucketCount; bucket++) {
      final double alpha = (bucket + 1) / _ParticleBuffers.bucketCount;
      paint.strokeWidth = 0.62 + bucket * 0.07;

      final int primaryCount = buffers.primaryCounts[bucket];
      if (primaryCount > 0) {
        paint.color = primaryColor.withValues(alpha: alpha);
        canvas.drawRawPoints(
          PointMode.points,
          Float32List.sublistView(buffers.primary[bucket], 0, primaryCount),
          paint,
        );
      }

      final int surfaceCount = buffers.surfaceCounts[bucket];
      if (surfaceCount > 0) {
        paint.color = onSurfaceColor.withValues(alpha: alpha);
        canvas.drawRawPoints(
          PointMode.points,
          Float32List.sublistView(buffers.surface[bucket], 0, surfaceCount),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelParticlePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.text != text ||
      oldDelegate.targetWidth != targetWidth ||
      oldDelegate.targetHeight != targetHeight ||
      oldDelegate.direction != direction ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.onSurfaceColor != onSurfaceColor;
}
