import 'dart:async';



final class DemandPollingLoop {
  final Duration interval;
  final Future<void> Function() poll;
  final void Function(Object, StackTrace)? onError;
  Timer? _timer;
  bool _active = false, _inFlight = false;
  int ticks = 0;
  DemandPollingLoop({required this.interval, required this.poll, this.onError});
  bool get active => _active;
  void setActive(bool value, {bool immediate = false}) {
    if (_active == value) return;
    _active = value;
    _timer?.cancel();
    _timer = null;
    if (!value) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
    if (immediate) unawaited(_tick());
  }

  Future<void> _tick() async {
    if (!_active || _inFlight) return;
    ticks++;
    _inFlight = true;
    try {
      await poll();
    } catch (error, stack) {
      onError?.call(error, stack);
    } finally {
      _inFlight = false;
    }
  }

  void cancel() => setActive(false);
}
