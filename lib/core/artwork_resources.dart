import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';

final class CachedArtwork {
  final MemoryImage cover;
  final ImageProvider background;
  final int encodedBytes;

  CachedArtwork._(this.cover, this.background, this.encodedBytes);

  factory CachedArtwork(Uint8List bytes) {
    final cover = MemoryImage(bytes);
    return CachedArtwork._(
      cover,
      ResizeImage(cover, width: 256),
      bytes.lengthInBytes,
    );
  }
}


final class ArtworkResources with WidgetsBindingObserver {
  static const int maximumArtworkEntries = 4;
  static const int maximumEncodedBytes = 12 * 1024 * 1024;
  final LinkedHashMap<String, CachedArtwork> _artworkPool = LinkedHashMap();
  int _poolBytes = 0;
  final Map<Object, Timer> _retired = {};
  final VoidCallback? onPoolCleared;
  bool _disposed = false;

  ArtworkResources({this.onPoolCleared}) {
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
    if (existing != null) _poolBytes -= existing.encodedBytes;
    _artworkPool[version] = entry;
    _poolBytes += entry.encodedBytes;
    while (_artworkPool.length > maximumArtworkEntries ||
        _poolBytes > maximumEncodedBytes) {
      final oldestKey = _artworkPool.keys.first;
      _poolBytes -= _artworkPool.remove(oldestKey)!.encodedBytes;
    }
    return entry;
  }

  bool retains(ImageProvider? provider) {
    if (provider == null) return false;
    for (final entry in _artworkPool.values) {
      if (identical(provider, entry.cover) ||
          identical(provider, entry.background)) {
        return true;
      }
    }
    return false;
  }

  void forgetArtwork(String version) {
    final entry = _artworkPool.remove(version);
    if (entry != null) _poolBytes -= entry.encodedBytes;
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
    if (_disposed) return;
    _retired.remove(key)?.cancel();
    _retired[key] = Timer(const Duration(seconds: 2), () {
      _retired.remove(key);
      PaintingBinding.instance.imageCache.evict(key, includeLive: false);
    });
  }

  @override
  void didHaveMemoryPressure() {
    _artworkPool.clear();
    _poolBytes = 0;
    onPoolCleared?.call();
    
    PaintingBinding.instance.imageCache.clear();
  }

  void dispose() {
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
