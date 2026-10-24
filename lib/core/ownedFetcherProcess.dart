import 'dart:ffi';
import 'dart:io';

abstract interface class OwnedFetcherProcess {
  int get pid;
  bool get isAlive;
  Future<void> stop();
}

typedef FetcherLauncher =
    Future<OwnedFetcherProcess> Function(String executable);



final class WindowsOwnedFetcherProcess implements OwnedFetcherProcess {
  @override
  final int pid;
  int _handle;
  WindowsOwnedFetcherProcess._(this.pid, this._handle);

  static final _kernel = DynamicLibrary.open('kernel32.dll');
  static final _open = _kernel
      .lookupFunction<
        IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)
      >('OpenProcess');
  static final _wait = _kernel
      .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
        'WaitForSingleObject',
      );
  static final _terminate = _kernel
      .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
        'TerminateProcess',
      );
  static final _close = _kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  static Future<OwnedFetcherProcess> launch(String executable) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows capture helper required');
    }
    final process = await Process.start(
      executable,
      const [],
      mode: ProcessStartMode.detached,
    );
    
    final handle = _open(0x0001 | 0x00100000, 0, process.pid);
    if (handle == 0) {
      throw StateError('Could not retain the launched capture process');
    }
    return WindowsOwnedFetcherProcess._(process.pid, handle);
  }

  @override
  bool get isAlive => _handle != 0 && _wait(_handle, 0) == 258;

  @override
  Future<void> stop() async {
    final handle = _handle;
    if (handle == 0) return;
    _handle = 0;
    try {
      if (_wait(handle, 0) == 258 && _terminate(handle, 1) == 0) {
        throw StateError('Could not stop the owned capture process');
      }
      final clock = Stopwatch()..start();
      while (_wait(handle, 0) == 258) {
        if (clock.elapsed >= const Duration(seconds: 2)) {
          throw StateError('Owned capture process did not exit in time');
        }
        
        
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      _close(handle);
    }
  }
}
