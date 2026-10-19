import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'cover_gpu_backend.dart';
import 'runtime_capabilities.dart';



Future<GpuCoverPixels> _runPixelWorker(
  Uint8List pixels,
  int width,
  int height,
  String? executableDirectory,
  String? runtimeDirectory,
) => Isolate.run(
  () => prepareGpuCover(
    pixels,
    width,
    height,
    executableDirectory: executableDirectory,
    runtimeDirectory: runtimeDirectory,
  ),
);

final class CoverLayers {
  final ui.Image original, mask, background;
  final ui.Image? priority, textRepair;
  final String backend;
  final String detail;
  final ui.FragmentProgram? program;
  final bool compactProgram;
  CoverLayers(
    this.original,
    this.mask,
    this.background,
    this.backend,
    this.detail,
    this.program, {
    this.priority,
    this.textRepair,
    this.compactProgram = false,
  });
  int get bytes => [original, mask, background, priority, textRepair]
      .whereType<ui.Image>()
      .fold(0, (sum, image) => sum + image.width * image.height * 4);
  void dispose() {
    original.dispose();
    mask.dispose();
    background.dispose();
    priority?.dispose();
    textRepair?.dispose();
  }
}

final class CoverLayerLease {
  final CoverLayers layers;
  final VoidCallback _release;
  bool _released = false;
  CoverLayerLease._(this.layers, this._release);
  void dispose() {
    if (_released) return;
    _released = true;
    _release();
  }
}

final class _Entry {
  final CoverLayers layers;
  int pins = 0;
  int waiters = 0;
  bool cached = true;
  _Entry(this.layers);
}

final class _LayerJob {
  int waiters = 0;
  late Future<_Entry?> future;
}

typedef CoverLayerProducer = Future<CoverLayers?> Function(ImageProvider);



final class CoverLayerService with WidgetsBindingObserver {
  
  
  
