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
  final NextUpPreviewInput Function() readInput;
  Timer? _boundaryTimer;
  Timer? _graceTimer;
  String? _trackIdentity;
  bool _graceExpired = false;
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
      _graceTimer?.cancel();
      _graceTimer = null;
      _graceExpired = false;
    }
    var visible = false;
    final eligible =
        input.enabled &&
        input.playing &&
        input.trackIdentity != null &&
        input.next != null &&
        input.durationMs > 0;
    if (eligible) {
      final remaining = input.durationMs - input.positionMs;
      final lead = (input.leadSeconds * 1000.0).clamp(0.0, input.durationMs);
      if (remaining > lead + 500) {
        _graceTimer?.cancel();
        _graceTimer = null;
        _graceExpired = false;
      }
      if (!_graceExpired) {
        visible = remaining > 0
            ? remaining <= lead ||
                  (!trackChanged && _visible && remaining <= lead + 500)
            : !trackChanged && _visible;
        if (visible && remaining <= 0) {
          _graceTimer ??= Timer(const Duration(milliseconds: 1100), () {
            _graceTimer = null;
            _graceExpired = true;
            refresh();
          });
        }
      }
      if (!visible && remaining > lead) {
        _boundaryTimer = Timer(
          Duration(milliseconds: (remaining - lead).ceil() + 16),
          refresh,
        );
      } else if (visible && remaining > 0) {
        _boundaryTimer = Timer(
          Duration(milliseconds: remaining.ceil() + 16),
          refresh,
        );
      }
    } else {
      _graceTimer?.cancel();
      _graceTimer = null;
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
    _graceTimer?.cancel();
    super.dispose();
  }
}
