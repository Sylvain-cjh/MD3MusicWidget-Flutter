import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';



final class PersistentCache {
  final Directory directory;
  final int Function() limitBytes;
  final int maximumEntryBytes;
  final bool Function()? isEnabled;
  bool get _enabled => isEnabled?.call() ?? true;
  final Map<String, Map<String, dynamic>> _entries = {};
  Future<void> _tail = Future.value();
  bool _loaded = false;
  PersistentCache({
    required this.directory,
    required this.limitBytes,
    this.maximumEntryBytes = 16 * 1024 * 1024,
    this.isEnabled,
  });

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
    if (!_enabled) return;
    final temporary = File('${_index.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'version': 1, 'entries': _entries}),
      flush: true,
    );
    await temporary.rename(_index.path);
  }

  Future<void> _drop(String digest) async {
    if (!_enabled) return;
    _entries.remove(digest);
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
        final digest = _digest(key), entry = _entries[_digest(key)];
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
        if (sha256.convert(bytes).toString() != entry['checksum']) {
          await _drop(digest);
          await _saveIndex();
          return null;
        }
        entry['used'] = DateTime.now().microsecondsSinceEpoch;
        await _saveIndex();
        return bytes;
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> put(String key, Uint8List bytes) {
    
    
    if (!_enabled) return Future.value();
    return _serial(() async {
      if (!_enabled) return;
      try {
        await _load();
        if (bytes.isEmpty ||
            bytes.length > limitBytes() ||
            bytes.length > maximumEntryBytes) {
          return;
        }
        final digest = _digest(key), file = _file(_digest(key));
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
        _entries[digest] = {
          'size': bytes.length,
          'used': DateTime.now().microsecondsSinceEpoch,
          'checksum': sha256.convert(bytes).toString(),
        };
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

  Future<void> flush() => _tail;
}
