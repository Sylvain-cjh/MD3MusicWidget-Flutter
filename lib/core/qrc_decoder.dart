import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

typedef _DecodeNative = Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32);
typedef _Decode = int Function(Pointer<Uint8>, Pointer<Uint8>, int);
final _decoders = <String, _Decode>{};


Future<String?> decodeQrcPayload(String encoded, {String? libraryDirectory}) {
  final directory =
      libraryDirectory ?? File(Platform.resolvedExecutable).parent.path;
  return Isolate.run(() => _decode(encoded, directory));
}

String? _decode(String encoded, String directory) {
  if (!Platform.isWindows || encoded.length > 1024 * 1024) return null;
  final hex = encoded.trim();
  if (hex.startsWith('[') || hex.startsWith('<')) return hex;
  if (hex.isEmpty ||
      hex.length % 16 != 0 ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
    return null;
  }
  final path = '$directory${Platform.pathSeparator}qrc_codec.dll';
  if (!File(path).existsSync()) return null;
  final length = hex.length ~/ 2;
  Pointer<Uint8>? input, output;
  try {
    final decode = _decoders.putIfAbsent(
      path,
      () => DynamicLibrary.open(
        path,
      ).lookupFunction<_DecodeNative, _Decode>('md3_qrc_decode'),
    );
    input = calloc<Uint8>(length);
    output = calloc<Uint8>(length);
    for (var index = 0; index < length; index++) {
      input[index] = int.parse(
        hex.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    if (decode(input, output, length) != 0) return null;
    final sink = _BoundedLyricBytes();
    final decoder = ZLibDecoder().startChunkedConversion(sink);
    final data = output.asTypedList(length);
    for (var offset = 0; offset < length; offset += 256) {
      decoder.add(data.sublist(offset, (offset + 256).clamp(0, length)));
    }
    decoder.close();
    return utf8.decode(sink.bytes.takeBytes()).replaceFirst('\ufeff', '');
  } catch (_) {
    return null;
  } finally {
    if (input != null) calloc.free(input);
    if (output != null) calloc.free(output);
  }
}

class _BoundedLyricBytes extends ByteConversionSink {
  final bytes = BytesBuilder(copy: false);
  int count = 0;
  @override
  void add(List<int> chunk) {
    count += chunk.length;
    if (count > 2 * 1024 * 1024) {
      throw const FormatException('Decoded QRC is too large');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