  static const _cacheRevision = 'probability6-original-pixels-v1';
  static final instance = CoverLayerService();
  final int maximumEntries, maximumBytes;
  final CoverLayerProducer _produce;
  final LinkedHashMap<Object, _Entry> _ready = LinkedHashMap();
  final Map<Object, _LayerJob> _pending = {};
  final LinkedHashMap<Object, DateTime?> _rejected = LinkedHashMap();
  final DateTime Function() _clock;
  DateTime? _backendRetryAt;
  final ValueNotifier<String> status = ValueNotifier('尚未分析封面');
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _observing = false;
  bool _disposed = false;
  int analyses = 0;
  String? lastFailure;
  CoverLayerService({
    this.maximumEntries = 4,
    this.maximumBytes = 16 * 1024 * 1024,
    CoverLayerProducer? produce,
    String? executableDirectory,
    String? runtimeDirectory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _produce =
           produce ??
           ((image) => _prepare(image, executableDirectory, runtimeDirectory));

  int get entryCount => _ready.length;
  String? get lastResultDetail =>
      _ready.isEmpty ? null : _ready.values.last.layers.detail;
  bool _isRejected(Object identity) {
    if (!_rejected.containsKey(identity)) return false;
    final retry = _rejected[identity];
    if (retry != null && !_clock().isBefore(retry)) {
      _rejected.remove(identity);
      return false;
    }
    return true;
  }

  bool get _backendCooling => _backendRetryAt?.isAfter(_clock()) == true;
  bool hasResult(Object identity) =>
      _ready.containsKey((_cacheRevision, identity)) ||
      _isRejected((_cacheRevision, identity)) ||
      _backendCooling;
  int get retainedBytes => _ready.values.fold(0, (a, b) => a + b.layers.bytes);

  Future<CoverLayerLease?> acquire(Object identity, ImageProvider image) async {
    if (_disposed) return null;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final key = (_cacheRevision, identity);
    if (_isRejected(key) || _backendCooling) return null;
    var entry = _ready.remove(key);
    if (entry != null) _ready[key] = entry;
    if (entry == null) {
      var pending = _pending[key];
      if (pending == null) {
        if (_pending.length >= 3) return null;
        final generation = _generation;
        final job = _LayerJob();
        final task = _tail
            .then((_) async {
              if (_disposed || generation != _generation) return null;
              analyses++;
              final layers = await _produce(image);
              if (_disposed || generation != _generation) {
                layers?.dispose();
                return null;
              }
              if (layers == null) {
                _rejected[key] = null;
                while (_rejected.length > 8) {
                  _rejected.remove(_rejected.keys.first);
                }
                status.value = '保留原始 3D 卡片 · 未找到可靠分层';
                return null;
              }
              final created = _Entry(layers)..waiters = job.waiters;
              lastFailure = null;
              _backendRetryAt = null;
              RuntimeCapabilities.instance.set(
                RuntimeCapability.coverLayers,
                const CapabilityStatus(CapabilityPhase.ready),
              );
              _ready[key] = created;
              final device = layers.detail.split(';').first;
              status.value = device.startsWith('gpu:integrated:')
                  ? '核显分层 · ${device.substring(15)}'
                  : 'GPU 分层 · ${device.replaceFirst('gpu:discrete:', '')}';
              
              return created;
            })
            .catchError((Object error) {
              if (!_disposed && generation == _generation) {
                lastFailure = error.toString();
                final detail = error.toString();
                final quality = detail.contains('mask_quality_rejected');
                final missing =
                    detail.contains('missing') || detail.contains('not_found');
                final unsupported =
                    detail.contains('integrated_gpu_unavailable') ||
                    detail.contains('policy_required') ||
                    detail.contains('not_allowed');
                final retryAt = quality
                    ? null
                    : _clock().add(
                        unsupported
                            ? const Duration(minutes: 2)
                            : const Duration(seconds: 30),
                      );
                _rejected[key] = retryAt;
                if (!quality) _backendRetryAt = retryAt;
                RuntimeCapabilities.instance.set(
                  RuntimeCapability.coverLayers,
                  CapabilityStatus(
                    quality
                        ? CapabilityPhase.ready
                        : missing
                        ? CapabilityPhase.missingDependency
                        : unsupported
                        ? CapabilityPhase.unsupported
                        : CapabilityPhase.temporarilyUnavailable,
                    reason: quality
                        ? 'mask_quality_rejected'
                        : missing
                        ? 'gpu_dependency_missing'
                        : unsupported
                        ? 'integrated_gpu_unavailable'
                        : 'gpu_prepare_failed',
                    retryAt: retryAt,
                  ),
                );
                while (_rejected.length > 8) {
                  _rejected.remove(_rejected.keys.first);
                }
                status.value =
                    error.toString().contains('integrated_gpu_unavailable')
                    ? '未检测到可用核显 · 保留原始 3D 卡片'
                    : error.toString().contains('mask_quality_rejected')
                    ? '保留原始 3D 卡片 · 分割结果不可靠'
                    : '保留原始 3D 卡片 · GPU 准备不可用';
              }
              return null;
            });
        _tail = task.then<void>((_) {});
        job.future = task.whenComplete(() {
          if (identical(_pending[key], job)) _pending.remove(key);
        });
        _pending[key] = pending = job;
      }
      pending.waiters++;
      entry = await pending.future;
      if (entry != null) {
        entry.waiters--;
        if (!entry.cached) {
          if (entry.pins == 0 && entry.waiters == 0) entry.layers.dispose();
          return null;
        }
      }
    }
    if (entry == null || _disposed) return null;
    entry.pins++;
    _trim();
    final pinned = entry;
    return CoverLayerLease._(entry.layers, () {
      pinned.pins--;
      if (!pinned.cached && pinned.pins == 0 && pinned.waiters == 0) {
        pinned.layers.dispose();
      }
      _trim();
    });
  }

  void _trim() {
    while (_ready.length > maximumEntries || retainedBytes > maximumBytes) {
      final candidates = _ready.entries.where(
        (e) => e.value.pins == 0 && e.value.waiters == 0,
      );
      if (candidates.isEmpty) break;
      final oldest = candidates.first;
      _ready.remove(oldest.key);
      oldest.value.cached = false;
      oldest.value.layers.dispose();
    }
  }

  void clear() {
    _backendRetryAt = null;
    _generation++;
    _pending.clear();
    _rejected.clear();
    for (final entry in _ready.values) {
      entry.cached = false;
      if (entry.pins == 0 && entry.waiters == 0) entry.layers.dispose();
    }
    _ready.clear();
  }

  @override
  void didHaveMemoryPressure() => clear();
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    status.dispose();
  }

  static Future<ui.FragmentProgram>? _program;
  static Future<ui.FragmentProgram>? _subjectProgram;
  static Future<ui.FragmentProgram> get subjectProgram {
    final cached = _subjectProgram;
    if (cached != null) return cached;
    final loading = ui.FragmentProgram.fromAsset('shaders/cover_subject.frag');
    _subjectProgram = loading;
    unawaited(
      loading.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_subjectProgram, loading)) _subjectProgram = null;
        },
      ),
    );
    return loading;
  }

  static Future<ui.FragmentProgram> get program {
    final cached = _program;
    if (cached != null) return cached;
    final loading = ui.FragmentProgram.fromAsset('shaders/cover_layers.frag');
    _program = loading;
    unawaited(
      loading.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_program, loading)) _program = null;
        },
      ),
    );
    return loading;
  }

  static Future<CoverLayers?> _prepare(
    ImageProvider provider,
    String? executableDirectory,
    String? runtimeDirectory,
  ) async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final ready = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (ready.isCompleted) {
          info.dispose();
        } else {
          ready.complete(info);
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    ImageInfo? info;
    try {
      info = await ready.future.timeout(const Duration(seconds: 5));
      final width = info.image.width, height = info.image.height;
      if (width > 2048 || height > 2048) return null;
      final data = await info.image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) return null;
      final pixels = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final prepared = await _runPixelWorker(
        pixels,
        width,
        height,
        executableDirectory,
        runtimeDirectory,
      );
      if (!prepared.usedGpu) throw StateError(prepared.detail);
      ui.Image? mask, background, original, priority, textRepair;
      try {
        mask = await _decode(prepared.mask!, prepared.width, prepared.height);
        background = await _decode(
          prepared.background!,
          prepared.width,
          prepared.height,
        );
        original = info.image.clone();
        if (prepared.priority != null && prepared.textRepair != null) {
          priority = await _decode(
            prepared.priority!,
            prepared.width,
            prepared.height,
          );
          textRepair = await _decode(
            prepared.textRepair!,
            prepared.width,
            prepared.height,
          );
        }
        final compact =
            prepared.priority == null || prepared.textRepair == null;
        return CoverLayers(
          original,
          mask,
          background,
          'gpu',
          prepared.detail,
          compact ? await subjectProgram : await program,
          priority: priority,
          textRepair: textRepair,
          compactProgram: compact,
        );
      } catch (_) {
        original?.dispose();
        mask?.dispose();
        background?.dispose();
        priority?.dispose();
        textRepair?.dispose();
        rethrow;
      }
    } finally {
      stream.removeListener(listener);
      info?.dispose();
      
      if (info == null) {
        unawaited(
          ready.future.then(
            (lateInfo) => lateInfo.dispose(),
            onError: (Object _) {},
          ),
        );
      }
    }
  }

  static Future<ui.Image> _decode(Uint8List data, int width, int height) {
    final ready = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      data,
      width,
      height,
      ui.PixelFormat.rgba8888,
      ready.complete,
    );
    return ready.future;
  }
}
