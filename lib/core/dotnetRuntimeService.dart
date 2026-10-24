import 'dart:async';
import 'dart:io';

typedef RuntimeCommand =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef RuntimeInstaller = Future<int> Function(String executable);

final class DotnetRuntimeService {
  static final downloadUri = Uri.parse(
    'https://aka.ms/dotnet/8.0/dotnet-runtime-win-x64.exe',
  );
  final bool isWindows;
  final Directory sharedRuntime;
  final RuntimeCommand _run;
  final RuntimeInstaller _install;
  final HttpClient _client;
  bool _closed = false;
  Future<bool>? _installing;

  DotnetRuntimeService({
    bool? isWindows,
    Directory? sharedRuntime,
    RuntimeCommand? run,
    RuntimeInstaller? install,
    HttpClient? client,
  }) : isWindows = isWindows ?? Platform.isWindows,
       sharedRuntime =
           sharedRuntime ??
           Directory(r'C:\Program Files\dotnet\shared\Microsoft.NETCore.App'),
       _run = run ?? ((executable, args) => Process.run(executable, args)),
       _install = install ?? _runInstaller,
       _client = client ?? HttpClient();

  static Future<int> _runInstaller(String executable) async {
    final process = await Process.start(executable, const [
      '/install',
      '/passive',
      '/norestart',
    ]);
    
    final output = process.stdout.drain<void>();
    final errors = process.stderr.drain<void>();
    final code = await process.exitCode.timeout(const Duration(minutes: 5));
    await Future.wait([output, errors]);
    return code;
  }

  Future<bool> isAvailable() async {
    if (_closed) return false;
    if (!isWindows) return true;
    try {
      if (await sharedRuntime.exists()) {
        await for (final entry in sharedRuntime.list(followLinks: false)) {
          if (_closed) return false;
          final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (entry is Directory && RegExp(r'^8\.\d+\.\d+').hasMatch(name)) {
            return true;
          }
        }
      }
    } catch (_) {}
    for (final executable in [
      r'C:\Program Files\dotnet\dotnet.exe',
      'dotnet.exe',
    ]) {
      if (_closed) return false;
      try {
        final result = await _run(executable, const [
          '--list-runtimes',
        ]).timeout(const Duration(milliseconds: 1400));
        if (!_closed &&
            result.exitCode == 0 &&
            RegExp(
              r'Microsoft\.NETCore\.App\s+8\.',
            ).hasMatch(result.stdout.toString())) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  Future<bool> installOnline() {
    if (_closed) return Future.value(false);
    return _installing ??= _downloadAndInstall().whenComplete(
      () => _installing = null,
    );
  }

  Future<bool> _downloadAndInstall() async {
    Directory? temporary;
    try {
      temporary = await Directory.systemTemp.createTemp(
        'md3_music_widget_dotnet_',
      );
      if (_closed) return false;
      final file = File(
        '${temporary.path}${Platform.pathSeparator}dotnet-runtime-win-x64.exe',
      );
      final request = await _client
          .getUrl(downloadUri)
          .timeout(const Duration(seconds: 20));
      if (_closed) {
        request.abort();
        return false;
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().timeout(const Duration(seconds: 20));
        return false;
      }
      await response.pipe(file.openWrite()).timeout(const Duration(minutes: 2));
      if (_closed) return false;
      final code = await _install(file.path);
      return !_closed && (code == 0 || code == 3010);
    } catch (_) {
      return false;
    } finally {
      if (temporary != null) {
        final full = temporary.absolute.path;
        final parent = Directory.systemTemp.absolute.path;
        
        if (full.startsWith('$parent${Platform.pathSeparator}') &&
            temporary.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('md3_music_widget_dotnet_')) {
          try {
            if (await temporary.exists()) {
              await temporary.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
  }
}
