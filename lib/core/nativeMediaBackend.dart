import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'mediaCaptureBackend.dart';
import 'mediaProvider.dart';
import 'musicSourceService.dart';
import 'platformProvider.dart';


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
  int? _selectionGeneration;
  String _source = '', _cover = '';
  String _committedSource = '';
  MediaSnapshot? _diagnosticSnapshot;
  String? _bridgeError;
  int? _lastCommand;
  String? _lastCommandResult;
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

  
  Map<String, Object?> captureDiagnostics() {
    final snapshot = _diagnosticSnapshot;
    final hasSession =
        snapshot?.hasMediaSession ?? (snapshot?.sourceAppId.isNotEmpty == true);
    final uia = snapshot?.captureRoute.usesUiAutomation == true;
    final hasPlayback = hasSession || uia;
    final positionKnown =
        hasPlayback &&
        (snapshot?.timelinePositionKnown ??
            ((snapshot?.timelineUpdatedAtMs ?? 0) > 0));
    final duration = snapshot?.durationMs;
    final durationKnown =
        hasPlayback && duration != null && duration.isFinite && duration > 0;
    return {
      'sourceMode': _source.isEmpty ? 'automatic' : 'strict',
      'selectedSource': _source,
      'activeSource': hasPlayback ? snapshot!.sourceAppId : null,
      'captureRoute': snapshot?.captureRoute.name,
      'session': !isConnected
          ? (_bridgeError ?? 'awaitingSnapshot')
          : uia && !hasSession
          ? 'uiaWithoutSmtc'
          : hasSession
          ? 'available'
          : _source.isEmpty
          ? 'noSession'
          : 'selectedSessionMissing',
      'hasTrack':
          snapshot != null && PlatformTrack.fromSnapshot(snapshot) != null,
      'hasArtwork': _cover.isNotEmpty && snapshot?.coverVersion == _cover,
      'timeline': switch ((positionKnown, durationKnown)) {
        (true, true) => 'positionAndDuration',
        (true, false) => 'positionOnly',
        (false, true) => 'durationOnly',
        (false, false) => 'unavailable',
      },
      'controls': {
        for (final entry in {
          'playPause': MediaCapability.playPause,
          'previous': MediaCapability.previous,
          'next': MediaCapability.next,
        }.entries)
          entry.key: MediaCapability.supports(
            snapshot?.capabilities ?? 0,
            entry.value,
          ),
      },
      if (_lastCommand != null)
        'lastCommand': {
          'wireValue': _lastCommand,
          'result': _lastCommandResult,
        },
      'spectrum': !_spectrumEnabled
          ? 'disabled'
          : !hasPlayback
          ? 'noSession'
          : !_playing
          ? 'paused'
          : audioStatus.isEmpty
          ? 'awaitingAudio'
          : audioStatus,
      'audioFrames': audioFrames,
      'audioProcessId': audioProcessId,
    };
  }

  @override
  Future<bool> connect({String? initialSource}) {
    if (_closed) return Future.value(false);
    if (initialSource != null && _timer == null && _generation == 0) {
      _source = _committedSource = initialSource;
    }
    _timer ??= Timer.periodic(interval, (_) => unawaited(_refresh()));
    return _refresh();
  }

  Future<bool> _refresh({bool forSelection = false}) {
    if (_closed) return Future.value(false);
    if (_selectionGeneration != null && !forSelection) {
      _refreshQueued = true;
      return Future.value(false);
    }
    if (_commandsPending > 0) return Future.value(isConnected);
    return _reading ??= _read().whenComplete(() {
      _reading = null;
      _drainRefresh();
    });
  }

  void _drainRefresh() {
    if (_refreshQueued &&
        !_closed &&
        _selectionGeneration == null &&
        _commandsPending == 0) {
      _refreshQueued = false;
      scheduleMicrotask(() => unawaited(_refresh()));
    }
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
      final hasNewArtwork =
          artwork is Uint8List &&
          artwork.isNotEmpty &&
          snapshot.coverVersion.isNotEmpty &&
          snapshot.coverVersion != _cover;
      _sources = sources;
      _connected = true;
      if (_diagnosticSnapshot?.sourceAppId != snapshot.sourceAppId) {
        _audioGeneration++;
        _clearAudioSample();
      }
      _diagnosticSnapshot = snapshot;
      _bridgeError = null;
      if (_playing != snapshot.isPlaying) {
        _playing = snapshot.isPlaying;
        if (_spectrumEnabled) _startSpectrumTimer();
      }
      _events.add(MediaSnapshotEvent(snapshot));
      if (_closed || generation != _generation) return false;
      
      
      if (hasNewArtwork) {
        _cover = snapshot.coverVersion;
        _events.add(MediaArtworkEvent(snapshot.coverVersion, artwork));
      } else if (snapshot.coverVersion.isEmpty) {
        _cover = '';
      }
      if (!_closed && generation == _generation) {
        _events.add(const MediaHeartbeatEvent());
      }
      return true;
    } catch (error) {
      if (!_closed && generation == _generation) {
        final wasConnected = _connected;
        _connected = false;
        _diagnosticSnapshot = null;
        _bridgeError = switch (error) {
          TimeoutException() => 'bridgeTimeout',
          FormatException() => 'invalidSnapshot',
          _ => 'bridgeUnavailable',
        };
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
    if (isConnected && _selectionGeneration == null && id == _source) return;
    final generation = ++_generation;
    _selectionGeneration = generation;
    _audioGeneration++;
    _clearAudioSample();
    _source = id;
    _cover = '';
    _connected = false;
    _diagnosticSnapshot = null;
    _bridgeError = null;
    _lastCommand = null;
    _lastCommandResult = null;
    try {
      
      
      await _reading;
      await _commandTail;
      if (_closed || generation != _generation) {
        throw StateError('Source selection superseded');
      }
      final connected = await _refresh(forSelection: true);
      if (_closed || generation != _generation) {
        throw StateError('Source selection superseded');
      }
      if (!connected) {
        _source = _committedSource;
        _refreshQueued = true;
        throw StateError('Native source selection unavailable');
      }
      _committedSource = id;
    } finally {
      if (_selectionGeneration == generation) {
        _selectionGeneration = null;
        _drainRefresh();
      }
    }
  }

  @override
  void setSpectrumEnabled(bool enabled) {
    if (_closed || _spectrumEnabled == enabled) return;
    _spectrumEnabled = enabled;
    _audioGeneration++;
    _clearAudioSample();
    _spectrumTimer?.cancel();
    unawaited(_demand(enabled));
    if (enabled) {
      _startSpectrumTimer();
      unawaited(_pollSpectrum());
    }
  }

  void _clearAudioSample() {
    audioFrames = 0;
    audioProcessId = 0;
    audioLookupOpenedProcesses = 0;
    audioStatus = '';
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
    final generation = _audioGeneration;
    try {
      await channel
          .invokeMethod<void>('spectrumDemand', {'enabled': enabled})
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      if (!_closed && generation == _audioGeneration) {
        audioStatus = 'audio_channel_unavailable';
      }
    }
  }

  Future<void> _pollSpectrum() async {
    if (_closed ||
        !_spectrumEnabled ||
        !isConnected ||
        _selectionGeneration != null ||
        _spectrumReading) {
      return;
    }
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
      if (!_closed && generation == _audioGeneration) {
        audioStatus = 'audio_channel_unavailable';
      }
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
    if (_closed || _selectionGeneration != null || _commandsPending >= 4) {
      return Future.value(false);
    }
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
        if (!_closed && generation == _generation) {
          _lastCommand = command;
          _lastCommandResult = accepted == true ? 'accepted' : 'notAccepted';
        }
        result.complete(
          !_closed && generation == _generation && accepted == true,
        );
      } catch (_) {
        if (!_closed && generation == _generation) {
          _lastCommand = command;
          _lastCommandResult = 'channelUnavailable';
        }
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
    _diagnosticSnapshot = null;
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
