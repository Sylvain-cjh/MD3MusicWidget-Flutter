import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';



final class PersistentCache {
  Directory _directory;
  Directory get directory => _directory;
  final int Function() limitBytes;
  final int maximumEntryBytes;
  final bool Function()? isEnabled;
  bool get _enabled => isEnabled?.call() ?? true;
  final Map<String, Map<String, dynamic>> _entries = {};
  Future<void> _tail = Future.value();
  bool _loaded = false;
  bool _indexDirty = false;
  Timer? _indexTimer;
  int debugIndexWrites = 0;
  PersistentCache({
    required Directory directory,
    required this.limitBytes,
    this.maximumEntryBytes = 16 * 1024 * 1024,
    this.isEnabled,
    
    
  }) : _directory = directory;

  static Future<String> _checksum(Uint8List bytes) => bytes.length >= 256 * 1024
      ? Isolate.run(() => sha256.convert(bytes).toString())
      : Future.value(sha256.convert(bytes).toString());

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  String _digest(String key) => sha256.convert(utf8.encode(key)).toString();
  File _file(String digest) =>
      File('${directory.path}${Platform.pathSeparator}$digest.bin');
  File get _index =>
      File('${directory.path}${Platform.pathSeparator}index.json');

  Future<void> _load() async {
    if (!_enabled) return;
    if (_loaded) return;
    await directory.create(recursive: true);
    try {
      if (await _index.length() <= 2 * 1024 * 1024) {
        final json = jsonDecode(await _index.readAsString());
        if (json is Map && json['version'] == 1 && json['entries'] is Map) {
          for (final entry in (json['entries'] as Map).entries) {
            if (entry.key is! String ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key) ||
                entry.value is! Map) {
              continue;
            }
            final value = Map<String, dynamic>.from(entry.value as Map);
            if (value['size'] is int &&
                value['size'] > 0 &&
                value['size'] <= maximumEntryBytes &&
                value['used'] is int &&
                value['checksum'] is String) {
              _entries[entry.key] = value;
            }
          }
        }
      }
    } catch (_) {}
    
    
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      final match = RegExp(r'^([a-f0-9]{64})\.bin$').firstMatch(name);
      if (entity is File &&
          match != null &&
          !_entries.containsKey(match.group(1))) {
        try {
          await entity.delete();
        } catch (_) {}
      }
      if (entity is File &&
          (name == 'index.json.tmp' ||
              RegExp(r'^[a-f0-9]{64}\.bin\.tmp$').hasMatch(name))) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    _loaded = true;
    await _trim();
  }

  Future<void> _saveIndex() async {
    if (!_enabled || !_indexDirty) return;
    final temporary = File('${_index.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'version': 1, 'entries': _entries}),
      flush: true,
    );
    await temporary.rename(_index.path);
    _indexDirty = false;
    debugIndexWrites++;
  }

  void _deferIndexSave() {
    _indexTimer ??= Timer(const Duration(milliseconds: 400), () {
      _indexTimer = null;
      unawaited(
        _serial(() async {
          try {
            await _saveIndex();
          } catch (_) {}
        }),
      );
    });
  }

  Future<void> _drop(String digest) async {
    if (!_enabled) return;
    if (_entries.remove(digest) != null) _indexDirty = true;
    try {
      if (await _file(digest).exists()) await _file(digest).delete();
    } catch (_) {}
  }

  Future<void> _trim() async {
    var total = _entries.values.fold<int>(
      0,
      (sum, entry) => sum + (entry['size'] as int),
    );
    final budget = limitBytes().clamp(0, 1024 * 1024 * 1024);
    final oldest = _entries.keys.toList()
      ..sort(
        (a, b) => (_entries[a]!['used'] as int).compareTo(
          _entries[b]!['used'] as int,
        ),
      );
    for (final key in oldest) {
      if (total <= budget) break;
      total -= _entries[key]!['size'] as int;
      await _drop(key);
    }
    await _saveIndex();
  }

  Future<Uint8List?> get(String key) {
    if (!_enabled) return Future.value();
    return _serial(() async {
      if (!_enabled) return null;
      try {
        await _load();
        if (limitBytes() <= 0) return null;
        final digest = _digest(key);
        final entry = _entries[digest];
        if (entry == null) return null;
        final file = _file(digest);
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file ||
            await file.length() != entry['size']) {
          await _drop(digest);
          await _saveIndex();
          return null;
        }
        final bytes = await file.readAsBytes();
        if (await _checksum(bytes) != entry['checksum']) {
          await _drop(digest);
          await _saveIndex();
          return null;
        }
        entry['used'] = DateTime.now().microsecondsSinceEpoch;
        _indexDirty = true;
        _deferIndexSave();
        return bytes;
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> put(String key, Uint8List bytes) {
    
    
    if (!_enabled ||
        bytes.isEmpty ||
        bytes.length > maximumEntryBytes ||
        bytes.length > limitBytes()) {
      return Future.value();
    }
    
    final snapshot = Uint8List.fromList(bytes);
    return _serial(() async {
      if (!_enabled) return;
      try {
        await _load();
        if (snapshot.length > limitBytes()) {
          return;
        }
        final digest = _digest(key), file = _file(_digest(key));
        final temporary = File('${file.path}.tmp');
        final checksum = await _checksum(snapshot);
        await temporary.writeAsBytes(snapshot, flush: true);
        await temporary.rename(file.path);
        _entries[digest] = {
          'size': snapshot.length,
          'used': DateTime.now().microsecondsSinceEpoch,
          'checksum': checksum,
        };
        _indexDirty = true;
        await _trim();
      } catch (_) {}
    });
  }

  Future<void> remove(String key) {
    if (!_enabled) return Future.value();
    return _serial(() async {
      try {
        await _load();
        await _drop(_digest(key));
        await _saveIndex();
      } catch (_) {}
    });
  }

  Future<void> applyLimit() {
    if (!_enabled) return Future.value();
    return _serial(() async {
      try {
        await _load();
        await _trim();
      } catch (_) {}
    });
  }

  Future<void> clear() {
    if (!_enabled) return Future.value();
    return _serial(() async {
      try {
        await _load();
        for (final key in _entries.keys.toList()) {
          await _drop(key);
        }
        await _saveIndex();
      } catch (_) {}
    });
  }

  Future<int> get usedBytes {
    if (!_enabled) return Future.value(0);
    return _serial(() async {
      try {
        await _load();
        return _entries.values.fold<int>(
          0,
          (sum, entry) => sum + (entry['size'] as int),
        );
      } catch (_) {
        return 0;
      }
    });
  }

  
  
  Future<void> relocate(Directory target, {bool copyExisting = true}) {
    if (!_enabled) {
      _indexTimer?.cancel();
      _indexTimer = null;
      _directory = target.absolute;
      _entries.clear();
      _loaded = _indexDirty = false;
      return Future.value();
    }
    return _serial(() async {
      final destination = target.absolute;
      final current = directory.absolute;
      final same = Platform.isWindows
          ? current.path.toLowerCase() == destination.path.toLowerCase()
          : current.path == destination.path;
      if (same) return;
      _indexTimer?.cancel();
      _indexTimer = null;
      if (!_enabled) {
        _directory = destination;
        _entries.clear();
        _loaded = _indexDirty = false;
        return;
      }
      await _load();
      await _saveIndex();
      final replacement = PersistentCache(
        directory: destination,
        limitBytes: limitBytes,
        maximumEntryBytes: maximumEntryBytes,
        isEnabled: isEnabled,
      );
      await replacement._load();
      if (copyExisting) {
        for (final entry in _entries.entries) {
          final existing = replacement._entries[entry.key];
          if (existing != null &&
              (existing['used'] as int) > (entry.value['used'] as int)) {
            final prior = replacement._file(entry.key);
            if (await FileSystemEntity.type(prior.path, followLinks: false) ==
                    FileSystemEntityType.file &&
                await prior.length() == existing['size'] &&
                await _checksum(await prior.readAsBytes()) ==
                    existing['checksum']) {
              continue;
            }
          }
          final source = _file(entry.key);
          if (await FileSystemEntity.type(source.path, followLinks: false) !=
                  FileSystemEntityType.file ||
              await source.length() != entry.value['size']) {
            continue;
          }
          final bytes = await source.readAsBytes();
          if (await _checksum(bytes) != entry.value['checksum']) continue;
          final file = replacement._file(entry.key);
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsBytes(bytes, flush: true);
          await temporary.rename(file.path);
          replacement._entries[entry.key] = Map<String, dynamic>.from(
            entry.value,
          );
          replacement._indexDirty = true;
        }
      }
      await replacement._trim();
      _directory = destination;
      _entries
        ..clear()
        ..addAll(replacement._entries);
      _loaded = true;
      _indexDirty = false;
    });
  }

  Future<void> flush() {
    if (!_enabled) return Future.value();
    _indexTimer?.cancel();
    _indexTimer = null;
    return _serial(() async {
      _indexTimer?.cancel();
      _indexTimer = null;
      try {
        await _saveIndex();
      } catch (_) {}
    });
  }
}
