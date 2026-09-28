import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/platform_provider.dart';

class MusicNextUpPanel extends StatefulWidget {
  const MusicNextUpPanel({super.key});

  @override
  State<MusicNextUpPanel> createState() => _MusicNextUpPanelState();
}

class _MusicNextUpPanelState extends State<MusicNextUpPanel> {
  static final ImageFilter _glassBlur = ImageFilter.blur(
    sigmaX: 13,
    sigmaY: 13,
  );
  Timer? _boundaryTimer;
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    AppState.playbackRevision.addListener(_syncPreview);
    AppState.queue.addListener(_syncPreview);
    _syncPreview();
  }

  void _syncPreview() {
    _boundaryTimer?.cancel();
    if (!mounted) return;

    final next = AppState.shouldPreviewNext;
    if (next != _preview) setState(() => _preview = next);
    if (AppState.nextUpPreviewVisible.value != next) {
      AppState.nextUpPreviewVisible.value = next;
    }

    if (!AppState.showNextUp ||
        !AppState.isPlaying ||
        AppState.nextQueueItem == null ||
        AppState.playbackDurationMs <= 0) {
      return;
    }

    final remainingMs =
        AppState.playbackDurationMs - AppState.estimatedPlaybackPositionMs;
    final leadMs = (AppState.nextUpLeadSeconds * 1000.0).clamp(
      0.0,
      AppState.playbackDurationMs,
    );
    final untilBoundaryMs = next ? remainingMs : remainingMs - leadMs;
    if (untilBoundaryMs > 0) {
      _boundaryTimer = Timer(
        Duration(milliseconds: untilBoundaryMs.ceil() + 16),
        _syncPreview,
      );
    }
  }

  @override
  void dispose() {
    _boundaryTimer?.cancel();
    if (AppState.nextUpPreviewVisible.value) {
      AppState.nextUpPreviewVisible.value = false;
    }
    AppState.playbackRevision.removeListener(_syncPreview);
    AppState.queue.removeListener(_syncPreview);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppState.currentScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final PlatformQueueItem? next = AppState.nextQueueItem;
    return LayoutBuilder(
      builder: (context, constraints) {
        final preview =
            _preview &&
            AppState.shouldPreviewNext &&
            next != null &&
            constraints.maxHeight >= 40;
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
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              reverseDuration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 170),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: reduceMotion
                    ? child
                    : SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.18),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
              ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
        );
      },
    );
  }
}
