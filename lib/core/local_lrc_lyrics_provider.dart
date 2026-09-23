import 'dart:convert';
import 'dart:io';

import 'lyrics_document.dart';
import 'platform_provider.dart';

final class LocalLrcLyricsProvider implements LyricsPlatformProvider {
  static const String providerId = 'localLrc';
  final String Function() directoryPath;

  const LocalLrcLyricsProvider(this.directoryPath);

  @override
  String get id => providerId;

  @override
  bool accepts(PlatformTrack track) =>
      directoryPath().trim().isNotEmpty && track.title.trim().isNotEmpty;

  @override
  Future<LyricsDocument?> loadLyrics(PlatformTrack track) async {
    final directory = directoryPath().trim();
    if (directory.isEmpty) return null;
    final folder = Directory(directory);
    if (!await folder.exists()) return null;
    final title = _safeName(track.title);
    final artist = _safeName(track.artist);
    if (title.isEmpty) return null;
    final names = <String>[
      if (artist.isNotEmpty) '$artist - $title.lrc',
      '$title.lrc',
    ];
    for (final name in names) {
      final file = File('$directory${Platform.pathSeparator}$name');
      final document = await _readDocument(file);
      if (document != null) return document;
    }
    final titleKey = _matchKey(track.title);
    final artistKey = _matchKey(track.artist);
    final candidates = <(int, File)>[];
    var scanned = 0;
    await for (final entry in folder.list(followLinks: false)) {
      if (++scanned > 512) break;
      if (entry is! File || !entry.path.toLowerCase().endsWith('.lrc')) {
        continue;
      }
      final filename = entry.uri.pathSegments.last;
      final key = _matchKey(filename.substring(0, filename.length - 4));
      if (titleKey.isEmpty || !key.contains(titleKey)) continue;
      final artistMatched = artistKey.isNotEmpty && key.contains(artistKey);
      candidates.add((artistMatched ? 2 : 1, entry));
    }
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    for (final candidate in candidates) {
      final document = await _readDocument(candidate.$2);
      if (document == null) continue;
      final metadataTitle = _matchKey(document.title);
      final metadataArtist = _matchKey(document.artist);
      if (metadataTitle.isNotEmpty && metadataTitle != titleKey) continue;
      if (metadataArtist.isNotEmpty &&
          artistKey.isNotEmpty &&
          !metadataArtist.contains(artistKey) &&
          !artistKey.contains(metadataArtist)) {
        continue;
      }
      if (candidate.$1 == 1 &&
          metadataTitle.isEmpty &&
          _matchKey(
                candidate.$2.uri.pathSegments.last.replaceFirst(
                  RegExp(r'\.lrc$', caseSensitive: false),
                  '',
                ),
              ) !=
              titleKey) {
        continue;
      }
      return document;
    }
    return null;
  }

  static Future<LyricsDocument?> _readDocument(File file) async {
    if (!await file.exists() || await file.length() > 2 * 1024 * 1024) {
      return null;
    }
    try {
      final bytes = await file.readAsBytes();
      String contents;
      if (bytes.length >= 2 &&
          ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
              (bytes[0] == 0xfe && bytes[1] == 0xff))) {
        final littleEndian = bytes[0] == 0xff;
        final units = <int>[];
        for (var i = 2; i + 1 < bytes.length; i += 2) {
          units.add(
            littleEndian
                ? bytes[i] | (bytes[i + 1] << 8)
                : (bytes[i] << 8) | bytes[i + 1],
          );
        }
        contents = String.fromCharCodes(units);
      } else {
        contents = utf8.decode(bytes);
      }
      final document = LyricsDocument.parseLrc(
        contents.replaceFirst('\ufeff', ''),
      );
      return document.isEmpty ? null : document;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static String _matchKey(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );

  static String _safeName(String value) => value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
}
