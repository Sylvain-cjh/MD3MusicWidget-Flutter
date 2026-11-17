import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audioOutputs.dart';
import 'smoothRoundedClip.dart';



class AudioOutputVolume extends StatefulWidget {
  final AudioOutputs audio;
  final AudioOutput output;
  final double scale;
  final String label;

  const AudioOutputVolume({
    super.key,
    required this.audio,
    required this.output,
    required this.scale,
    required this.label,
  });

  @override
  State<AudioOutputVolume> createState() => _AudioOutputVolumeState();
}

class _AudioOutputVolumeState extends State<AudioOutputVolume> {
  static const _writeInterval = Duration(milliseconds: 50);
  final _focus = FocusNode();
  AudioOutputVolumeState? _confirmed;
  double? _queued, _inFlight;
  Timer? _writeTimer;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    unawaited(_read());
  }

  Future<void> _read() async {
    final value = await widget.audio.readVolume(widget.output.id);
    if (mounted) setState(() => _confirmed = value);
  }

  void _focusChanged() => setState(() {});

  void _change(double level) {
    if (!widget.audio.isCurrent(widget.output.id)) return;
    setState(() => _queued = level);
    _schedule();
  }

  void _schedule() {
    if (_inFlight != null || _queued == null) return;
    _writeTimer ??= Timer(_writeInterval, _flush);
  }

  void _flush() {
    _writeTimer?.cancel();
    _writeTimer = null;
    final level = _queued;
    if (level == null || _inFlight != null) return;
    _queued = null;
    _inFlight = level;
    unawaited(_send(level));
  }

  Future<void> _send(double level) async {
    final result = await widget.audio.setVolume(widget.output.id, level);
    if (!mounted) return;
    setState(() {
      _inFlight = null;
      if (result != null) {
        _confirmed = result;
      } else {
        _queued = null;
      }
    });
    _schedule();
  }

  @override
  void dispose() {
    _writeTimer?.cancel();
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.audio,
    builder: (context, _) {
      final scheme = Theme.of(context).colorScheme;
      final scale = widget.scale;
      final level = _queued ?? _inFlight ?? _confirmed?.level ?? 0;
      final muted =
          (_confirmed?.muted ?? false) && _queued == null && _inFlight == null;
      final enabled =
          _confirmed != null && widget.audio.isCurrent(widget.output.id);
      final ink = enabled ? scheme.onSurface : scheme.onSurfaceVariant;
      final rail = enabled
          ? Color.lerp(
              scheme.surfaceContainerHighest,
              scheme.primaryContainer,
              .7,
            )!
          : scheme.surfaceContainer;
      final fill = Color.lerp(rail, scheme.primary, .29)!;
      final showPercent = enabled && (_dragging || _focus.hasFocus);
      return LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight;
          final w = constraints.maxWidth;
          final travel = (w - h).clamp(0.0, w);
          final corners = SmoothSurfaceCorners.popoverItem * scale;
          return SmoothRoundedClip(
            borderRadius: corners,
            composite: false,
            side: _focus.hasFocus && enabled
                ? BorderSide(color: scheme.primary, width: 1.2 * scale)
                : BorderSide.none,
            child: ColoredBox(
              color: rail,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (enabled)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox(
                        width: (h + travel * (muted ? 0 : level)).clamp(0.0, w),
                        height: h,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            shape: SmoothSurfaceCorners.shape(corners),
                            color: fill,
                          ),
                        ),
                      ),
                    ),
                  Semantics(
                    label: '${widget.label}音量',
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 0,
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        disabledActiveTrackColor: Colors.transparent,
                        disabledInactiveTrackColor: Colors.transparent,
                        thumbShape: SliderComponentShape.noThumb,
                        overlayShape: SliderComponentShape.noOverlay,
                        showValueIndicator: ShowValueIndicator.never,
                      ),
                      child: Slider(
                        key: const ValueKey('home_audio_output_volume'),
                        focusNode: _focus,
                        padding: EdgeInsets.symmetric(
                          horizontal: (h / 2).clamp(0, w / 2),
                        ),
                        value: muted ? 0 : level,
                        onChanged: enabled ? _change : null,
                        onChangeStart: enabled
                            ? (_) => setState(() => _dragging = true)
                            : null,
                        onChangeEnd: enabled
                            ? (_) {
                                setState(() => _dragging = false);
                                _flush();
                              }
                            : null,
                        semanticFormatterCallback: (value) =>
                            '${(value * 100).round()}%',
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(end: 11 * scale),
                        child: Row(
                          children: [
                            SizedBox.square(
                              dimension: h,
                              child: Icon(
                                muted || level == 0
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                size: 19 * scale,
                                color: ink,
                              ),
                            ),
                            SizedBox(width: 5 * scale),
                            Expanded(
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      fontSize: 12.5 * scale,
                                      color: ink,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                            SizedBox(width: 4 * scale),
                            SizedBox(
                              width: 28 * scale,
                              child: Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: showPercent || !enabled
                                    ? Text(
                                        enabled
                                            ? '${((muted ? 0 : level) * 100).round()}%'
                                            : '—',
                                        maxLines: 1,
                                        overflow: TextOverflow.clip,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontSize: 10.5 * scale,
                                              color: ink,
                                            ),
                                      )
                                    : SizedBox.square(
                                        dimension: 4 * scale,
                                        child: DecoratedBox(
                                          decoration: ShapeDecoration(
                                            color: ink.withValues(alpha: .78),
                                            shape: const CircleBorder(),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
