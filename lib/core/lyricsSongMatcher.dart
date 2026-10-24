import 'platformProvider.dart';



final class LyricsSongMatcher {
  final PlatformTrack track;
  late final String _title = compact(track.title);
  late final String _base = compact(_baseTitle(track.title));
  late final Set<String> _edition = _editions(track.title);

  LyricsSongMatcher(this.track);

  static String compact(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]', unicode: true),
    '',
  );

  static bool _unknown(String value) => const {
    '',
    '未知歌手',
    '无媒体会话',
    'unknown artist',
  }.contains(value.trim().toLowerCase());

  static Set<String> _artists(Iterable<String> names) => names
      .expand(
        (name) => name.split(
          RegExp(
            r'\s+(?:feat\.?|featuring|ft\.?)\s+|[/&、;,，；]',
            caseSensitive: false,
          ),
        ),
      )
      .map(
        (name) =>
            compact(name.replaceAll(RegExp(r'[\(（\[【][^\)）\]】]*[\)）\]】]'), '')),
      )
      .where((name) => name.isNotEmpty)
      .toSet();

  static bool artistsMatch(String wanted, Iterable<String> actual) {
    if (_unknown(wanted)) return true;
    final expected = _artists([wanted]), candidates = _artists(actual);
    return candidates.isNotEmpty &&
        (expected.isNotEmpty &&
                (candidates.containsAll(expected) ||
                    expected.containsAll(candidates)) ||
            compact(wanted) == compact(actual.join('')));
  }

  static String _baseTitle(String title) => title
      .replaceAllMapped(RegExp(r'[\(（\[【]([^\)）\]】]*)[\)）\]】]'), (match) {
        final text = match[1]!;
        return RegExp(
                  r'\b(?:feat\.?|featuring|ft\.?)\s',
                  caseSensitive: false,
                ).hasMatch(text) ||
                _editions('($text)').isNotEmpty
            ? ''
            : match[0]!;
      })
      .replaceFirst(
        RegExp(r'\s+(?:feat\.?|featuring|ft\.?)\s+.*$', caseSensitive: false),
        '',
      )
      .trim();

  static Set<String> _editions(String title) {
    final qualifiers = RegExp(
      r'[\(（\[【]([^\)）\]】]*)[\)）\]】]',
    ).allMatches(title).map((match) => match[1]!).join(' ');
    final suffix = title.contains(' - ') ? title.split(' - ').last : '';
    final text = '$qualifiers $suffix'.toLowerCase();
    final editions = <String>{};
    final markers = <String, String>{
      'live': r'\blive\b|现场|演唱会',
      'remix': r'\bremix\b|混音',
      'instrumental': r'\binstrumental\b|伴奏|纯音乐',
      'cover': r'\bcover\b|翻唱',
      'acoustic': r'\bacoustic\b|\bunplugged\b|不插电',
      'slowed': r'\bslowed\b|慢速|降速',
      'sped': r'\bsped\b|\bspeed\s*up\b|加速',
    };
    for (final entry in markers.entries) {
      if (RegExp(entry.value).hasMatch(text)) editions.add(entry.key);
    }
    return editions;
  }

  List<String> get searchTerms {
    final title = track.title.trim(), artist = track.artist.trim();
    
    
    return {
      if (!_unknown(artist)) '$title $artist',
      title,
      if (_edition.isEmpty && _baseTitle(title) != title) _baseTitle(title),
    }.where((term) => term.isNotEmpty).take(3).toList();
  }

  int? score({
    required String title,
    required Iterable<String> artists,
    double? durationMs,
  }) {
    final candidate = compact(title);
    if (_title.isEmpty || candidate.isEmpty) return null;
    final edition = _editions(title);
    if (edition.length != _edition.length || !edition.containsAll(_edition)) {
      return null;
    }
    final knownArtist = !_unknown(track.artist);
    if (knownArtist && !artistsMatch(track.artist, artists)) return null;
    final durationKnown =
        track.durationMs.isFinite &&
        track.durationMs > 0 &&
        durationMs != null &&
        durationMs.isFinite &&
        durationMs > 0;
    final difference = durationKnown
        ? (track.durationMs - durationMs).abs()
        : null;
    if (difference != null && difference > 12000) return null;
    final base = compact(_baseTitle(title));
    final exact = candidate == _title;
    final equivalent = _base.isNotEmpty && base == _base;
    
    final shorter = candidate.length < _title.length ? candidate : _title;
    final longer = candidate.length < _title.length ? _title : candidate;
    final close =
        shorter.length >= 8 &&
        shorter.length / longer.length >= .9 &&
        longer.contains(shorter) &&
        knownArtist &&
        difference != null &&
        difference <= 3000;
    if (!exact && !equivalent && !close) return null;
    if (!exact && !knownArtist && !durationKnown) return null;
    return (exact
            ? 1000
            : equivalent
            ? 850
            : 650) +
        (knownArtist ? 100 : 0) +
        (difference == null ? 0 : (12000 - difference).round() ~/ 100);
  }
}
