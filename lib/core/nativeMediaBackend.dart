import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'mediaCaptureBackend.dart';
import 'mediaProvider.dart';
import 'musicSourceService.dart';


final class NativeMediaBackend implements MediaCaptureBackend {
  final MethodChannel channel;
  final Duration interval;
  final _events = StreamController<MediaProviderEvent>.broadcast(sync: true);
  Timer? _timer;
  Timer? _spectrumTimer;
  bool _refreshQueued = false,
      _spectrumEnabled = false,
      _spectrumReading = false;
  int _commandsPending = 0;
  int _audioGeneration = 0;
  Future<void> _commandTail = Future.value();
  String audioStatus = '';
  int audioFrames = 0, audioProcessId = 0;
  int audioLookupOpenedProcesses = 0;
  Future<bool>? _reading;
  bool _closed = false, _connected = false;
  bool _playing = false;
  int _generation = 0;
  String _source = '', _cover = '';
  MusicSourceSnapshot _sources = const MusicSourceSnapshot(
    selectedSourceAppId: '',
    sources: [],
  );
  NativeMediaBackend({
    this.channel = const MethodChannel('md3_music_widget/native_media_preview'),
    this.interval = const Duration(seconds: 2),
  }) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && !_closed) {
        if (_reading != null || _commandsPending > 0) {
          _refreshQueued = true;
        } else {
          unawaited(_refresh());
        }
      }
    });
  }
  @override
  bool get usesExternalProcess => false;
  @override
  bool get supportsLegacyPolling => false;
  @override
  bool get isConnected => !_closed && _connected;
  @override
  Stream<MediaProviderEvent> get events => _events.stream;
  @override
  Future<bool> connect() {
    if (_closed) return Future.value(false);
    _timer ??= Timer.periodic(interval, (_) => unawaited(_refresh()));
    return _refresh();
  }

  Future<bool> _refresh() {
    if (_closed) return Future.value(false);
    if (_commandsPending > 0) return Future.value(isConnected);
    return _reading ??= _read().whenComplete(() {
      _reading = null;
      if (_refreshQueued && !_closed && _commandsPending == 0) {
        _refreshQueued = false;
        scheduleMicrotask(() => unawaited(_refresh()));
      }
    });
  }

  Future<bool> _read() async {
    final generation = _generation;
    try {
      final response = await channel
          .invokeMapMethod<String, dynamic>('snapshot', {
            'source': _source,
            'knownCover': _cover,
          })
          .timeout(const Duration(seconds: 10));
      if (_closed || generation != _generation) return false;
      if (response == null ||
          response['info'] is! String ||
          response['sources'] is! String) {
        throw const FormatException('Invalid native media response');
      }
      final snapshot = MediaSnapshot.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(response['info'] as String) as Map,
        ),
      );
      final sources = MusicSourceSnapshot.fromJson(
        jsonDecode(response['sources'] as String),
      );
      final artwork = response['artwork'];
      
      if (snapshot.coverVersion.isNotEmpty &&
          snapshot.coverVersion != _cover &&
          (artwork is! Uint8List || artwork.isEmpty)) {
        throw const FormatException('Native artwork missing for a new version');
      }
      _sources = sources;
      _connected = true;
      if (_playing != snapshot.isPlaying) {
        _playing = snapshot.isPlaying;
        if (_spectrumEnabled) _startSpectrumTimer();
      }
      _events.add(MediaSnapshotEvent(snapshot));
      if (_closed || generation != _generation) return false;
      if (artwork is Uint8List &&
          artwork.isNotEmpty &&
          snapshot.coverVersion != _cover) {
        _events.add(MediaArtworkEvent(snapshot.coverVersion, artwork));
      }
      _cover = snapshot.coverVersion;
      if (!_closed && generation == _generation) {
        _events.add(const MediaHeartbeatEvent());
      }
      return true;
    } catch (error) {
      if (!_closed && generation == _generation) {
        final wasConnected = _connected;
        _connected = false;
        if (wasConnected ||
            error is MissingPluginException ||
            error is PlatformException) {
          _events.add(MediaDisconnectedEvent(error));
        }
      }
      return false;
    }
  }

  @override
  Future<MusicSourceSnapshot> fetchSources() async {
    if (_closed) throw StateError('Native backend closed');
    await _refresh();
    if (!isConnected) throw StateError('Native media unavailable');
    return _sources;
  }

  @override
  Future<void> selectSource(String id) async {
    if (_closed) throw StateError('Native backend closed');
    if (id.length > 512) throw ArgumentError('Source ID too long');
    final generation = ++_generation;
    _audioGeneration++;
    audioFrames = 0;
    audioProcessId = 0;
    audioLookupOpenedProcesses = 0;
    audioStatus = '';
    _source = id;
    _cover = '';
    _connected = false;
    if (_spectrumEnabled) await _demand(false);
    if (_closed || generation != _generation) {
      throw StateError('Source selection superseded');
    }
    
    await _reading;
    if (_closed || generation != _generation) {
      throw StateError('Source selection superseded');
    }
    if (!await _refresh()) {
      throw StateError('Native source selection unavailable');
    }
    if (_spectrumEnabled && !_closed && generation == _generation) {
      await _demand(true);
    }
  }

  @override
  void setSpectrumEnabled(bool enabled) {
    if (_closed || _spectrumEnabled == enabled) return;
    _spectrumEnabled = enabled;
    _audioGeneration++;
    audioFrames = 0;
    audioProcessId = 0;
    audioLookupOpenedProcesses = 0;
    _spectrumTimer?.cancel();
    unawaited(_demand(enabled));
    if (enabled) {
      _startSpectrumTimer();
      unawaited(_pollSpectrum());
    }
  }

  void _startSpectrumTimer() {
    _spectrumTimer?.cancel();
    _spectrumTimer = Timer.periodic(
      Duration(milliseconds: _playing ? 33 : 250),
      (_) => unawaited(_pollSpectrum()),
    );
  }

  Future<void> _demand(bool enabled) async {
    if (_closed) return;
    try {
      await channel
          .invokeMethod<void>('spectrumDemand', {'enabled': enabled})
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      audioStatus = 'audio_channel_unavailable';
    }
  }

  Future<void> _pollSpectrum() async {
    if (_closed || !_spectrumEnabled || _spectrumReading) return;
    _spectrumReading = true;
    final generation = _audioGeneration;
    try {
      final result = await channel
          .invokeMapMethod<String, dynamic>('spectrum')
          .timeout(const Duration(seconds: 2));
      if (_closed ||
          !_spectrumEnabled ||
          generation != _audioGeneration ||
          result == null) {
        return;
      }
      audioStatus = result['status']?.toString() ?? '';
      audioFrames = (result['frames'] as num?)?.toInt() ?? 0;
      audioProcessId = (result['processId'] as num?)?.toInt() ?? 0;
      audioLookupOpenedProcesses =
          (result['lookupOpenedProcesses'] as num?)?.toInt() ?? 0;
      final packet = result['packet'];
      if (packet is Uint8List) _events.add(MediaSpectrumEvent(packet));
    } catch (_) {
      if (!_closed) audioStatus = 'audio_channel_unavailable';
    } finally {
      _spectrumReading = false;
    }
  }

  @override
  bool sendCommand(MediaCommand command) => false;
  @override
  Future<bool> dispatchCommand(MediaCommand command) {
    return _dispatch(command.wireValue);
  }

  Future<bool> setPlaying(bool playing) => _dispatch(playing ? 4 : 5);
  Future<bool> _dispatch(int command) {
    if (_closed || _commandsPending >= 4) return Future.value(false);
    final result = Completer<bool>();
    final generation = _generation;
    _commandsPending++;
    _commandTail = _commandTail.then((_) async {
      try {
        await _reading;
        if (_closed || generation != _generation) {
          result.complete(false);
          return;
        }
        final accepted = await channel
            .invokeMethod<bool>('command', {
              'source': _source,
              'command': command,
            })
            .timeout(const Duration(seconds: 10));
        result.complete(
          !_closed && generation == _generation && accepted == true,
        );
      } catch (_) {
        result.complete(false);
      } finally {
        _commandsPending--;
        if (_commandsPending == 0 && !_closed) {
          _refreshQueued = false;
          unawaited(_refresh());
        }
      }
    });
    return result.future;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _connected = false;
    _timer?.cancel();
    _spectrumTimer?.cancel();
    channel.setMethodCallHandler(null);
    try {
      await channel
          .invokeMethod<void>('stop')
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    await _events.close();
  }
}
