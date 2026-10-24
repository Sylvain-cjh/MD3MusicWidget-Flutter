

final class LyricsReconnectPolicy {
  final Duration window;
  final int maximumAttempts;
  final Duration initialDelay;
  final Duration maximumDelay;

  const LyricsReconnectPolicy({
    this.window = const Duration(minutes: 5),
    this.maximumAttempts = 5,
    this.initialDelay = const Duration(seconds: 15),
    this.maximumDelay = const Duration(seconds: 60),
  }) : assert(maximumAttempts >= 0);

  bool canStart({
    required DateTime now,
    required DateTime windowEnd,
    required int completedAttempts,
  }) => now.isBefore(windowEnd) && completedAttempts < maximumAttempts;

  DateTime? nextAttempt({
    required DateTime now,
    required DateTime windowEnd,
    required int completedAttempts,
    DateTime? serverRetryAt,
  }) {
    if (!canStart(
      now: now,
      windowEnd: windowEnd,
      completedAttempts: completedAttempts,
    )) {
      return null;
    }
    final initial = initialDelay < Duration.zero ? Duration.zero : initialDelay;
    final maximum = maximumDelay < Duration.zero ? Duration.zero : maximumDelay;
    final exponential = initial * (1 << completedAttempts.clamp(0, 20));
    final delay = exponential > maximum ? maximum : exponential;
    var next = now.add(delay);
    if (serverRetryAt != null && serverRetryAt.isAfter(next)) {
      next = serverRetryAt;
    }
    return next.isBefore(windowEnd) ? next : null;
  }
}
