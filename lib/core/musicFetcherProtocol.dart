import 'dart:convert';
import 'dart:typed_data';

abstract final class MusicFetcherProtocol {
  static const int magic = 0x3153574d;
  static const int version = 1;
  static const int headerSize = 12;
  static const int maxPayloadSize = 20 * 1024 * 1024;

  static const int infoType = 1;
  static const int spectrumType = 2;
  static const int heartbeatType = 3;
  static const int artworkType = 4;
  static const int setSpectrumType = 16;
  static const int commandType = 17;

  static Uint8List encodeFrame(int type, Uint8List payload) {
    final ByteData frame = ByteData(headerSize + payload.length);
    frame.setUint32(0, magic, Endian.little);
    frame.setUint8(4, version);
    frame.setUint8(5, type);
    frame.setUint16(6, 0, Endian.little);
    frame.setUint32(8, payload.length, Endian.little);
    frame.buffer.asUint8List().setRange(
      headerSize,
      frame.lengthInBytes,
      payload,
    );
    return frame.buffer.asUint8List();
  }

  static MusicFetcherArtwork? decodeArtwork(Uint8List payload) {
    if (payload.length < 3) return null;
    final ByteData data = ByteData.sublistView(payload);
    final int versionLength = data.getUint16(0, Endian.little);
    final int imageOffset = 2 + versionLength;
    if (versionLength <= 0 || imageOffset >= payload.length) return null;
    try {
      final String version = utf8.decode(
        Uint8List.sublistView(payload, 2, imageOffset),
      );
      if (version.isEmpty) return null;
      return MusicFetcherArtwork(
        version,
        Uint8List.fromList(Uint8List.sublistView(payload, imageOffset)),
      );
    } catch (_) {
      return null;
    }
  }
}

final class MusicFetcherArtwork {
  final String version;
  final Uint8List bytes;

  const MusicFetcherArtwork(this.version, this.bytes);
}
