import 'dart:async';
import 'dart:io';
import 'dotnetRuntimeService.dart';
import 'ownedFetcherProcess.dart';

final class MusicFetcherRuntime {
  final Directory executableDirectory;
  final Directory workingDirectory;
  final DotnetRuntimeService dotnet;
  final FetcherLauncher _launch;
  OwnedFetcherProcess? _owned;
  Future<int?>? _starting;
  Future<String?>? _preparing;
  bool _closed = false;
  int _generation = 0;

  MusicFetcherRuntime({
    Directory? executableDirectory,
    Directory? workingDirectory,
    DotnetRuntimeService? dotnet,
    FetcherLauncher? launch,
  }) : executableDirectory =
           executableDirectory ?? File(Platform.resolvedExecutable).parent,
       workingDirectory = workingDirectory ?? Directory.current,
       dotnet = dotnet ?? DotnetRuntimeService(),
       _launch = launch ?? WindowsOwnedFetcherProcess.launch;

  File _file(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');
  File get _active => _file(executableDirectory, 'MusicFetcher.exe');
  File get _bundled => _file(
    Directory('${executableDirectory.path}${Platform.pathSeparator}runtime'),
    'MusicFetcher.exe',
  );
  int get ownedPid => _owned?.isAlive == true ? _owned!.pid : 0;

  Future<bool> needsRefresh() async {
    if (_closed || !await _bundled.exists()) return false;
    if (!await _active.exists()) return true;
    try {
      final bundled = await _bundled.stat();
      final active = await _active.stat();
      return active.size != bundled.size ||
          bundled.modified.isAfter(active.modified);
    } catch (_) {
      return true;
    }
  }

  Future<String?> prepareExecutable() {
    if (_closed) return Future.value(null);
    return _preparing ??= _prepareExecutable().whenComplete(
      () => _preparing = null,
    );
  }

  Future<String?> _prepareExecutable() async {
    if (_closed) return null;
    await stopOwned();
    if (_closed) return null;
    if (await _bundled.exists()) {
      try {
        if (await needsRefresh()) await _bundled.copy(_active.path);
      } catch (_) {
         
      }
      return await _active.exists() ? _active.path : _bundled.path;
    }
    if (await _active.exists()) return _active.path;
    final working = _file(workingDirectory, 'MusicFetcher.exe');
    return await working.exists() ? working.path : null;
  }

  Future<int?> start(String executable) {
    if (_closed) return Future.value(null);
    if (ownedPid > 0) return Future.value(ownedPid);
    return _starting ??= _start(
      executable,
    ).whenComplete(() => _starting = null);
  }

  Future<int?> _start(String executable) async {
    final generation = _generation;
    final process = await _launch(File(executable).absolute.path);
    if (_closed || generation != _generation) {
      await process.stop();
      return null;
    }
    await _owned?.stop();
    if (_closed || generation != _generation) {
      await process.stop();
      return null;
    }
    _owned = process;
    return process.isAlive ? process.pid : null;
  }

  Future<void> stopOwned() async {
    _generation++;
    final process = _owned;
    _owned = null;
    await process?.stop();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    dotnet.close();
    await stopOwned();
    
    try {
      await _starting?.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
