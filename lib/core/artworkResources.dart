import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'artworkPalette.dart';
import 'widgetDiagnostics.dart';

typedef _SchemeKey = (String, Brightness, DynamicSchemeVariant);
typedef ArtworkSeed = ({Color color, double contrast});



final class ArtworkSchemeCache {
  final int maximumEntries;
  final Future<ColorScheme> Function(
    ImageProvider,
    Brightness,
    DynamicSchemeVariant,
  )?
  _generate;
  final Future<ArtworkSeed> Function(ImageProvider) _analyze;
  final LinkedHashMap<_SchemeKey, ColorScheme> _ready = LinkedHashMap();
  final Map<_SchemeKey, Future<ColorScheme>> _pending = {};
  final LinkedHashMap<String, ArtworkSeed> _readySeeds = LinkedHashMap();
  final Map<String, Future<ArtworkSeed>> _pendingSeeds = {};
  int _generation = 0;

  ArtworkSchemeCache({
    this.maximumEntries = 8,
    Future<ColorScheme> Function(
      ImageProvider,
      Brightness,
      DynamicSchemeVariant,
    )?
    generate,
    Future<ArtworkSeed> Function(ImageProvider)? analyze,
  }) : assert(maximumEntries > 0),
       
       
       _generate = generate,
       _analyze = analyze ?? _fromImage;

  static Future<ArtworkSeed> _fromImage(ImageProvider provider) async {
    final palette = await WidgetDiagnostics.measure(
      'artwork.seedSample',
      () => ArtworkPalette.fromProvider(provider),
    );
    if (palette.whiteFraction < 0.35) {
      return (
        color: await WidgetDiagnostics.measure(
          'artwork.materialSeed',
          () => ArtworkPalette.materialSeedFromProvider(provider),
        ),
        contrast: 0.0,
      );
    }
    return (
      color: palette.seed,
      contrast: palette.whiteFraction > 0.55 ? 0.15 : 0.0,
    );
  }

  Future<ArtworkSeed> _seed(String identity, ImageProvider provider) {
    final cached = _readySeeds.remove(identity);
    if (cached != null) {
      _readySeeds[identity] = cached;
      return Future.value(cached);
    }
    final pending = _pendingSeeds[identity];
    if (pending != null) return pending;
    final generation = _generation;
    late final Future<ArtworkSeed> shared;
    shared = Future<ArtworkSeed>.sync(() => _analyze(provider))
        .then((seed) {
          if (generation == _generation) {
            _readySeeds[identity] = seed;
            while (_readySeeds.length > maximumEntries) {
              _readySeeds.remove(_readySeeds.keys.first);
            }
          }
          return seed;
        })
        .whenComplete(() {
          if (identical(_pendingSeeds[identity], shared)) {
            _pendingSeeds.remove(identity);
          }
        });
    return _pendingSeeds[identity] = shared;
  }

  Future<ColorScheme> resolve({
    required String identity,
    required ImageProvider provider,
    required Brightness brightness,
    required DynamicSchemeVariant variant,
  }) {
    final key = (identity, brightness, variant);
    final cached = _ready.remove(key);
    if (cached != null) {
      _ready[key] = cached;
      return Future.value(cached);
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final generation = _generation;
    final generate = _generate;
    final future = generate == null
        ? _seed(identity, provider).then(
            (seed) => ColorScheme.fromSeed(
              seedColor: seed.color,
              brightness: brightness,
              dynamicSchemeVariant: variant,
              contrastLevel: seed.contrast,
            ),
          )
        : Future<ColorScheme>.sync(
            () => generate(provider, brightness, variant),
          );
    late final Future<ColorScheme> shared;
    shared = future
        .then((scheme) {
          if (generation == _generation) {
            _ready[key] = scheme;
            while (_ready.length > maximumEntries) {
              _ready.remove(_ready.keys.first);
            }
          }
          return scheme;
        })
        .whenComplete(() {
          if (identical(_pending[key], shared)) _pending.remove(key);
        });
    _pending[key] = shared;
    return shared;
  }

  int get entryCount => _ready.length;
  int get pendingCount => _pending.length;

  void clear() {
    _generation++;
    _ready.clear();
    _pending.clear();
    _readySeeds.clear();
    _pendingSeeds.clear();
  }
}

final class CachedArtwork {
  static final Expando<CachedArtwork> _owners = Expando();
  final MemoryImage cover;
  final ImageProvider background;
  final Set<ImageProvider> _variants = {};
  final int encodedBytes;
  Color? averageColor;
  bool tonePrepared = false;
  Future<Color?>? _averageTask;

  CachedArtwork._(this.cover, this.background, this.encodedBytes);

  factory CachedArtwork(Uint8List bytes) {
    WidgetDiagnostics.count('sourcePreparations');
    final cover = MemoryImage(bytes);
    final entry = CachedArtwork._(
      cover,
      ResizeImage(cover, width: 256),
      bytes.lengthInBytes,
    );
    _owners[cover] = entry;
    _owners[entry.background] = entry;
    return entry;
  }

  
  
