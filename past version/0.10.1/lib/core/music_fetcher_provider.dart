import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'media_provider.dart';
import 'music_fetcher_protocol.dart';
import 'music_fetcher_frame_decoder.dart';

final class MusicFetcherProvider implements MediaProvider {
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

  @override
  Stream<MediaProviderEvent> get events => _events.stream;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<bool> connect() async {
    if (_closed) return false;
    if (_socket != null) return true;
    final int serial = ++_connectionSerial;
    try {
      final Socket socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        12581,
        timeout: const Duration(milliseconds: 450),
      );
      if (serial != _connectionSerial) {
        socket.destroy();
        return false;
      }
      socket.setOption(SocketOption.tcpNoDelay, true);
      _decoder.reset();
      _socket = socket;
      _socketSubscription = socket.listen(
        _handleBytes,
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
      _heartbeatWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
        if (_lastFrame.elapsed > const Duration(seconds: 6)) {
          _handleDisconnect(
            serial,
            const SocketException('Media stream timed out'),
          );
        }
      });
      return true;
    } catch (error) {
      if (serial == _connectionSerial) {
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
    _spectrumEnabled = enabled;
    final Socket? socket = _socket;
    if (socket == null) return;
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
    if (serial != _connectionSerial) return;
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
