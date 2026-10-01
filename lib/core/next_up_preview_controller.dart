import 'dart:async';

import 'package:flutter/foundation.dart';

import 'platform_provider.dart';

class NextUpPreviewInput {
  final String? trackIdentity;
  final PlatformQueueItem? next;
  final bool enabled;
  final bool playing;
  final double durationMs;
  final double positionMs;
  final int leadSeconds;

  const NextUpPreviewInput({
    required this.trackIdentity,
    required this.next,
    required this.enabled,
    required this.playing,
    required this.durationMs,
    required this.positionMs,
    required this.leadSeconds,
  });
}


class NextUpPreviewController extends ChangeNotifier {
  static const dismissBeforeEnd = Duration(seconds: 2);
  final NextUpPreviewInput Function() readInput;
  Timer? _boundaryTimer;
  String? _trackIdentity;
  bool _closedForTrack = false;
  bool _visible = false;
  PlatformQueueItem? _next;

  NextUpPreviewController({required this.readInput});
  bool get visible => _visible;
  PlatformQueueItem? get next => _next;

  void refresh() {
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    final input = readInput();
    final trackChanged = input.trackIdentity != _trackIdentity;
    if (trackChanged) {
      _trackIdentity = input.trackIdentity;
      _closedForTrack = false;
    }
    var visible = false;
    final eligible =
        input.enabled &&
        input.playing &&
        input.trackIdentity != null &&
        input.next != null &&
        input.durationMs.isFinite &&
        input.durationMs > 0 &&
        input.positionMs.isFinite;
    if (eligible) {
      final remaining = input.durationMs - input.positionMs;
      final lead = (input.leadSeconds * 1000.0).clamp(0.0, input.durationMs);
      final cutoff = dismissBeforeEnd.inMilliseconds.toDouble();
      if (remaining <= cutoff) {
        _closedForTrack = true;
      } else if (remaining > cutoff + 500) {
        
        _closedForTrack = false;
      }
      visible =
          !_closedForTrack &&
          remaining > cutoff &&
          (remaining <= lead ||
              (!trackChanged && _visible && remaining <= lead + 500));
      if (!visible && remaining > lead && lead > cutoff) {
        _boundaryTimer = Timer(
          Duration(milliseconds: (remaining - lead).ceil() + 16),
          refresh,
        );
      } else if (visible) {
        _boundaryTimer = Timer(
          Duration(milliseconds: (remaining - cutoff).ceil() + 16),
          refresh,
        );
      }
    }
    final next = visible ? input.next : null;
    if (_visible == visible && identical(_next, next)) return;
    _visible = visible;
    _next = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _boundaryTimer?.cancel();
    super.dispose();
  }
}
