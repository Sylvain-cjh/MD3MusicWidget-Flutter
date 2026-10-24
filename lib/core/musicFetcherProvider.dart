import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'mediaProvider.dart';
import 'musicFetcherProtocol.dart';
import 'musicFetcherFrameDecoder.dart';

typedef MediaSocketConnector =
    Future<Socket> Function(
      InternetAddress address,
      int port,
      Duration timeout,
    );

final class MusicFetcherProvider implements MediaProvider {
  final int port;
  final Duration connectTimeout;
  final Duration watchdogInterval;
  final Duration heartbeatTimeout;
  final MediaSocketConnector _connectSocket;
  Future<bool>? _connecting;

  MusicFetcherProvider({
    this.port = 12581,
    this.connectTimeout = const Duration(milliseconds: 450),
    this.watchdogInterval = const Duration(seconds: 2),
    this.heartbeatTimeout = const Duration(seconds: 6),
    MediaSocketConnector? connectSocket,
  }) : _connectSocket =
           connectSocket ??
           ((address, port, timeout) =>
               Socket.connect(address, port, timeout: timeout));

  final StreamController<MediaProviderEvent> _events =
      StreamController<MediaProviderEvent>.broadcast(sync: true);
  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;
  late final MusicFetcherFrameDecoder _decoder = MusicFetcherFrameDecoder(
    _handleFrame,
  );
  Timer? _heartbeatWatchdog;
  final Stopwatch _lastFrame = Stopwatch();
  bool _closed = false;
  int _connectionSerial = 0;
  bool _spectrumEnabled = false;
  bool? _sentSpectrumEnabled;

  @override
  Stream<MediaProviderEvent> get events => _events.stream;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<bool> connect() {
    if (_closed) return Future.value(false);
    if (_socket != null) return Future.value(true);
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<bool> _connect() async {
    final int serial = ++_connectionSerial;
    try {
      final Socket socket = await _connectSocket(
        InternetAddress.loopbackIPv4,
        port,
        connectTimeout,
      );
      if (_closed || serial != _connectionSerial) {
        socket.destroy();
        return false;
      }
      socket.setOption(SocketOption.tcpNoDelay, true);
      _decoder.reset();
      _socket = socket;
      _sentSpectrumEnabled = null;
      _socketSubscription = socket.listen(
        (chunk) {
          if (!_closed && serial == _connectionSerial) _handleBytes(chunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          _handleDisconnect(serial, error);
        },
        onDone: () => _handleDisconnect(serial),
        cancelOnError: true,
      );
      setSpectrumEnabled(_spectrumEnabled);
      _lastFrame
        ..reset()
        ..start();
      _heartbeatWatchdog?.cancel();
      _heartbeatWatchdog = Timer.periodic(watchdogInterval, (_) {
        if (_lastFrame.elapsed > heartbeatTimeout) {
          _handleDisconnect(
            serial,
            const SocketException('Media stream timed out'),
          );
        }
      });
      return true;
    } catch (error) {
      if (!_closed && serial == _connectionSerial) {
        _events.add(MediaDisconnectedEvent(error));
      }
      return false;
    }
  }

  void _handleBytes(Uint8List chunk) {
    try {
      _decoder.add(chunk);
    } on FormatException catch (error) {
      _handleDisconnect(_connectionSerial, error);
    }
  }

  void _handleFrame(int type, Uint8List payload) {
    if (_closed) return;
    _lastFrame.reset();
    try {
      switch (type) {
        case MusicFetcherProtocol.infoType:
          final Object? decoded = jsonDecode(utf8.decode(payload));
          if (decoded is Map) {
            _events.add(
              MediaSnapshotEvent(
                MediaSnapshot.fromJson(Map<String, dynamic>.from(decoded)),
              ),
            );
          }
          break;
        case MusicFetcherProtocol.spectrumType:
          _events.add(MediaSpectrumEvent(payload));
          break;
        case MusicFetcherProtocol.heartbeatType:
          _events.add(const MediaHeartbeatEvent());
          break;
        case MusicFetcherProtocol.artworkType:
          final MusicFetcherArtwork? artwork =
              MusicFetcherProtocol.decodeArtwork(payload);
          if (artwork != null) {
            _events.add(MediaArtworkEvent(artwork.version, artwork.bytes));
          }
          break;
      }
    } catch (_) {
      
    }
  }

  @override
  void setSpectrumEnabled(bool enabled) {
    if (_closed) return;
    _spectrumEnabled = enabled;
    final Socket? socket = _socket;
    if (socket == null) return;
    if (_sentSpectrumEnabled == enabled) return;
    _sentSpectrumEnabled = enabled;
    final Uint8List payload = Uint8List.fromList(<int>[enabled ? 1 : 0]);
    socket.add(
      MusicFetcherProtocol.encodeFrame(
        MusicFetcherProtocol.setSpectrumType,
        payload,
      ),
    );
  }

  @override
  bool sendCommand(MediaCommand command) {
    if (_closed) return false;
    final Socket? socket = _socket;
    if (socket == null) return false;
    socket.add(
      MusicFetcherProtocol.encodeFrame(
        MusicFetcherProtocol.commandType,
        Uint8List.fromList(<int>[command.wireValue]),
      ),
    );
    return true;
  }

  void _handleDisconnect(int serial, [Object? error]) {
    if (_closed || serial != _connectionSerial) return;
    _connectionSerial++;
    _heartbeatWatchdog?.cancel();
    _lastFrame.stop();
    unawaited(_socketSubscription?.cancel());
    _socketSubscription = null;
    _socket?.destroy();
    _socket = null;
    _decoder.reset();
    _events.add(MediaDisconnectedEvent(error));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _connectionSerial++;
    _heartbeatWatchdog?.cancel();
    _lastFrame.stop();
    final StreamSubscription<Uint8List>? subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) await subscription.cancel();
    _socket?.destroy();
    _socket = null;
    _decoder.reset();
    await _events.close();
  }
}
