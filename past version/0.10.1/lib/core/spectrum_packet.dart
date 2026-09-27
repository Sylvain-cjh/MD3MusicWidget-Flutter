import 'dart:typed_data';

typedef SpectrumPacket = ({
  Float32List levels,
  int updatedAtMs,
  bool available,
});

const int spectrumPacketVersion = 1;
const int spectrumPacketHeaderSize = 12;

SpectrumPacket? decodeSpectrumPacket(
  Uint8List bytes, {
  required int expectedBandCount,
  Float32List? targetLevels,
}) {
  final int expectedLength =
      spectrumPacketHeaderSize +
      expectedBandCount * Float32List.bytesPerElement;
  if (bytes.length != expectedLength) return null;

  final ByteData data = ByteData.sublistView(bytes);
  if (data.getUint8(0) != spectrumPacketVersion) return null;
  final int bandCount = data.getUint16(2, Endian.little);
  if (bandCount != expectedBandCount) return null;
  if (targetLevels != null && targetLevels.length != expectedBandCount) {
    return null;
  }

  final levels = targetLevels ?? Float32List(expectedBandCount);
  for (int i = 0; i < expectedBandCount; i++) {
    final double value = data.getFloat32(
      spectrumPacketHeaderSize + i * Float32List.bytesPerElement,
      Endian.little,
    );
    levels[i] = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
  }
  return (
    levels: levels,
    updatedAtMs: data.getInt64(4, Endian.little),
    available: data.getUint8(1) & 1 != 0,
  );
}
