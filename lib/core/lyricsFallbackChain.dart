import 'lyricsDocument.dart';
import 'platformProvider.dart';
import 'lyricsRequestError.dart';



final class LyricsFallbackChain
    implements
        LyricsPlatformProvider,
        RetryableLyricsProvider,
        WordTimingLyricsProvider,
        ExhaustiveLyricsProvider {
  @override
  final String id;
  final List<LyricsPlatformProvider> sources;
  LyricsFallbackChain({
    required this.id,
    required List<LyricsPlatformProvider> sources,
  }) : sources = List.unmodifiable(sources);
  @override
  bool accepts(PlatformTrack track) =>
      sources.any((source) => source.accepts(track));
  @override
  Future<LyricsDocument?> loadLyrics(PlatformTrack track) async {
    Object? failure;
    StackTrace? trace;
    for (final source in sources) {
      if (!source.accepts(track)) continue;
      try {
        final doc = await source.loadLyrics(track);
        if (doc != null && !doc.isEmpty) {
          final sourced = doc.sourceProviderId.isEmpty
              ? doc.withSourceProviderId(source.id)
              : doc;
          return sourced.isWordTimed
              ? sourced
              : sourced.withWordTimingRetryAt(
                  DateTime.now().add(const Duration(minutes: 30)),
                );
        }
      } catch (error, stack) {
        if (failure == null ||
            error is LyricsRateLimitException &&
                failure is! LyricsRateLimitException) {
          failure = error;
          trace = stack;
        }
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    return null;
  }

  @override
  void invalidateMiss(PlatformTrack track) {
    for (final source in sources) {
      if (source is RetryableLyricsProvider) {
        (source as RetryableLyricsProvider).invalidateMiss(track);
      }
    }
  }

  @override
  Future<LyricsDocument?> upgradeWordTiming(PlatformTrack track) async {
    Object? failure;
    StackTrace? trace;
    for (final source in sources) {
      if (source is! WordTimingLyricsProvider) continue;
      try {
        final document = await (source as WordTimingLyricsProvider)
            .upgradeWordTiming(track);
        if (document?.isWordTimed == true) return document;
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    return null;
  }
}
