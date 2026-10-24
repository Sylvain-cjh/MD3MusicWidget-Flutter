import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'mediaCaptureBackend.dart';
import 'mediaProvider.dart';
import 'musicFetcherProvider.dart';
import 'musicSourceService.dart';

final class MusicFetcherBackend
    implements MediaCaptureBackend, LegacyMediaReader {
  final MediaProvider _provider;
  final MusicSourceClient _sources;
  final HttpClient _commands;
  final HttpClient _legacy;
  final Uri _baseUri;
  bool _closed = false;

  MusicFetcherBackend({
    MediaProvider? provider,
    MusicSourceClient? sources,
    HttpClient? commandClient,
    HttpClient? legacyClient,
    Uri? baseUri,
  }) : _provider = provider ?? MusicFetcherProvider(),
       _sources = sources ?? HttpMusicSourceClient(baseUri: baseUri),
       _commands = commandClient ?? HttpClient(),
       _legacy = legacyClient ?? HttpClient(),
       _baseUri = baseUri ?? Uri.parse('http://localhost:12580') {
    _commands
      ..connectionTimeout = const Duration(milliseconds: 350)
      ..idleTimeout = const Duration(seconds: 2)
      ..maxConnectionsPerHost = 2;
    _commands.findProxy = (_) => 'DIRECT';
    _legacy
      ..connectionTimeout = const Duration(milliseconds: 350)
      ..idleTimeout = const Duration(seconds: 2)
      ..maxConnectionsPerHost = 3
      ..findProxy = (_) => 'DIRECT';
  }

  @override
  Future<Uint8List> readLegacyResponse(
    Uri resource, {
    required Duration timeout,
  }) async {
    if (_closed) throw StateError('Media backend closed');
    
    final uri = _baseUri.replace(path: resource.path, query: resource.query);
    HttpClientRequest? request;
    var cancelled = false;
    try {
      return await (() async {
        final opened = await _legacy.getUrl(uri);
        request = opened;
        if (_closed || cancelled) {
          opened.abort();
          throw StateError('Media read cancelled');
        }
        opened.persistentConnection = false;
        final response = await opened.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'MusicFetcher returned HTTP ${response.statusCode}',
            uri: uri,
          );
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (_closed || cancelled) throw StateError('Media read cancelled');
          builder.add(chunk);
        }
        return builder.takeBytes();
      })().timeout(timeout);
    } catch (_) {
      cancelled = true;
      request?.abort();
      rethrow;
    }
  }

  @override
  Future<int?> waitUntilReady({
    Duration maxWait = const Duration(milliseconds: 1800),
  }) async {
    final clock = Stopwatch()..start();
    var delayMs = 35;
    while (!_closed && clock.elapsed < maxWait) {
      final remaining = maxWait - clock.elapsed;
      try {
        final bytes = await readLegacyResponse(
          Uri(path: '/info'),
          timeout: remaining < const Duration(milliseconds: 160)
              ? remaining
              : const Duration(milliseconds: 160),
        );
        final info = jsonDecode(utf8.decode(bytes));
        final pid = info is Map ? info['processId'] : null;
        if (!_closed && clock.elapsed <= maxWait && pid is int && pid > 0) {
          return pid;
        }
      } catch (_) {}
      final left = maxWait - clock.elapsed;
      if (_closed || left <= Duration.zero) break;
      final delay = Duration(milliseconds: delayMs);
      await Future<void>.delayed(left < delay ? left : delay);
      if (delayMs < 115) delayMs += 20;
    }
    return null;
  }

  @override
  bool get usesExternalProcess => true;
  @override
  bool get supportsLegacyPolling => true;
  @override
  Stream<MediaProviderEvent> get events => _provider.events;
  @override
  bool get isConnected => !_closed && _provider.isConnected;
  @override
  Future<bool> connect() async {
    if (_closed) return false;
    final connected = await _provider.connect();
    return !_closed && connected;
  }

  @override
  void setSpectrumEnabled(bool enabled) {
    if (!_closed) _provider.setSpectrumEnabled(enabled);
  }

  @override
  bool sendCommand(MediaCommand command) =>
      !_closed && _provider.sendCommand(command);
  @override
  Future<MusicSourceSnapshot> fetchSources() {
    if (_closed) throw StateError('Media backend closed');
    return _sources.fetchSources();
  }

  @override
  Future<void> selectSource(String id) {
    if (_closed) throw StateError('Media backend closed');
    return _sources.selectSource(id);
  }

  @override
  Future<bool> dispatchCommand(MediaCommand command) async {
    if (_closed) return false;
    if (sendCommand(command)) return true;
    HttpClientRequest? request;
    try {
      request = await _commands
          .getUrl(
            _baseUri
                .resolve('/command')
                .replace(queryParameters: {'cmd': command.httpValue}),
          )
          .timeout(const Duration(milliseconds: 350));
      if (_closed) {
        request.abort();
        return false;
      }
      request.persistentConnection = false;
      final response = await request.close().timeout(
        const Duration(milliseconds: 500),
      );
      final accepted = response.statusCode >= 200 && response.statusCode < 300;
      await response.drain<void>().timeout(const Duration(milliseconds: 500));
      return !_closed && accepted;
    } catch (_) {
      request?.abort();
      return false;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _commands.close(force: true);
    _legacy.close(force: true);
    try {
      _sources.close();
    } finally {
      await _provider.close();
    }
  }
}
