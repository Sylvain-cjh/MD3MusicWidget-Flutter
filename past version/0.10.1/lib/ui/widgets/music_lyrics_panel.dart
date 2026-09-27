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
    AppState.typographyRevision.addListener(_onLyricsChanged);
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
    AppState.typographyRevision.removeListener(_onLyricsChanged);
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

  Widget _sourceIcon(LyricsState state, ColorScheme scheme) {
    final source = state.providerId.isNotEmpty
        ? state.providerId
        : AppState.lyricsProviderChoice.name;
    final (label, foreground, background, mark) = switch (source) {
      'qqMusic' => (
        'QQ 音乐',
        const Color(0xFF063B24),
        const Color(0xFF75DFA0),
        'QQ',
      ),
      'lrclib' => (
        'LRCLIB',
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
        'LRC',
      ),
      'localLrc' => (
        '本地 LRC',
        scheme.onTertiaryContainer,
        scheme.tertiaryContainer,
        '',
      ),
      _ => ('歌词', scheme.onSurfaceVariant, scheme.surfaceContainerHighest, ''),
    };
    return Tooltip(
      message: '歌词来源：$label',
      child: Semantics(
        label: '歌词来源：$label',
        child: DecoratedBox(
          key: ValueKey('lyrics_source_$source'),
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: SizedBox(
            width: 27,
            height: 27,
            child: Center(
              child: mark.isNotEmpty
                  ? Text(
                      mark,
                      style: TextStyle(
                        color: foreground,
                        fontSize: mark.length == 3 ? 9 : 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    )
                  : Icon(
                      source == 'localLrc'
                          ? Icons.folder_rounded
                          : Icons.lyrics_rounded,
                      size: 17,
                      color: foreground,
                    ),
            ),
          ),
        ),
      ),
    );
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
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: KeyedSubtree(
                    key: ValueKey(
                      state.providerId.isNotEmpty
                          ? state.providerId
                          : AppState.lyricsProviderChoice.name,
                    ),
                    child: _sourceIcon(state, scheme),
                  ),
                ),
                const SizedBox(width: 8),
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
                        style: AppState.lyricsTextStyle(scheme.onSurface),
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
