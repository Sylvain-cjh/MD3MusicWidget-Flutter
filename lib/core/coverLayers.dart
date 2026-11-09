import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'coverGpuBackend.dart';
import 'runtimeCapabilities.dart';
import 'widgetDiagnostics.dart';



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


final class CoverLayerDemand {
  CoverLayerDemand({this.isCurrent});
  final bool Function()? isCurrent;
  bool _active = true;
  bool get wanted => _active && (isCurrent?.call() ?? true);
  void cancel() => _active = false;
}

typedef _LayerKey = (String, Object);

final class _LayerJob {
  _LayerJob(this.key, this.image);
  final _LayerKey key;
  final ImageProvider image;
  final completion = Completer<_Entry?>();
  final demands = <CoverLayerDemand?>[];
  bool running = false;
  bool get wanted => demands.any((demand) => demand?.wanted ?? true);
  bool get foreground =>
      demands.any((demand) => demand?.isCurrent != null && demand!.wanted);
}

typedef CoverLayerProducer = Future<CoverLayers?> Function(ImageProvider);



final class CoverLayerService with WidgetsBindingObserver {
  
  
  
  static const _cacheRevision = 'probability6-original-pixels-v1';
  static final instance = CoverLayerService();
  final int maximumEntries, maximumBytes;
  final CoverLayerProducer _produce;
  final LinkedHashMap<Object, _Entry> _ready = LinkedHashMap();
  final Map<_LayerKey, _LayerJob> _pending = {};
  final LinkedHashMap<Object, DateTime?> _rejected = LinkedHashMap();
  final DateTime Function() _clock;
  DateTime? _backendRetryAt;
  final ValueNotifier<String> status = ValueNotifier('尚未分析封面');
  bool _draining = false;
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
  int get pendingCount => _pending.length;
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

  Future<CoverLayerLease?> acquire(
    Object identity,
    ImageProvider image, {
    CoverLayerDemand? demand,
  }) async {
    if (_disposed || demand?.wanted == false) return null;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _discardAbandoned();
    final key = (_cacheRevision, identity);
    var entry = _ready.remove(key);
    if (entry != null) _ready[key] = entry;
    if (entry == null) {
      if (_isRejected(key) || _backendCooling) return null;
      var pending = _pending[key];
      if (pending == null) {
        if (_pending.length >= 3) return null;
        _pending[key] = pending = _LayerJob(key, image);
        if (WidgetDiagnostics.enabled) {
          WidgetDiagnostics.markOnce('layersQueued:$identity');
        }
      }
      pending.demands.add(demand);
      _scheduleDrain();
      entry = await pending.completion.future;
      if (entry != null) {
        entry.waiters--;
        if (!entry.cached) {
          if (entry.pins == 0 && entry.waiters == 0) entry.layers.dispose();
          return null;
        }
      }
    }
    if (entry == null || _disposed || demand?.wanted == false) {
      _trim();
      return null;
    }
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

  void _discardAbandoned() {
    for (final job in _pending.values.toList()) {
      if (job.running || job.wanted) continue;
      _pending.remove(job.key);
      WidgetDiagnostics.count('layerJobsSkipped');
      job.completion.complete(null);
    }
  }

  void _scheduleDrain() {
    if (_draining) return;
    _draining = true;
    scheduleMicrotask(_drain);
  }

  Future<void> _drain() async {
    try {
      while (!_disposed) {
        _discardAbandoned();
        if (_pending.isEmpty) break;
        
        var next = _pending.values.first;
        for (final job in _pending.values) {
          if (job.foreground) next = job;
        }
        next.running = true;
        final entry = _backendCooling || _isRejected(next.key)
            ? null
            : await _produceEntry(next, _generation);
        if (identical(_pending[next.key], next)) _pending.remove(next.key);
        next.completion.complete(entry);
        
        await Future<void>.value();
      }
    } finally {
      _draining = false;
    }
  }

  Future<_Entry?> _produceEntry(_LayerJob job, int generation) async {
    final key = job.key;
    try {
      if (WidgetDiagnostics.enabled) {
        WidgetDiagnostics.markOnce('layersStarted:${key.$2}');
      }
      analyses++;
      final layers = await _produce(job.image);
      if (_disposed || generation != _generation) {
        layers?.dispose();
        return null;
      }
      if (layers == null) {
        _rememberRejection(key, null);
        status.value = '保留原始 3D 卡片 · 未找到可靠分层';
        return null;
      }
      final created = _Entry(layers)..waiters = job.demands.length;
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
    } catch (error) {
      if (!_disposed && generation == _generation) _recordFailure(key, error);
      return null;
    }
  }

  void _rememberRejection(_LayerKey key, DateTime? retryAt) {
    _rejected[key] = retryAt;
    while (_rejected.length > 8) {
      _rejected.remove(_rejected.keys.first);
    }
  }

  void _recordFailure(_LayerKey key, Object error) {
    final detail = lastFailure = error.toString();
    final quality = detail.contains('mask_quality_rejected');
    final missing = detail.contains('missing') || detail.contains('not_found');
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
    _rememberRejection(key, retryAt);
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
    status.value = detail.contains('integrated_gpu_unavailable')
        ? '未检测到可用核显 · 保留原始 3D 卡片'
        : quality
        ? '保留原始 3D 卡片 · 分割结果不可靠'
        : '保留原始 3D 卡片 · GPU 准备不可用';
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
    for (final job in _pending.values) {
      if (!job.running) job.completion.complete(null);
    }
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
    final loading = ui.FragmentProgram.fromAsset('shaders/coverSubject.frag');
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
    final loading = ui.FragmentProgram.fromAsset('shaders/coverLayers.frag');
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
      final data = await WidgetDiagnostics.measure(
        'layers.inputReadback',
        () =>
            info!.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
      );
      if (data == null) return null;
      final pixels = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final prepared = await WidgetDiagnostics.measure(
        'layers.nativeWorker',
        () => _runPixelWorker(
          pixels,
          width,
          height,
          executableDirectory,
          runtimeDirectory,
        ),
      );
      if (!prepared.usedGpu) throw StateError(prepared.detail);
      ui.Image? mask, background, original, priority, textRepair;
      try {
        mask = await WidgetDiagnostics.measure<ui.Image>(
          'layers.maskUpload',
          () => _decode(prepared.mask!, prepared.width, prepared.height),
        );
        background = await WidgetDiagnostics.measure<ui.Image>(
          'layers.backgroundUpload',
          () => _decode(prepared.background!, prepared.width, prepared.height),
        );
        original = info.image.clone();
        if (prepared.priority != null && prepared.textRepair != null) {
          priority = await WidgetDiagnostics.measure(
            'layers.priorityUpload',
            () => _decode(prepared.priority!, prepared.width, prepared.height),
          );
          textRepair = await WidgetDiagnostics.measure(
            'layers.textRepairUpload',
            () =>
                _decode(prepared.textRepair!, prepared.width, prepared.height),
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
          await WidgetDiagnostics.measure(
            'layers.programReady',
            () => compact ? subjectProgram : program,
          ),
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
