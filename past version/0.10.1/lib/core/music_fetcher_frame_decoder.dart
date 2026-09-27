import 'dart:math' as math;
import 'dart:typed_data';

import 'music_fetcher_protocol.dart';


final class MusicFetcherFrameDecoder {
  final void Function(int type, Uint8List payload) onFrame;
  final Uint8List _header = Uint8List(MusicFetcherProtocol.headerSize);
  int _headerLength = 0;
  int _payloadLength = 0;
  int _type = 0;
  Uint8List? _payload;

  MusicFetcherFrameDecoder(this.onFrame);

  void reset() {
    _headerLength = 0;
    _payloadLength = 0;
    _payload = null;
  }

  void add(Uint8List bytes) {
    int offset = 0;
    while (offset < bytes.length) {
      if (_payload == null) {
        final count = math.min(
          _header.length - _headerLength,
          bytes.length - offset,
        );
        _header.setRange(_headerLength, _headerLength + count, bytes, offset);
        offset += count;
        _headerLength += count;
        if (_headerLength < _header.length) return;
        final header = ByteData.sublistView(_header);
        if (header.getUint32(0, Endian.little) != MusicFetcherProtocol.magic ||
            header.getUint8(4) != MusicFetcherProtocol.version) {
          reset();
          throw const FormatException('Invalid MusicFetcher frame header');
        }
        final size = header.getUint32(8, Endian.little);
        if (size > MusicFetcherProtocol.maxPayloadSize) {
          reset();
          throw const FormatException('MusicFetcher payload exceeds limit');
        }
        _type = header.getUint8(5);
        _payload = Uint8List(size);
        _payloadLength = 0;
      }
      final payload = _payload!;
      final count = math.min(
        payload.length - _payloadLength,
        bytes.length - offset,
      );
      payload.setRange(_payloadLength, _payloadLength + count, bytes, offset);
      offset += count;
      _payloadLength += count;
      if (_payloadLength == payload.length) {
        final type = _type;
        reset();
        onFrame(type, payload);
      }
    }
  }
}
