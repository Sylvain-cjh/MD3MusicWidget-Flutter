import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'media_provider.dart';

final class MusicFetcherProvider implements MediaProvider {
  static const int _magic = 0x3153574d;
  static const int _protocolVersion = 1;
  static const int _headerSize = 12;
  static const int _maxPayloadSize = 16 * 1024 * 1024;

  static const int _typeInfo = 1;
  static const int _typeSpectrum = 2;
  static const int _typeHeartbeat = 3;
  static const int _typeSetSpectrum = 16;

  final StreamController<MediaProviderEvent> _events =
      StreamController<MediaProviderEvent>.broadcast(sync: true);
  Socket? _socket;
  StreamSubscription<Uint8List>? _socketSubscription;
  Uint8List _pending = Uint8List(0);
  int _connectionSerial = 0;
  bool _spectrumEnabled = false;

  @override
  Stream<MediaProviderEvent> get events => _events.stream;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<bool> connect() async {
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
      _pending = Uint8List(0);
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
      return true;
    } catch (error) {
      if (serial == _connectionSerial) {
        _events.add(MediaDisconnectedEvent(error));
      }
      return false;
    }
  }

  void _handleBytes(Uint8List chunk) {
    if (chunk.isEmpty) return;
    final Uint8List combined = Uint8List(_pending.length + chunk.length)
      ..setRange(0, _pending.length, _pending)
      ..setRange(_pending.length, _pending.length + chunk.length, chunk);
    int offset = 0;
    while (combined.length - offset >= _headerSize) {
      final ByteData header = ByteData.sublistView(
        combined,
        offset,
        offset + _headerSize,
      );
      if (header.getUint32(0, Endian.little) != _magic ||
          header.getUint8(4) != _protocolVersion) {
        _socket?.destroy();
        return;
      }
      final int type = header.getUint8(5);
      final int payloadLength = header.getUint32(8, Endian.little);
      if (payloadLength > _maxPayloadSize) {
        _socket?.destroy();
        return;
      }
      final int frameLength = _headerSize + payloadLength;
      if (combined.length - offset < frameLength) break;
      final Uint8List payload = Uint8List.sublistView(
        combined,
        offset + _headerSize,
        offset + frameLength,
      );
      _handleFrame(type, payload);
      offset += frameLength;
    }
    _pending = offset == combined.length
        ? Uint8List(0)
        : Uint8List.fromList(combined.sublist(offset));
  }

  void _handleFrame(int type, Uint8List payload) {
    try {
      switch (type) {
        case _typeInfo:
          final Object? decoded = jsonDecode(utf8.decode(payload));
          if (decoded is Map) {
            _events.add(
              MediaSnapshotEvent(
                MediaSnapshot.fromJson(Map<String, dynamic>.from(decoded)),
              ),
            );
          }
          break;
        case _typeSpectrum:
          _events.add(MediaSpectrumEvent(Uint8List.fromList(payload)));
          break;
        case _typeHeartbeat:
          _events.add(const MediaHeartbeatEvent());
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
    socket.add(_encodeFrame(_typeSetSpectrum, payload));
  }

  Uint8List _encodeFrame(int type, Uint8List payload) {
    final ByteData frame = ByteData(_headerSize + payload.length);
    frame.setUint32(0, _magic, Endian.little);
    frame.setUint8(4, _protocolVersion);
    frame.setUint8(5, type);
    frame.setUint16(6, 0, Endian.little);
    frame.setUint32(8, payload.length, Endian.little);
    frame.buffer.asUint8List().setRange(
      _headerSize,
      frame.lengthInBytes,
      payload,
    );
    return frame.buffer.asUint8List();
  }

  void _handleDisconnect(int serial, [Object? error]) {
    if (serial != _connectionSerial) return;
    _socketSubscription = null;
    _socket?.destroy();
    _socket = null;
    _pending = Uint8List(0);
    _events.add(MediaDisconnectedEvent(error));
  }

  @override
  Future<void> close() async {
    _connectionSerial++;
    final StreamSubscription<Uint8List>? subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) await subscription.cancel();
    await _socket?.close();
    _socket = null;
    await _events.close();
  }
}
