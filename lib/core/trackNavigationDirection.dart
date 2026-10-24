import 'mediaProvider.dart';
import 'platformProvider.dart';



class TrackNavigationDirection {
  static const intentLifetime = Duration(seconds: 3);
  static const historyLimit = 32;
  static const restartConfirmation = Duration(milliseconds: 250);
  final DateTime Function() now;
  final List<String> _history = [];
  int _cursor = -1;
  PlatformTrack? _current;
  double _lastPositionMs = 0;
  ({int serial, int direction, String source, DateTime at})? _intent;
  int _serial = 0;
  DateTime? _restartCandidateAt;
  int direction = 1;

  TrackNavigationDirection({DateTime Function()? now})
    : now = now ?? DateTime.now;

  int get retainedTrackCount => _history.length;

  int? noteCommand(MediaCommand command) {
    final value = switch (command) {
      MediaCommand.previous => -1,
      MediaCommand.next => 1,
      MediaCommand.togglePlayPause => null,
    };
    if (value == null) return null;
    final serial = ++_serial;
    _restartCandidateAt = null;
    _intent = (
      serial: serial,
      direction: value,
      source: _current?.sourceAppId.toLowerCase() ?? '',
      at: now(),
    );
    return serial;
  }

  void cancelCommand(int? serial) {
    if (serial != null && _intent?.serial == serial) {
      _intent = null;
      _restartCandidateAt = null;
    }
  }

  int observe(
    PlatformTrack? track, {
    PlatformQueue? queue,
    bool shuffle = false,
    bool wrap = false,
    double? positionMs,
    double? previousPositionMs,
  }) {
    final intent = _intent;
    if (intent != null && now().difference(intent.at) > intentLifetime) {
      _intent = null;
      _restartCandidateAt = null;
    }
    if (track == null) return direction;
    final previous = _current;
    final source = track.sourceAppId.toLowerCase();
    if (previous == null || previous.sourceAppId.toLowerCase() != source) {
      _history.clear();
      _history.add(track.queueIdentity);
      _cursor = 0;
      _current = track;
      _lastPositionMs = positionMs?.isFinite == true ? positionMs! : 0;
      _intent = null;
      _restartCandidateAt = null;
      return direction = 1;
    }
    if (track.title.trim() == previous.title.trim() &&
        track.artist.trim() == previous.artist.trim()) {
      
      
      if (_intent?.direction == -1 &&
          positionMs != null &&
          positionMs < 2500 &&
          ((previousPositionMs ?? 0) > 5000 || _restartCandidateAt != null)) {
        
        
        _restartCandidateAt ??= now();
        if (now().difference(_restartCandidateAt!) >= restartConfirmation) {
          cancelCommand(_intent?.serial);
        }
      } else if (positionMs != null) {
        _restartCandidateAt = null;
      }
      _current = track;
      if (positionMs?.isFinite == true) _lastPositionMs = positionMs!;
      return direction;
    }

    final identity = track.queueIdentity;
    final pending = _intent;
    _intent = null;
    _restartCandidateAt = null;
    int? resolved;
    if (pending != null &&
        (pending.source.isEmpty || pending.source == source)) {
      resolved = pending.direction;
    }
    final previousPosition =
        previousPositionMs?.isFinite == true &&
            previousPositionMs! > _lastPositionMs
        ? previousPositionMs
        : _lastPositionMs;
    final automaticAdvance =
        positionMs != null &&
        positionMs < 5000 &&
        previous.durationMs > 0 &&
        previousPosition >= previous.durationMs - 2500;
    if (resolved == null && !shuffle && queue != null) {
      final from = _uniqueIndex(queue, previous);
      final to = _uniqueIndex(queue, track);
      if (from != null && to != null && from != to) {
        if (automaticAdvance && from == queue.items.length - 1 && to == 0) {
          resolved = 1;
        } else if (wrap &&
            queue.items.length > 2 &&
            from == queue.items.length - 1 &&
            to == 0) {
          resolved = 1;
        } else if (wrap &&
            queue.items.length > 2 &&
            from == 0 &&
            to == queue.items.length - 1) {
          resolved = -1;
        } else {
          resolved = to > from ? 1 : -1;
        }
      }
    }
    if (resolved == null && automaticAdvance) resolved = 1;
    final before = _cursor > 0 && _history[_cursor - 1] == identity;
    final after =
        _cursor + 1 < _history.length && _history[_cursor + 1] == identity;
    if (resolved == null && !shuffle) {
      resolved = before
          ? -1
          : after
          ? 1
          : null;
    }
    direction = resolved ?? 1;
    if (direction < 0 && before) {
      _cursor--;
    } else if (direction > 0 && after) {
      _cursor++;
    } else if (direction < 0) {
      _history.insert(_cursor, identity);
    } else {
      _history.removeRange(_cursor + 1, _history.length);
      _history.add(identity);
      _cursor++;
    }
    while (_history.length > historyLimit) {
      if (_cursor > 0) {
        _history.removeAt(0);
        _cursor--;
      } else {
        _history.removeLast();
      }
    }
    _current = track;
    _lastPositionMs = positionMs?.isFinite == true ? positionMs! : 0;
    return direction;
  }

  static int? _uniqueIndex(PlatformQueue queue, PlatformTrack track) {
    final title = _normalize(track.title), artist = _normalize(track.artist);
    int? found;
    for (var i = 0; i < queue.items.length; i++) {
      final item = queue.items[i];
      if (_normalize(item.title) != title ||
          (item.artist.isNotEmpty && _normalize(item.artist) != artist)) {
        continue;
      }
      if (found != null) return null;
      found = i;
    }
    return found;
  }

  static final _whitespace = RegExp(r'\s+');
  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(_whitespace, ' ').trim();
}
