import 'dart:io';


final class LyricsRateLimitException extends HttpException {
  final String providerId;
  final DateTime retryAt;
  final bool fromServer;

  const LyricsRateLimitException({
    required this.providerId,
    required this.retryAt,
    required this.fromServer,
  }) : super('Lyric service rate limited the request');
}



DateTime lyricsRetryDeadline(
  String? value, {
  required DateTime now,
  String? serverDate,
  Duration fallback = const Duration(seconds: 30),
}) {
  final text = value?.trim() ?? '';
  Duration? delay;
  if (RegExp(r'^\d+$').hasMatch(text)) {
    final seconds = int.tryParse(text);
    if (seconds != null && seconds <= 8640000000000) {
      delay = Duration(seconds: seconds);
    }
  } else if (text.isNotEmpty) {
    try {
      final deadline = HttpDate.parse(text);
      DateTime reference = now;
      if (serverDate != null) {
        try {
          reference = HttpDate.parse(serverDate);
        } on HttpException catch (_) {
          
        }
      }
      delay = deadline.difference(reference);
    } on HttpException catch (_) {
      
    }
  }
  final effective = delay ?? fallback;
  try {
    return now.add(
      effective < const Duration(seconds: 1)
          ? const Duration(seconds: 1)
          : effective,
    );
  } on ArgumentError catch (_) {
    return DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true);
  }
}
