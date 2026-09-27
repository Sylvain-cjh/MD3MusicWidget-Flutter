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
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _preview = AppState.shouldPreviewNext;
    AppState.playbackRevision.addListener(_onPlaybackChanged);
    AppState.queue.addListener(_onQueueChanged);
  }

  void _onPlaybackChanged() {
    final next = AppState.shouldPreviewNext;
    if (next != _preview && mounted) setState(() => _preview = next);
  }

  void _onQueueChanged() {
    if (!mounted) return;
    setState(() => _preview = AppState.shouldPreviewNext);
  }

  @override
  void dispose() {
    AppState.playbackRevision.removeListener(_onPlaybackChanged);
    AppState.queue.removeListener(_onQueueChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppState.currentScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final queue = AppState.queue.queue;
    final fromQqPlaylist = AppState.queue.providerId == 'qqMusicPlaylist';
    final PlatformQueueItem? next = AppState.nextQueueItem;
    final preview = _preview && next != null;
    final String label;
    final String detail;
    if (preview) {
      label = '预计下一首 · ${next.title}';
      detail = next.artist.isEmpty
          ? (fromQqPlaylist ? '来自 QQ 音乐歌单' : '来自导入的播放列表')
          : next.artist;
    } else if (AppState.isShuffleActive == true) {
      label = '随机播放中';
      detail = '无法可靠预测下一首';
    } else if (AppState.autoRepeatMode == 'track') {
      label = '单曲循环中';
      detail = '不会预告其他歌曲';
    } else if (AppState.queue.isLoading) {
      label = fromQqPlaylist ? '正在读取 QQ 音乐歌单' : '正在读取播放列表';
      detail = '请稍候';
    } else if (AppState.queue.error != null) {
      label = fromQqPlaylist ? 'QQ 音乐歌单暂不可用' : '播放列表暂不可用';
      detail = fromQqPlaylist ? '请检查歌单链接或网络' : '请在设置中重新选择文件';
    } else if (queue?.currentIndex != null) {
      label = fromQqPlaylist
          ? 'QQ 音乐歌单 · ${queue!.currentIndex! + 1}/${queue.items.length}'
          : '播放列表 · ${queue!.currentIndex! + 1}/${queue.items.length}';
      detail = fromQqPlaylist ? '按歌单顺序估算，临时队列可能不同' : '歌曲接近结束时预告下一首';
    } else if (AppState.qqPlaylistLink.isNotEmpty &&
        AppState.playlistFilePath.isEmpty &&
        AppState.currentPlatformTrack?.platform != MusicPlatform.qqMusic) {
      label = 'QQ 音乐歌单待连接';
      detail = '切换到 QQ 音乐歌曲后读取歌单';
    } else {
      label = fromQqPlaylist ? 'QQ 音乐歌单已载入' : '播放列表已载入';
      detail = queue == null ? '请在设置中选择播放列表来源' : '尚未匹配当前歌曲';
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: _glassBlur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.40),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  preview ? Icons.skip_next_rounded : Icons.queue_music_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.16),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey('$preview|$label|$detail'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: scheme.onSurface),
                        ),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
