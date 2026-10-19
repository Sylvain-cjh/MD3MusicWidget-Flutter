

final class RecoverableResource<T> {
  final Future<T> Function() load;
  final Duration retryDelay;
  final int maximumAttempts;
  final DateTime Function() clock;
  T? _value;
  Future<T?>? _pending;
  DateTime? retryAt;
  int attempts = 0;
  RecoverableResource({
    required this.load,
    this.retryDelay = const Duration(seconds: 1),
    this.maximumAttempts = 3,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  bool get canRetry => attempts < maximumAttempts;
  Future<T?> get() {
    if (_value != null) return Future.value(_value);
    if (_pending != null) return _pending!;
    if (!canRetry || retryAt?.isAfter(clock()) == true) {
      return Future.value(null);
    }
    attempts++;
    return _pending = Future<T>.sync(load)
        .then<T?>(
          (value) {
            _value = value;
            retryAt = null;
            return value;
          },
          onError: (Object _, StackTrace _) {
            retryAt = clock().add(retryDelay);
            return null;
          },
        )
        .whenComplete(() {
          _pending = null;
        });
  }
}
