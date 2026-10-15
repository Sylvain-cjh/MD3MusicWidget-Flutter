import 'dart:async';
import 'dart:io';



final class LyricsPrimaryAttempt {
  final Duration budget;
  final Stopwatch _clock = Stopwatch()..start();
  final Set<HttpClientRequest> _requests = {};
  late final Timer _deadline;
  bool _closed = false;

  LyricsPrimaryAttempt(this.budget) {
    _deadline = Timer(budget, close);
  }

  Duration get remaining {
    final value = budget - _clock.elapsed;
    if (_closed || value <= Duration.zero) {
      throw TimeoutException('Primary lyric lookup timed out');
    }
    return value;
  }

  Future<T> run<T>(Future<T> Function() load) async {
    try {
      return await load().timeout(remaining);
    } finally {
      close();
    }
  }

  Future<HttpClientRequest> open(HttpClient client, Uri uri) async {
    final opening = client.getUrl(uri);
    
    
    unawaited(
      opening.then<void>((request) {
        if (_closed) {
          request.abort(TimeoutException('Primary lyrics cancelled'));
        }
      }, onError: (Object _) {}),
    );
    final request = await opening.timeout(remaining);
    if (_closed) {
      request.abort();
      throw TimeoutException('Primary lyric lookup timed out');
    }
    _requests.add(request);
    return request;
  }

  void release(HttpClientRequest request) => _requests.remove(request);

  void close() {
    if (_closed) return;
    _closed = true;
    _deadline.cancel();
    for (final request in _requests) {
      request.abort(TimeoutException('Primary lyric lookup timed out'));
    }
    _requests.clear();
    _clock.stop();
  }
}
