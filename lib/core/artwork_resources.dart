import 'dart:async';

import 'package:flutter/material.dart';


final class ArtworkResources with WidgetsBindingObserver {
  Timer? _trimTimer;
  final Map<Object, Timer> _retired = {};
  bool _disposed = false;

  ArtworkResources() {
    PaintingBinding.instance.imageCache
      ..maximumSize = 24
      ..maximumSizeBytes = 48 * 1024 * 1024;
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> retire(ImageProvider? provider) async {
    if (provider == null || _disposed) return;
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

  void trimWhenIdle() {
    _trimTimer?.cancel();
    _trimTimer = Timer(const Duration(seconds: 2), didHaveMemoryPressure);
  }

  @override
  void didHaveMemoryPressure() {
    
    PaintingBinding.instance.imageCache.clear();
    _trimTimer?.cancel();
    _trimTimer = null;
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _trimTimer?.cancel();
    for (final timer in _retired.values) {
      timer.cancel();
    }
    _retired.clear();
  }
}
