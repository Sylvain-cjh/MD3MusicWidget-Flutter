import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef AudioOutput = ({String id, String name, String bluetoothGroup});
typedef AudioOutputVolumeState = ({double level, bool muted});

class AudioOutputs extends ChangeNotifier {
  final MethodChannel channel;
  final Duration noticeDuration;
  final ValueNotifier<AudioOutput?> bluetoothNotice = ValueNotifier(null);
  List<AudioOutput> _outputs = const [];
  String _defaultId = '', _consoleId = '';
  Set<String>? _connectedBluetooth;
  Future<void>? _starting;
  Timer? _noticeTimer;
  int _eventSerial = 0;
  bool _watching = false, _available = false, _disposed = false;
  bool _switching = false, _selectFailed = false;

  AudioOutputs({
    this.channel = const MethodChannel('md3_music_widget/audio_outputs'),
    this.noticeDuration = const Duration(milliseconds: 2800),
  });

  List<AudioOutput> get outputs => _outputs;
  String get defaultId => _defaultId;
  bool get available => _available;
  bool get switching => _switching;
  bool get selectFailed => _selectFailed;

  bool isCurrent(String id) =>
      !_disposed && !_switching && id.isNotEmpty && id == _defaultId;

  Future<AudioOutputVolumeState?> readVolume(String id) => _volume(id);

  Future<AudioOutputVolumeState?> setVolume(String id, double value) =>
      value.isFinite ? _volume(id, value.clamp(0.0, 1.0)) : Future.value(null);

  Future<AudioOutputVolumeState?> _volume(String id, [double? value]) async {
    if (!isCurrent(id)) return null;
    try {
      final result = await channel.invokeMapMethod<String, Object?>(
        value == null ? 'readVolume' : 'setVolume',
        value == null ? id : {'id': id, 'level': value},
      );
      final level = result?['level'];
      if (!isCurrent(id) || level is! num || !level.isFinite) return null;
      return (
        level: level.toDouble().clamp(0.0, 1.0),
        muted: result?['muted'] == true,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> start() {
    if (_disposed || _watching) return Future.value();
    return _starting ??= _watch().whenComplete(() => _starting = null);
  }

  Future<void> _watch() async {
    channel.setMethodCallHandler((call) async {
      if (_disposed || call.method != 'changed') return;
      _eventSerial++;
      _accept(call.arguments);
    });
    final serial = _eventSerial;
    try {
      final reply = await channel.invokeMapMethod<Object?, Object?>('watch');
      if (_disposed) return;
      _watching = reply?['watching'] == true;
      if (_eventSerial == serial) _accept(reply?['snapshot']);
    } on PlatformException {
      _watching = false;
    } on MissingPluginException {
      _watching = false;
    }
  }

  void _accept(Object? message) {
    
    if (_disposed || message is! Map || message['available'] != true) return;
    final list = message['outputs'];
    if (list is! List) return;
    final byId = <String, AudioOutput>{};
    for (final data in list) {
      if (data is! Map || data['id'] is! String) continue;
      final id = data['id'] as String;
      if (id.isEmpty) continue;
      byId[id] = (
        id: id,
        name: data['name'] is String ? data['name'] as String : '',
        bluetoothGroup: data['bluetoothGroup'] is String
            ? data['bluetoothGroup'] as String
            : '',
      );
    }
    final outputs = byId.values.toList()
      ..sort((a, b) {
        final byName = a.name.compareTo(b.name);
        return byName == 0 ? a.id.compareTo(b.id) : byName;
      });
    final defaultId = message['defaultId']?.toString() ?? '';
    final consoleId = message['consoleId']?.toString() ?? '';
    final bluetooth = <String, AudioOutput>{};
    for (final output in outputs) {
      if (output.bluetoothGroup.isEmpty) continue;
      
      if (output.id == defaultId ||
          !bluetooth.containsKey(output.bluetoothGroup)) {
        bluetooth[output.bluetoothGroup] = output;
      }
    }
    final previous = _connectedBluetooth;
    _connectedBluetooth = bluetooth.keys.toSet();
    final shown = bluetoothNotice.value;
    if (shown != null && !bluetooth.containsKey(shown.bluetoothGroup)) {
      _noticeTimer?.cancel();
      bluetoothNotice.value = null;
    }
    if (previous != null) {
      for (final entry in bluetooth.entries) {
        if (previous.contains(entry.key)) continue;
        bluetoothNotice.value = entry.value;
        _noticeTimer?.cancel();
        _noticeTimer = Timer(
          noticeDuration,
          () => bluetoothNotice.value = null,
        );
        break;
      }
    }
    if (_available &&
        defaultId == _defaultId &&
        consoleId == _consoleId &&
        listEquals(outputs, _outputs)) {
      return;
    }
    _available = true;
    _outputs = List.unmodifiable(outputs);
    _defaultId = defaultId;
    _consoleId = consoleId;
    notifyListeners();
  }

  Future<bool> select(String id) async {
    if (_disposed || _switching || !_outputs.any((device) => device.id == id)) {
      return false;
    }
    if (_defaultId == id && _consoleId == id) {
      if (_selectFailed) {
        _selectFailed = false;
        notifyListeners();
      }
      return true;
    }
    _switching = true;
    _selectFailed = false;
    notifyListeners();
    final serial = _eventSerial;
    var succeeded = false;
    try {
      final reply = await channel.invokeMapMethod<Object?, Object?>(
        'select',
        id,
      );
      if (_disposed) return false;
      if (_eventSerial == serial) _accept(reply?['snapshot']);
      succeeded =
          reply?['selected'] == true && _defaultId == id && _consoleId == id;
      return succeeded;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } finally {
      if (!_disposed) {
        _switching = false;
        _selectFailed = !succeeded;
        notifyListeners();
      }
    }
  }

  Future<bool> openWindowsSettings() async {
    try {
      return await channel.invokeMethod<bool>('openWindowsSettings') == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _noticeTimer?.cancel();
    bluetoothNotice.dispose();
    channel.setMethodCallHandler(null);
    super.dispose();
  }
}
