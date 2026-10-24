import 'dart:async';
import 'dart:io';



final class LyricsPrimaryAttempt {
  final Duration budget;
  final Stopwatch _clock = Stopwatch()..start();
  final Set<HttpClientRequest> _requests = {};
  final Set<LyricsPrimaryAttempt> _children = {};
  LyricsPrimaryAttempt? _parent;
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

  LyricsPrimaryAttempt slice(
    Duration maximum, {
    Duration reserve = Duration.zero,
  }) {
    final available = remaining - reserve;
    if (available <= Duration.zero) {
      throw TimeoutException('No lyric phase budget remains');
    }
    final child = LyricsPrimaryAttempt(
      available < maximum ? available : maximum,
    );
    child._parent = this;
    _children.add(child);
    return child;
  }

  Future<HttpClientRequest> open(HttpClient client, Uri uri) async {
    final opening = client.getUrl(uri);
    
    
    unawaited(
      opening.then<void>((request) {
        
        
        
        request.done.ignore();
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
    _parent?._children.remove(this);
    for (final child in _children.toList()) {
      child.close();
    }
    _children.clear();
    for (final request in _requests) {
      request.abort(TimeoutException('Primary lyric lookup timed out'));
    }
    _requests.clear();
    _clock.stop();
  }
}
