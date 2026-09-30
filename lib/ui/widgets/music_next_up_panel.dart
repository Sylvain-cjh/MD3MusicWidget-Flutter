import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/platform_provider.dart';
import '../../core/next_up_preview_controller.dart';
import '../animations/next_up_presence_motion.dart';

class MusicNextUpPanel extends StatefulWidget {
  final Animation<double>? presenceAnimation;
  const MusicNextUpPanel({super.key, this.presenceAnimation});

  @override
  State<MusicNextUpPanel> createState() => _MusicNextUpPanelState();
}

class _MusicNextUpPanelState extends State<MusicNextUpPanel>
    with SingleTickerProviderStateMixin {
  static final ImageFilter _glassBlur = ImageFilter.blur(
    sigmaX: 13,
    sigmaY: 13,
  );
  late final NextUpPreviewController _preview;
  late final AnimationController _localAnimation;
  Animation<double> get _animation =>
      widget.presenceAnimation ?? _localAnimation;
  PlatformQueueItem? _visibleNext;

  @override
  void initState() {
    super.initState();
    _localAnimation = AnimationController(vsync: this);
    _preview = AppState.nextUpPreviewController;
    _preview.addListener(_syncPreview);
    _animation.addStatusListener(_onStatus);
    _visibleNext = _preview.next;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPreview();
  }

  void _syncPreview() {
    if (!mounted) return;
    setState(() {
      if (_preview.visible) _visibleNext = _preview.next;
      if (!_preview.visible && _animation.value == 0) _visibleNext = null;
    });
    if (widget.presenceAnimation == null) {
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      _localAnimation.animateTo(
        _preview.visible ? 1 : 0,
        duration: reduceMotion
            ? const Duration(milliseconds: 160)
            : _preview.visible
            ? NextUpPresenceMotion.enterDuration
            : NextUpPresenceMotion.exitDuration,
        curve: AppState.layoutSwitchCurve,
      );
    }
  }

  void _onStatus(AnimationStatus status) {
    if ((status == AnimationStatus.dismissed ||
            status == AnimationStatus.completed) &&
        _animation.value == 0 &&
        !_preview.visible &&
        mounted) {
      setState(() => _visibleNext = null);
    }
  }

  @override
  void didUpdateWidget(covariant MusicNextUpPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.presenceAnimation != widget.presenceAnimation) {
      (oldWidget.presenceAnimation ?? _localAnimation).removeStatusListener(
        _onStatus,
      );
      _animation.addStatusListener(_onStatus);
    }
  }

  @override
  void dispose() {
    _preview.removeListener(_syncPreview);
    _animation.removeStatusListener(_onStatus);
    _localAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppState.currentScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final PlatformQueueItem? next = _visibleNext;
    final preview = next != null;
    final label = preview ? '预计下一首 · ${next.title}' : '';
    final detail = preview
        ? next.artist.isNotEmpty
              ? next.artist
              : AppState.queue.providerId == 'qqMusicPlaylist'
              ? '来自 QQ 音乐歌单'
              : '来自导入的播放列表'
        : '';
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: 48,
        maxHeight: 48,
        child: FadeTransition(
          opacity: _animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: reduceMotion ? Offset.zero : const Offset(0, 0.18),
              end: Offset.zero,
            ).animate(_animation),
            child: !preview
                ? const SizedBox.shrink(key: ValueKey('next_up_hidden'))
                : ClipRRect(
                    key: ValueKey('next_up_${next.id}'),
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: _glassBlur,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh.withValues(
                            alpha: 0.62,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.40,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Icon(
                                Icons.skip_next_rounded,
                                size: 20,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(color: scheme.onSurface),
                                    ),
                                    Text(
                                      detail,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
