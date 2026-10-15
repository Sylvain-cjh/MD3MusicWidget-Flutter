import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

final class GpuCoverPixels {
  final Uint8List? mask, background;
  final Uint8List? priority, textRepair;
  final int width, height;
  final String detail;
  const GpuCoverPixels(
    this.mask,
    this.background,
    this.width,
    this.height,
    this.detail, {
    this.priority,
    this.textRepair,
  });
  bool get usedGpu =>
      mask != null &&
      background != null &&
      detail.startsWith('gpu:integrated:');
}

typedef _PrepareNative =
    Int32 Function(
      Pointer<Uint16>,
      Pointer<Uint8>,
      Int32,
      Int32,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Int32,
      Int32,
      Pointer<Uint8>,
      Int32,
    );
typedef _Prepare =
    int Function(
      Pointer<Uint16>,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Uint8>,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Uint8>,
      int,
    );
typedef _PrepareSceneNative =
    Int32 Function(
      Pointer<Uint16>,
      Pointer<Uint8>,
      Int32,
      Int32,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Int32,
      Int32,
      Pointer<Uint8>,
      Int32,
    );
typedef _PrepareScene =
    int Function(
      Pointer<Uint16>,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Uint8>,
      int,
    );




GpuCoverPixels prepareGpuCover(
  Uint8List pixels,
  int width,
  int height, {
  String? executableDirectory,
  String? runtimeDirectory,
}) {
  if (!Platform.isWindows ||
      width < 2 ||
      height < 2 ||
      width > 2048 ||
      height > 2048 ||
      pixels.length != width * height * 4) {
    return const GpuCoverPixels(null, null, 0, 0, 'gpu_input_unavailable');
  }
  final directory =
      executableDirectory ?? File(Platform.resolvedExecutable).parent.path;
  final libraryFile = File('$directory\\cover_layers_gpu.dll');
  if (!libraryFile.existsSync()) {
    return const GpuCoverPixels(null, null, 0, 0, 'gpu_backend_missing');
  }
  final rootPath = runtimeDirectory ?? '$directory\\runtime\\cover_gpu';
  late DynamicLibrary library;
  late bool scene;
  try {
    library = DynamicLibrary.open(libraryFile.path);
    if (!library.providesSymbol('cover_layers_gpu_policy')) {
      return const GpuCoverPixels(
        null,
        null,
        0,
        0,
        'gpu_integrated_only_policy_required',
      );
    }
    final policyPointer = library
        .lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
          'cover_layers_gpu_policy',
        )();
    final policyBytes = <int>[];
    if (policyPointer != nullptr) {
      for (var i = 0; i < 128; i++) {
        final value = policyPointer[i];
        if (value == 0) break;
        policyBytes.add(value);
      }
    }
    if (utf8.decode(policyBytes, allowMalformed: true) !=
        'integrated-only-no-discrete-or-cpu-fallback') {
      return const GpuCoverPixels(
        null,
        null,
        0,
        0,
        'gpu_development_backend_not_allowed',
      );
    }
    scene = library.providesSymbol('cover_layers_prepare_scene');
  } catch (error) {
    return GpuCoverPixels(null, null, 0, 0, 'gpu_backend_error:$error');
  }
  
  final scale = scene ? 1.0 : math.min(1.0, 768 / math.max(width, height));
  final outWidth = math.max(2, (width * scale).round());
  final outHeight = math.max(2, (height * scale).round());
  final outputBytes = outWidth * outHeight * 4;
  final memory = <Pointer<Void>>[];
  late void Function(Pointer<Void>) free;
  try {
    final crt = DynamicLibrary.open('ucrtbase.dll');
    final malloc = crt
        .lookupFunction<
          Pointer<Void> Function(IntPtr),
          Pointer<Void> Function(int)
        >('malloc');
    free = crt
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    Pointer<Void> allocate(int size) {
      final p = malloc(size);
      if (p == nullptr) throw StateError('gpu_transfer_allocation_failed');
      memory.add(p);
      return p;
    }

    final path = allocate((rootPath.length + 1) * 2).cast<Uint16>();
    path.asTypedList(rootPath.length + 1)
      ..setAll(0, rootPath.codeUnits)
      ..[rootPath.length] = 0;
    final source = allocate(pixels.length).cast<Uint8>();
    source.asTypedList(pixels.length).setAll(0, pixels);
    final mask = allocate(outputBytes).cast<Uint8>();
    final background = allocate(outputBytes).cast<Uint8>();
    final priority = scene ? allocate(outputBytes).cast<Uint8>() : nullptr;
    final textRepair = scene ? allocate(outputBytes).cast<Uint8>() : nullptr;
    final message = allocate(2048).cast<Uint8>();
    message.asTypedList(2048).fillRange(0, 2048, 0);
    final code = scene
        ? library.lookupFunction<_PrepareSceneNative, _PrepareScene>(
            'cover_layers_prepare_scene',
          )(
            path,
            source,
            width,
            height,
            mask,
            background,
            priority,
            textRepair,
            outWidth,
            outHeight,
            message,
            2048,
          )
        : library.lookupFunction<_PrepareNative, _Prepare>(
            'cover_layers_prepare',
          )(
            path,
            source,
            width,
            height,
            mask,
            background,
            outWidth,
            outHeight,
            message,
            2048,
          );
    final detail = utf8.decode(
      message.asTypedList(2048).takeWhile((b) => b != 0).toList(),
      allowMalformed: true,
    );
    if (code != 0 || !detail.startsWith('gpu:integrated:')) {
      return GpuCoverPixels(null, null, 0, 0, detail);
    }
    
    
    final advancedScene = scene && detail.contains(';scene=1');
    return GpuCoverPixels(
      Uint8List.fromList(mask.asTypedList(outputBytes)),
      Uint8List.fromList(background.asTypedList(outputBytes)),
      outWidth,
      outHeight,
      detail,
      priority: advancedScene
          ? Uint8List.fromList(priority.asTypedList(outputBytes))
          : null,
      textRepair: advancedScene
          ? Uint8List.fromList(textRepair.asTypedList(outputBytes))
          : null,
    );
  } catch (error) {
    return GpuCoverPixels(null, null, 0, 0, 'gpu_backend_error:$error');
  } finally {
    for (final p in memory.reversed) {
      free(p);
    }
  }
}
