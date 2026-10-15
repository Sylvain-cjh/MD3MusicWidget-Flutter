import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import 'adaptive_media_text.dart';


class PlaybackTimeLabel extends StatefulWidget {
  final double? maxWidth;
  const PlaybackTimeLabel({super.key, this.maxWidth});

  static final Map<(TextStyle, double, String), Size> _metrics = {};

  static TextStyle get geometryStyle => TextStyle(
    fontSize: 11,
    fontWeight: AppState.artistWeight,
    fontVariations: AppState.variationsFor(
      AppState.artistWeightValue,
      fontSize: 11,
    ),
    height: 1.2,
    fontFamily: AppState.effectiveGlobalFontFamily,
    fontFamilyFallback: AppState.textFontFallback,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static String reserveFor(double duration) {
    final digits = duration.isFinite && duration >= 3600000
        ? format(duration).replaceAll(RegExp(r'\d'), '8')
        : '88:88';
    return '$digits / $digits';
  }

  static Size measure(TextStyle style, double scale, String reserve) {
    final key = (style, scale, reserve);
    return _metrics.putIfAbsent(key, () {
      if (_metrics.length >= 32) _metrics.remove(_metrics.keys.first);
      var width = 0.0, height = 0.0;
      
      for (var digit = 0; digit < 10; digit++) {
        final painter = TextPainter(
          text: TextSpan(text: reserve.replaceAll('8', '$digit'), style: style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
          maxLines: 1,
          textHeightBehavior: AppState.crispTextHeightBehavior,
        )..layout();
        width = math.max(width, painter.width);
        height = math.max(height, painter.height);
        painter.dispose();
      }
      return Size((width + 2).ceilToDouble(), (height + 2).ceilToDouble());
    });
  }

  static double preferredHeight(BuildContext context) => measure(
    geometryStyle,
    MediaQuery.textScalerOf(context).scale(11) / 11,
    reserveFor(AppState.playbackDurationMs),
  ).height;

  static String format(double milliseconds) {
    if (!milliseconds.isFinite || milliseconds < 0) return '--:--';
    final seconds = (milliseconds / 1000).floor();
    final s = (seconds % 60).toString().padLeft(2, '0');
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes:$s';
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:$s';
  }

  @override
  State<PlaybackTimeLabel> createState() => _PlaybackTimeLabelState();
}

class _PlaybackTimeLabelState extends State<PlaybackTimeLabel> {
  Timer? _timer;
  String _text = '';
  String _reserve = '';
  String _identity = '';

  @override
  void initState() {
    super.initState();
    AppState.playbackRevision.addListener(_refresh);
    AppState.typographyRevision.addListener(_styleChanged);
    AppState.fontsRevision.addListener(_fontsChanged);
    AppState.backgroundRevision.addListener(_styleChanged);
    _refresh();
  }

  void _styleChanged() {
    if (mounted) setState(() {});
  }

  void _fontsChanged() {
    PlaybackTimeLabel._metrics.clear();
    _styleChanged();
  }

  void _refresh() {
    final duration = AppState.playbackDurationMs;
    final hasDuration = duration.isFinite && duration > 0;
    final identity =
        '${AppState.currentPlatformTrack?.sourceAppId}|${AppState.trackTitle}|${AppState.artistName}';
    if (!hasDuration && identity == _identity && _text.isNotEmpty) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _identity = identity;
    final total = hasDuration ? PlaybackTimeLabel.format(duration) : '--:--';
    final elapsed = hasDuration
        ? PlaybackTimeLabel.format(
            AppState.estimatedPlaybackPositionMs.clamp(0.0, duration),
          )
        : '--:--';
    final text = '$elapsed / $total';
    final reserve = PlaybackTimeLabel.reserveFor(duration);
    if (_text != text || _reserve != reserve) {
      setState(() {
        _text = text;
        _reserve = reserve;
      });
    }
    if (AppState.isPlaying && hasDuration) {
      _timer ??= Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _refresh(),
      );
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    AppState.playbackRevision.removeListener(_refresh);
    AppState.typographyRevision.removeListener(_styleChanged);
    AppState.fontsRevision.removeListener(_fontsChanged);
    AppState.backgroundRevision.removeListener(_styleChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppState.enableGlow
        ? Colors.white.withValues(alpha: AppState.isPlaying ? 0.85 : 0.60)
        : AppState.currentScheme.onSurfaceVariant;
    final style = PlaybackTimeLabel.geometryStyle;
    var scale = MediaQuery.textScalerOf(context).scale(11) / 11;
    var metrics = PlaybackTimeLabel.measure(style, scale, _reserve);
    final limit = widget.maxWidth;
    if (limit != null && metrics.width > limit) {
      
      scale *= math.max(1, limit - 2) / metrics.width;
      metrics = PlaybackTimeLabel.measure(style, scale, _reserve);
    }
    return Semantics(
      label: '已播放与总时长：$_text',
      child: SizedBox(
        key: const ValueKey('playback_time_slot'),
        width: limit == null ? metrics.width : math.min(metrics.width, limit),
        height: metrics.height,
        child: Align(
          alignment: Alignment.centerRight,
          child: AdaptiveMediaText(
            _text,
            textKey: const ValueKey('playback_time_text'),
            style: style.copyWith(color: color),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
            textHeightBehavior: AppState.crispTextHeightBehavior,
          ),
        ),
      ),
    );
  }
}
