import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/lyrics_coordinator.dart';

class MusicLyricsPanel extends StatefulWidget {
  const MusicLyricsPanel({super.key});

  @override
  State<MusicLyricsPanel> createState() => _MusicLyricsPanelState();
}

class _MusicLyricsPanelState extends State<MusicLyricsPanel> {
  static final ImageFilter _glassBlur = ImageFilter.blur(
    sigmaX: 13,
    sigmaY: 13,
  );
  Timer? _timelineTimer;

  @override
  void initState() {
    super.initState();
    AppState.lyrics.addListener(_onLyricsChanged);
    _syncTimelineTimer();
  }

  void _onLyricsChanged() {
    _syncTimelineTimer();
    if (mounted) setState(() {});
  }

  void _syncTimelineTimer() {
    if (AppState.lyrics.state.document?.isTimed == true) {
      _timelineTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (AppState.isPlaying) {
          AppState.lyrics.setPositionMs(AppState.estimatedPlaybackPositionMs);
        }
      });
    } else {
      _timelineTimer?.cancel();
      _timelineTimer = null;
    }
  }

  @override
  void dispose() {
    _timelineTimer?.cancel();
    AppState.lyrics.removeListener(_onLyricsChanged);
    super.dispose();
  }

  String _displayText(LyricsState state) {
    if (AppState.currentPlatformTrack == null) return '等待歌曲播放';
    switch (state.status) {
      case LyricsStatus.loading:
        return '正在匹配歌词…';
      case LyricsStatus.failed:
        return switch (state.issue) {
          LyricsIssue.rateLimited => '歌词服务请求过于频繁，请稍后切歌重试',
          LyricsIssue.network => '歌词网络请求失败，请检查网络',
          LyricsIssue.invalidData => '歌词返回格式无法解析',
          _ => '歌词获取失败',
        };
      case LyricsStatus.unavailable:
        if (state.issue == LyricsIssue.noProvider) return '当前歌词来源不可用';
        if (AppState.lyricsProviderChoice == LyricsProviderChoice.localLrc &&
            AppState.localLyricsDirectory.isEmpty) {
          return '请在设置中选择 LRC 文件夹';
        }
        return '暂未找到歌词';
      case LyricsStatus.ready:
        final document = state.document!;
        if (!document.isTimed) return document.plainText;
        return state.currentLine?.text.isNotEmpty == true
            ? state.currentLine!.text
            : '♪';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppState.currentScheme;
    final state = AppState.lyrics.state;
    final radius = BorderRadius.circular(24);
    final displayText = _displayText(state);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: _glassBlur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surfaceContainerHigh.withValues(alpha: 0.60),
                scheme.primaryContainer.withValues(alpha: 0.20),
                scheme.surface.withValues(alpha: 0.46),
              ],
            ),
            borderRadius: radius,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.42),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Row(
              children: [
                Icon(
                  Icons.lyrics_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: Align(
                      key: ValueKey(
                        '${state.providerId}:${state.status}:${state.lineIndex}:$displayText',
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        displayText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                          fontFamilyFallback: AppState.textFontFallback,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                if (AppState.currentPlatformTrack != null &&
                    (state.status == LyricsStatus.failed ||
                        state.issue == LyricsIssue.noMatch))
                  IconButton(
                    tooltip: '重新查询歌词',
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    onPressed: () => AppState.refreshLyrics(force: true),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
