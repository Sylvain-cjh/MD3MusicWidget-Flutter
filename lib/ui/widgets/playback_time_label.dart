import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';


class PlaybackTimeLabel extends StatefulWidget {
  const PlaybackTimeLabel({super.key});

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
  TextStyle? _measuredStyle;
  TextScaler? _measuredScaler;
  String _measuredReserve = '';
  double _reservedWidth = 0;

  @override
  void initState() {
    super.initState();
    AppState.playbackRevision.addListener(_refresh);
    AppState.typographyRevision.addListener(_styleChanged);
    AppState.backgroundRevision.addListener(_styleChanged);
    _refresh();
  }

  void _styleChanged() {
    if (mounted) setState(() {});
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
    
    
    final digits = hasDuration && duration >= 3600000
        ? total.replaceAll(RegExp(r'\d'), '8')
        : '88:88';
    final reserve = '$digits / $digits';
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
    AppState.backgroundRevision.removeListener(_styleChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppState.enableGlow
        ? Colors.white.withValues(alpha: AppState.isPlaying ? 0.85 : 0.60)
        : AppState.currentScheme.onSurfaceVariant;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: AppState.artistWeight,
      fontVariations: AppState.variationsFor(AppState.artistWeightValue),
      height: 1.2,
      color: color,
      fontFamily: AppState.currentFontFamily == AppState.defaultFontFamily
          ? null
          : AppState.currentFontFamily,
      fontFamilyFallback: AppState.textFontFallback,
      fontFeatures: const [FontFeature.tabularFigures()],
      shadows: AppState.enableGlow
          ? const [Shadow(color: Color(0x66000000), blurRadius: 3)]
          : null,
    );
    final scaler = MediaQuery.textScalerOf(context);
    if (_measuredStyle != style ||
        _measuredScaler != scaler ||
        _measuredReserve != _reserve) {
      final painter = TextPainter(
        text: TextSpan(text: _reserve, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      _reservedWidth = painter.width.ceilToDouble();
      painter.dispose();
      _measuredStyle = style;
      _measuredScaler = scaler;
      _measuredReserve = _reserve;
    }
    return Semantics(
      label: '已播放与总时长：$_text',
      child: SizedBox(
        width: _reservedWidth,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            _text,
            key: const ValueKey('playback_time_text'),
            style: style,
          ),
        ),
      ),
    );
  }
}
