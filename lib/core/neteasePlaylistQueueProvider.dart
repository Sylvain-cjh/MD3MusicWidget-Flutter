import 'platformProvider.dart';
import 'neteaseLyricsProvider.dart';

String? parseNeteasePlaylistId(String input) {
  final value = input.trim();
  if (RegExp(r'^\d{1,20}$').hasMatch(value)) return value;
  final text =
      RegExp(r'https://[^\s<>"\u3000]+').firstMatch(value)?.group(0) ?? value;
  final uri = Uri.tryParse(text.replaceFirst(RegExp(r'[),，。！？）]+$'), ''));
  if (uri == null ||
      uri.scheme != 'https' ||
      !(uri.host == 'music.163.com' || uri.host.endsWith('.music.163.com'))) {
    return null;
  }
  final page = uri.fragment.isNotEmpty ? Uri.tryParse(uri.fragment) : uri;
  if (page == null || !RegExp(r'(?:^|/)playlist(?:/|$)').hasMatch(page.path)) {
    return null;
  }
  final id = page.queryParameters['id'];
  return id != null && RegExp(r'^\d{1,20}$').hasMatch(id) ? id : null;
}

String _key(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

final class NeteasePlaylistQueueProvider
    implements QueuePlatformProvider, QueueContextProvider {
  final String Function() playlistInput;
  final NeteasePublicClient client;
  final Map<String, Future<List<PlatformQueueItem>>> _pending = {};
  String? _cachedId;
  List<PlatformQueueItem>? _items;
  DateTime? _expires;
  int _generation = 0;
  NeteasePlaylistQueueProvider({
    required this.playlistInput,
    NeteasePublicClient? client,
  }) : client = client ?? NeteasePublicClient();
  @override
  String get id => 'neteasePlaylist';
  @override
  String get queueContextKey =>
      parseNeteasePlaylistId(playlistInput()) ?? playlistInput().trim();
  
  @override
  bool accepts(PlatformTrack track) =>
      track.title.trim().isNotEmpty &&
      parseNeteasePlaylistId(playlistInput()) != null;
  void invalidate() {
    _generation++;
    _cachedId = null;
    _items = null;
    _expires = null;
    _pending.clear();
  }

  Future<List<PlatformQueueItem>> _read(String id) async {
    final json = await client.get('/api/playlist/detail', {'id': id});
    if (json is! Map || json['code'] != 200) {
      throw const FormatException('网易云歌单不可读取，请确认公开可见，或使用本地歌单');
    }
    final playlist = json['playlist'] ?? json['result'];
    if (playlist is! Map || playlist['tracks'] is! List) {
      throw const FormatException('网易云歌单格式不可用');
    }
    final tracks = playlist['tracks'] as List;
    final rawCount = playlist['trackCount'];
    final rawIds = playlist['trackIds'];
    final count = rawCount is num
        ? rawCount.toInt()
        : rawIds is List
        ? rawIds.length
        : tracks.length;
    if (count > tracks.length) {
      throw const FormatException('网易云只返回部分曲目，请使用本地歌单导入');
    }
    if (tracks.length > 2000) throw const FormatException('歌单超过 2000 首');
    final items = <PlatformQueueItem>[];
    for (final song in tracks) {
      if (song is! Map ||
          song['name'] is! String ||
          (song['name'] as String).trim().isEmpty) {
        throw const FormatException('歌单曲目不完整，无法可靠预测下一首');
      }
      final singers = song['artists'] ?? song['ar'];
      final artist = (singers is List ? singers : const [])
          .whereType<Map>()
          .map((s) => s['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .join(' / ');
      items.add(
        PlatformQueueItem(
          id: song['id'].toString(),
          title: song['name'] as String,
          artist: artist,
        ),
      );
    }
    return List.unmodifiable(items);
  }

  @override
  Future<PlatformQueue?> loadQueue(PlatformTrack track) async {
    if (!accepts(track)) return null;
    final id = parseNeteasePlaylistId(playlistInput())!;
    List<PlatformQueueItem> items;
    if (_cachedId == id &&
        _items != null &&
        _expires != null &&
        DateTime.now().isBefore(_expires!)) {
      items = _items!;
    } else {
      final generation = _generation;
      late final Future<List<PlatformQueueItem>> pending;
      pending =
          _pending[id] ??
          _read(id).whenComplete(() {
            if (identical(_pending[id], pending)) _pending.remove(id);
          });
      _pending[id] = pending;
      items = await pending;
      if (generation == _generation) {
        _cachedId = id;
        _items = items;
        _expires = DateTime.now().add(const Duration(minutes: 5));
      }
    }
    final matches = <int>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (_key(item.title) != _key(track.title)) continue;
      final artist = _key(track.artist);
      final singers = item.artist.split(' / ').map(_key).toSet();
      if (artist.isNotEmpty &&
          artist != '未知歌手' &&
          _key(item.artist) != artist &&
          !singers.contains(artist)) {
        continue;
      }
      matches.add(i);
    }
    return PlatformQueue(
      items: items,
      currentIndex: matches.length == 1 ? matches.single : null,
    );
  }
}