  static void trackVariant(ImageProvider source, ImageProvider variant) {
    _owners[source]?._variants.add(variant);
  }

  Iterable<ImageProvider> get providers sync* {
    yield cover;
    yield background;
    yield* _variants;
  }

  Future<Color?> prepareAverageColor() => _averageTask ??= () async {
    WidgetDiagnostics.count('toneDecodes');
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        cover.bytes,
        targetWidth: 32,
        targetHeight: 32,
        allowUpscaling: false,
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      double r = 0, g = 0, b = 0, a = 0;
      for (var i = 0; i < data.lengthInBytes; i += 4) {
        r += data.getUint8(i);
        g += data.getUint8(i + 1);
        b += data.getUint8(i + 2);
        a += data.getUint8(i + 3);
      }
      if (a <= 0) return null;
      averageColor = Color.fromARGB(
        (a / (data.lengthInBytes / 4)).round().clamp(0, 255),
        (r * 255 / a).round().clamp(0, 255),
        (g * 255 / a).round().clamp(0, 255),
        (b * 255 / a).round().clamp(0, 255),
      );
      return averageColor;
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }();
}


final class ArtworkResources with WidgetsBindingObserver {
  final colorSchemes = ArtworkSchemeCache();
  static const int maximumArtworkEntries = 4;
  static const int maximumEncodedBytes = 12 * 1024 * 1024;
  final LinkedHashMap<String, CachedArtwork> _artworkPool = LinkedHashMap();
  int _poolBytes = 0;
  int _generation = 0;
  final Map<Object, Timer> _retired = {};
  bool _disposed = false;

  ArtworkResources() {
    PaintingBinding.instance.imageCache
      ..maximumSize = 24
      ..maximumSizeBytes = 48 * 1024 * 1024;
    WidgetsBinding.instance.addObserver(this);
  }

  CachedArtwork? findArtwork(String version) {
    final entry = _artworkPool.remove(version);
    if (entry != null) _artworkPool[version] = entry;
    return entry;
  }

  bool hasArtwork(String version) => _artworkPool.containsKey(version);
  int get generation => _generation;

  CachedArtwork? rememberArtwork(String version, Uint8List bytes) {
    return rememberPreparedArtwork(version, CachedArtwork(bytes));
  }

  CachedArtwork? rememberPreparedArtwork(String version, CachedArtwork entry) {
    if (_disposed ||
        version.isEmpty ||
        entry.encodedBytes > maximumEncodedBytes) {
      return null;
    }
    final existing = _artworkPool.remove(version);
    if (existing != null) {
      _poolBytes -= existing.encodedBytes;
    }
    _artworkPool[version] = entry;
    _poolBytes += entry.encodedBytes;
    if (existing != null && !identical(existing, entry)) _retireEntry(existing);
    while (_artworkPool.length > maximumArtworkEntries ||
        _poolBytes > maximumEncodedBytes) {
      final oldestKey = _artworkPool.keys.first;
      final oldest = _artworkPool.remove(oldestKey)!;
      _poolBytes -= oldest.encodedBytes;
      _retireEntry(oldest);
    }
    return entry;
  }

  bool retains(ImageProvider? provider) {
    if (provider == null) return false;
    for (final entry in _artworkPool.values) {
      if (entry.providers.contains(provider)) {
        return true;
      }
    }
    return false;
  }

  void forgetArtwork(String version) {
    final entry = _artworkPool.remove(version);
    if (entry != null) {
      _poolBytes -= entry.encodedBytes;
      _retireEntry(entry);
    }
  }

  void _retireEntry(CachedArtwork entry) {
    for (final provider in entry.providers) {
      unawaited(retire(provider));
    }
  }

  int get artworkCount => _artworkPool.length;
  int get encodedBytes => _poolBytes;

  Future<void> retire(ImageProvider? provider) async {
    if (provider == null || _disposed || retains(provider)) return;
    Object key;
    try {
      key = await provider.obtainKey(ImageConfiguration.empty);
    } catch (_) {
      return;
    }
    if (_disposed || retains(provider)) return;
    _retired.remove(key)?.cancel();
    _retired[key] = Timer(const Duration(seconds: 2), () {
      _retired.remove(key);
      if (!_disposed && !retains(provider)) {
        PaintingBinding.instance.imageCache.evict(key, includeLive: false);
      }
    });
  }

  @override
  void didHaveMemoryPressure() {
    _generation++;
    colorSchemes.clear();
    _artworkPool.clear();
    _poolBytes = 0;
    
    PaintingBinding.instance.imageCache.clear();
  }

  void dispose() {
    _generation++;
    colorSchemes.clear();
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _artworkPool.clear();
    _poolBytes = 0;
    for (final timer in _retired.values) {
      timer.cancel();
    }
    _retired.clear();
  }
}
