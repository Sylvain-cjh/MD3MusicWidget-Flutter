import 'dart:async';



final class WindowGeometryQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> read<T>(Future<T> Function() operation) => _enqueue(operation);

  Future<void> write(
    Future<void> Function() operation, {
    required bool Function() isCurrent,
  }) => _enqueue(() async {
    if (isCurrent()) await operation();
  });

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    
    
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
