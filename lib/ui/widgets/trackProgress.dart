part of 'trackControls.dart';

class _PlaybackProgress extends StatefulWidget {
  const _PlaybackProgress();

  @override
  State<_PlaybackProgress> createState() => _PlaybackProgressState();
}

class _ProgressPaintState extends ChangeNotifier {
  double progress = 0;
  bool returning = false;
  double minimumVisibleDelta = 0.00005;

  void update(double nextProgress, bool nextReturning, {bool force = false}) {
    if (!force &&
        (progress - nextProgress).abs() < minimumVisibleDelta &&
        returning == nextReturning) {
      return;
    }
    progress = nextProgress;
    returning = nextReturning;
    notifyListeners();
  }
}

class _PlaybackProgressState extends State<_PlaybackProgress>
    with SingleTickerProviderStateMixin {
  static const double _returnDurationMs = 720.0;
  static const double _catchUpDurationMs = 240.0;
  late final AnimationController _frameController;
  Timer? _progressTimer;
  final _ProgressPaintState _paintState = _ProgressPaintState();
  final Stopwatch _clock = Stopwatch()..start();
  String _trackSource = '';
  String _trackVersion = '';
  String _trackTitle = '';
  String _trackArtist = '';
  double _displayProgress = 0.0;
  double _transitionFrom = 0.0;
  int _transitionStartedAtMs = 0;
  double _catchUpFrom = 0.0;
  int _catchUpStartedAtMs = 0;
  bool _hasExplicitTrackSignal = false;
  MD3ProgressStyle _lastProgressStyle = MD3ProgressStyle.linear;
  bool _lastPlaying = false;
  bool _lastAutoContrast = true;
  bool _lastReturning = false;
  Color _lastSchemeColor = Colors.transparent;
  bool _lastVisible = false;

  @override
  void initState() {
    super.initState();
    _frameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_onFrame);
    _trackSource = AppState.currentPlatformTrack?.sourceAppId ?? '';
    _trackVersion = AppState.trackVersion;
    _trackTitle = AppState.trackTitle;
    _trackArtist = AppState.artistName;
    _displayProgress = _currentTargetProgress;
    _paintState.progress = _displayProgress;
    _lastVisible = AppState.playbackDurationMs > 0 || _displayProgress > 0.001;
    AppState.playbackRevision.addListener(_handlePlaybackSignal);
    AppState.trackTransitionRevision.addListener(_handleTrackTransition);
    _syncProgressClock();
  }

  @override
  void dispose() {
    AppState.playbackRevision.removeListener(_handlePlaybackSignal);
    AppState.trackTransitionRevision.removeListener(_handleTrackTransition);
    _progressTimer?.cancel();
    _frameController.dispose();
    _paintState.dispose();
    super.dispose();
  }

  double get _currentTargetProgress {
    final double duration = AppState.playbackDurationMs;
    if (duration <= 0) return _displayProgress;
    return (AppState.estimatedPlaybackPositionMs / duration).clamp(0.0, 1.0);
  }

  void _syncProgressClock() {
    final bool animating =
        _transitionStartedAtMs > 0 || _catchUpStartedAtMs > 0;
    if (animating) {
      _progressTimer?.cancel();
      _progressTimer = null;
      if (!_frameController.isAnimating) _frameController.repeat();
    } else {
      if (_frameController.isAnimating) _frameController.stop();
      if (AppState.isPlaying && AppState.playbackDurationMs > 0) {
        _progressTimer ??= Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => _onFrame(),
        );
      } else {
        _progressTimer?.cancel();
        _progressTimer = null;
      }
    }
  }

  void _handlePlaybackSignal() {
    if (!mounted) return;
    _onFrame();
    _syncProgressClock();
  }

  void _handleTrackTransition() {
    if (!mounted) return;
    _hasExplicitTrackSignal = true;
    if (_transitionStartedAtMs <= 0) {
      _transitionFrom = _displayProgress;
      _transitionStartedAtMs = _clock.elapsedMilliseconds + 1;
      _catchUpStartedAtMs = 0;
    }
    _syncProgressClock();
    _lastReturning = true;
    _paintState.update(_displayProgress, true);
    if (!_lastVisible) {
      _lastVisible = true;
      setState(() {});
    }
  }

  void _onFrame() {
    final double target = _currentTargetProgress;
    final int now = _clock.elapsedMilliseconds + 1;

    final bool metadataChanged =
        _trackSource != (AppState.currentPlatformTrack?.sourceAppId ?? '') ||
        _trackTitle != AppState.trackTitle ||
        _trackArtist != AppState.artistName;
    final bool trackChanged =
        metadataChanged || _trackVersion != AppState.trackVersion;
    if (trackChanged) {
      final bool hasPreviousTrack =
          _trackSource.isNotEmpty || _trackTitle.isNotEmpty;
      _trackSource = AppState.currentPlatformTrack?.sourceAppId ?? '';
      _trackVersion = AppState.trackVersion;
      _trackTitle = AppState.trackTitle;
      _trackArtist = AppState.artistName;
      if (hasPreviousTrack && metadataChanged && !_hasExplicitTrackSignal) {
        _transitionFrom = _displayProgress;
        _transitionStartedAtMs = now;
        _catchUpStartedAtMs = 0;
      } else {
        _hasExplicitTrackSignal = false;
      }
    }

    double nextProgress = target;
    if (_transitionStartedAtMs > 0) {
      final double t = ((now - _transitionStartedAtMs) / _returnDurationMs)
          .clamp(0.0, 1.0);
      final double eased = Curves.easeInOutCubicEmphasized.transform(t);
      nextProgress = _transitionFrom * (1.0 - eased);
      if (t >= 1.0) {
        _transitionStartedAtMs = 0;
        _catchUpFrom = 0.0;
        _catchUpStartedAtMs = now;
        nextProgress = 0.0;
      }
    } else if (_catchUpStartedAtMs > 0) {
      final double t = ((now - _catchUpStartedAtMs) / _catchUpDurationMs).clamp(
        0.0,
        1.0,
      );
      final double eased = Curves.easeOutCubic.transform(t);
      nextProgress = _catchUpFrom + (target - _catchUpFrom) * eased;
      if (t >= 1.0) {
        _catchUpStartedAtMs = 0;
        nextProgress = target;
      }
    }

    final bool isReturning = _transitionStartedAtMs > 0;

    final bool visible =
        AppState.playbackDurationMs > 0 || isReturning || nextProgress > 0.001;
    final bool shouldRebuild =
        _lastProgressStyle != AppState.progressStyle ||
        _lastPlaying != AppState.isPlaying ||
        _lastAutoContrast != AppState.enableProgressAutoContrast ||
        _lastReturning != isReturning ||
        _lastSchemeColor != AppState.currentScheme.primary ||
        _lastVisible != visible;
    if (!mounted) return;

    _displayProgress = nextProgress;
    _paintState.update(
      nextProgress,
      isReturning,
      force: isReturning || _catchUpStartedAtMs > 0,
    );
    if (shouldRebuild) {
      setState(() {
        _lastProgressStyle = AppState.progressStyle;
        _lastPlaying = AppState.isPlaying;
        _lastAutoContrast = AppState.enableProgressAutoContrast;
        _lastReturning = isReturning;
        _lastSchemeColor = AppState.currentScheme.primary;
        _lastVisible = visible;
      });
    }
    _syncProgressClock();
  }

  @override
  Widget build(BuildContext context) {
    final double duration = AppState.playbackDurationMs;
    final bool isReturning = _transitionStartedAtMs > 0;
    if (duration <= 0 && !isReturning && _displayProgress <= 0.001) {
      return const SizedBox.shrink();
    }

    final Color primary = AppState.currentScheme.primary;
    final Color trackColor = AppState.currentScheme.surfaceContainerHighest;
    final bool autoContrast = AppState.enableProgressAutoContrast;
    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return SizedBox.expand(
      child: CustomPaint(
        painter: _ProgressBarPainter(
          paintState: _paintState,
          activeColor: primary,
          trackColor: trackColor,
          autoContrast: autoContrast,
          style: AppState.progressStyle,
          devicePixelRatio: devicePixelRatio,
        ),
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final _ProgressPaintState paintState;
  final Color activeColor;
  final Color trackColor;
  final bool autoContrast;
  final MD3ProgressStyle style;
  final double devicePixelRatio;

  _ProgressBarPainter({
    required this.paintState,
    required this.activeColor,
    required this.trackColor,
    required this.autoContrast,
    required this.style,
    required this.devicePixelRatio,
  }) : super(repaint: paintState);

  @override
  void paint(Canvas canvas, Size size) {
    paintState.minimumVisibleDelta =
        0.5 / math.max(1.0, size.width * devicePixelRatio);
    final Radius radius = Radius.circular(size.height / 2.0);
    final Paint trackPaint = Paint()
      ..isAntiAlias = true
      ..color = (autoContrast ? Colors.white : trackColor).withValues(
        alpha: autoContrast ? 0.34 : 0.72,
      )
      ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver;
    final Paint activePaint = Paint()
      ..isAntiAlias = true
      ..color = autoContrast ? Colors.white : activeColor
      ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver;

    final double normalized = paintState.progress.clamp(0.0, 1.0);
    if (style == MD3ProgressStyle.segmented) {
      final int segmentCount = (size.width / 12.0).round().clamp(1, 32);
      const double segmentGap = 2.0;
      final double segmentWidth =
          (size.width - segmentGap * (segmentCount - 1)) / segmentCount;
      final double activePosition = normalized * segmentCount;
      for (int i = 0; i < segmentCount; i++) {
        final double x = i * (segmentWidth + segmentGap);
        final RRect segment = roundedMediaFragment(
          Rect.fromLTWH(x, 0, segmentWidth, size.height),
          horizontal: true,
        );
        canvas.drawRRect(segment, trackPaint);
        final double fraction = (activePosition - i).clamp(0.0, 1.0);
        if (fraction > 0) {
          canvas.drawRRect(
            roundedMediaFragment(
              Rect.fromLTWH(x, 0, segmentWidth * fraction, size.height),
              horizontal: true,
            ),
            activePaint,
          );
        }
      }
      return;
    }

    final RRect track = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(track, trackPaint);
    final double activeWidth = size.width * normalized;
    if (activeWidth > 0) {
      final RRect active = roundedMediaFragment(
        Rect.fromLTWH(0, 0, activeWidth, size.height),
        horizontal: true,
      );
      canvas.drawRRect(active, activePaint);
      if (paintState.returning) {
        final Paint returnHighlight = Paint()
          ..isAntiAlias = true
          ..color = (autoContrast ? Colors.white : activeColor).withValues(
            alpha: 0.24,
          )
          ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver;
        canvas.save();
        canvas.clipRRect(active);
        canvas.drawCircle(
          Offset(
            activeWidth.clamp(size.height / 2.0, size.width),
            size.height / 2.0,
          ),
          size.height * 0.42,
          returnHighlight,
        );
        canvas.restore();
      }
    }

    if (style == MD3ProgressStyle.linear) {
      final Paint stopPaint = Paint()
        ..isAntiAlias = true
        ..color = (autoContrast ? Colors.white : activeColor).withValues(
          alpha: 0.86,
        )
        ..blendMode = autoContrast ? BlendMode.difference : BlendMode.srcOver;
      canvas.drawCircle(
        Offset(size.width - size.height / 2.0, size.height / 2.0),
        size.height * 0.34,
        stopPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) =>
      oldDelegate.activeColor != activeColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.autoContrast != autoContrast ||
      oldDelegate.style != style ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      oldDelegate.paintState != paintState;
}
