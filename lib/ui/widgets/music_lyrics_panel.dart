import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/lyrics_coordinator.dart';
import '../animations/lyrics_content_transition.dart';
import 'pixel_aligned_text.dart';
import 'smooth_rounded_clip.dart';
import 'provider_brand_mark.dart';

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
  LyricsState? _retainedState;
  late final AnimatedSwitcherTransitionBuilder _lineTransitionBuilder =
      _buildLineTransition;

  Widget _buildLineTransition(Widget child, Animation<double> animation) =>
      LyricsContentTransition(
        style: AppState.lyricsTransitionStyle,
        exitStyleResolver: () => AppState.effectiveLyricsExitTransitionStyle,
        animation: animation,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        child: child,
      );

  @override
  void initState() {
    super.initState();
    AppState.lyrics.addListener(_onLyricsChanged);
    AppState.typographyRevision.addListener(_onLyricsChanged);
    AppState.lyricsVisualRevision.addListener(_onLyricsChanged);
    AppState.backgroundRevision.addListener(_onLyricsChanged);
    AppState.playbackRevision.addListener(_syncTimelineTimer);
    _syncTimelineTimer();
  }

  void _onLyricsChanged() {
    _syncTimelineTimer();
    if (mounted) setState(() {});
  }

  void _syncTimelineTimer() {
    if (AppState.isPlaying && AppState.lyrics.state.document?.isTimed == true) {
      _timelineTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
        AppState.lyrics.setPositionMs(AppState.estimatedPlaybackPositionMs);
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
    AppState.lyricsVisualRevision.removeListener(_onLyricsChanged);
    AppState.backgroundRevision.removeListener(_onLyricsChanged);
    AppState.playbackRevision.removeListener(_syncTimelineTimer);
    super.dispose();
  }

  String _displayText(LyricsState state) {
    if (AppState.currentPlatformTrack == null) return '等待歌曲播放';
    switch (state.status) {
      case LyricsStatus.loading:
        return state.attempt > 1
            ? '再试一次… ${state.attempt}/${state.maximumAttempts}'
            : '正在匹配歌词…';
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
    final label = switch (source) {
      'qqMusic' => 'QQ 音乐',
      'neteaseCloud' => '网易云音乐',
      'lrclib' => 'LRCLIB',
      'localLrc' => '本地 LRC',
      _ => '歌词',
    };
    return Tooltip(
      message: '歌词来源：$label',
      child: Semantics(
        label: '歌词来源：$label',
        child: SizedBox(
          key: ValueKey('lyrics_source_$source'),
          width: 27,
          height: 27,
          child: ProviderBrandMark(source: source, scheme: scheme),
        ),
      ),
    );
  }

  Widget _loadingContent(
    ColorScheme scheme,
    bool reduceMotion,
    LyricsState state,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 16,
          child: reduceMotion
              ? Icon(
                  Icons.hourglass_top_rounded,
                  size: 16,
                  color: scheme.primary,
                )
              : CircularProgressIndicator(
                  strokeWidth: 2,
                  strokeCap: StrokeCap.round,
                  color: scheme.primary,
                  backgroundColor: scheme.primaryContainer.withValues(
                    alpha: 0.55,
                  ),
                  semanticsLabel: '歌词加载中',
                ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: PixelAlignedText(
            child: Text(
              _displayText(state),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppState.lyricsTextStyle(scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = AppState.currentScheme;
    final actual = AppState.lyrics.state;
    final hiding =
        AppState.hideUnavailableLyrics &&
        (actual.status == LyricsStatus.failed ||
            actual.status == LyricsStatus.unavailable);
    if (!hiding) _retainedState = actual;
    final state = hiding ? (_retainedState ?? actual) : actual;
    final radius = BorderRadius.circular(24);
    final displayText = _displayText(state);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SmoothRoundedClip(
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
              width: RoundedRasterScale.hairline(context),
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
                    duration: LyricsContentTransition.durationFor(
                      LyricsTransitionStyle.fade,
                      reduceMotion: reduceMotion,
                    ),
                    reverseDuration: LyricsContentTransition.durationFor(
                      LyricsTransitionStyle.fade,
                      reduceMotion: reduceMotion,
                    ),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic.flipped,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.centerLeft,
                      clipBehavior: Clip.hardEdge,
                      children: [...previousChildren, ?currentChild],
                    ),
                    transitionBuilder: _lineTransitionBuilder,
                    child: Align(
                      key: ValueKey(
                        '${state.providerId}:${state.status}:${state.lineIndex}:$displayText',
                      ),
                      alignment: Alignment.centerLeft,
                      child:
                          state.status == LyricsStatus.loading &&
                              AppState.currentPlatformTrack != null
                          ? _loadingContent(scheme, reduceMotion, state)
                          : PixelAlignedText(
                              child: Text(
                                displayText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppState.lyricsTextStyle(
                                  scheme.onSurface,
                                ),
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
