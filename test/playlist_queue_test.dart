import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_widget_flutter/core/app_state.dart';
import 'package:music_widget_flutter/core/local_playlist_queue_provider.dart';
import 'package:music_widget_flutter/core/media_provider.dart';
import 'package:music_widget_flutter/core/platform_provider.dart';
import 'package:music_widget_flutter/core/queue_coordinator.dart';
import 'package:music_widget_flutter/core/qq_music_playlist_queue_provider.dart';
import 'package:music_widget_flutter/ui/widgets/music_next_up_panel.dart';

const firstTrack = PlatformTrack(
  sourceAppId: 'QQMusic.exe',
  trackVersion: '1',
  title: '第一首',
  artist: '歌手 A',
  durationMs: 100000,
);

final class DelayedQueueProvider implements QueuePlatformProvider {
  final Completer<PlatformQueue?> first = Completer<PlatformQueue?>();
  final Completer<PlatformQueue?> second = Completer<PlatformQueue?>();
  int calls = 0;

  @override
  String get id => 'delayed';

  @override
  bool accepts(PlatformTrack track) => true;

  @override
  Future<PlatformQueue?> loadQueue(PlatformTrack track) =>
      ++calls == 1 ? first.future : second.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M3U and JSON preserve ordered title and artist metadata', () {
    final m3u = parseM3uPlaylist(
      '#EXTM3U\n#EXTINF:180,歌手 A - 第一首\nC:\\music\\a.mp3\n'
      '#EXTINF:200,歌手 B - 第二首\nC:\\music\\b.mp3\n',
    );
    expect(m3u.map((item) => item.title), ['第一首', '第二首']);
    expect(m3u.last.artist, '歌手 B');

    final json = parsePlaylistJson(
      '{"tracks":[{"title":"第一首","artist":"歌手 A"},'
      '{"title":"第二首","artist":"歌手 B"}]}',
    );
    expect(json.map((item) => item.title), ['第一首', '第二首']);
    final filenames = parseM3uPlaylist('#EXTM3U\nC:\\music\\歌手 A - 第一首.mp3\n');
    expect(filenames.single.title, '第一首');
    expect(filenames.single.artist, '歌手 A');
  });

  test('QQ playlist input accepts only a numeric ID or HTTPS QQ link', () {
    expect(parseQqPlaylistId('8081238754'), '8081238754');
    expect(
      parseQqPlaylistId('https://y.qq.com/n/ryqq/playlist/8081238754'),
      '8081238754',
    );
    expect(
      parseQqPlaylistId('https://y.qq.com/n/yqq/playlist/8081238754.html'),
      '8081238754',
    );
    expect(
      parseQqPlaylistId('https://evil.example/playlist/8081238754'),
      isNull,
    );
    expect(
      parseQqPlaylistId('http://y.qq.com/n/ryqq/playlist/8081238754'),
      isNull,
    );
  });

  test(
    'QQ playlist provider reads ordered tracks and caches the response',
    () async {
      var requests = 0;
      final provider = QqMusicPlaylistQueueProvider(
        playlistInput: () => 'https://y.qq.com/n/ryqq/playlist/8081238754',
        fetchJson: (uri) async {
          requests++;
          expect(uri.queryParameters['disstid'], '8081238754');
          return {
            'code': 0,
            'cdlist': [
              {
                'songlist': [
                  {
                    'songmid': 'a',
                    'songname': '第一首',
                    'singer': [
                      {'name': '歌手 A'},
                    ],
                  },
                  {
                    'songmid': 'b',
                    'songname': '第二首',
                    'singer': [
                      {'name': '歌手 B'},
                    ],
                  },
                  {
                    'songmid': 'c',
                    'songname': '第三首',
                    'singer': [
                      {'name': '歌手 A'},
                      {'name': '歌手 C'},
                    ],
                  },
                ],
              },
            ],
          };
        },
      );
      final queue = await provider.loadQueue(firstTrack);
      expect(queue?.currentIndex, 0);
      expect(queue?.nextItem()?.title, '第二首');
      expect(requests, 1);
      await provider.loadQueue(firstTrack);
      expect(requests, 1);
      final duet = await provider.loadQueue(
        const PlatformTrack(
          sourceAppId: 'QQMusic.exe',
          trackVersion: '3',
          title: '第三首',
          artist: '歌手 A、歌手 C',
          durationMs: 100000,
        ),
      );
      expect(duet?.currentIndex, 2);
      expect(requests, 1);
      provider.invalidate();
      await provider.loadQueue(firstTrack);
      expect(requests, 2);
      expect(
        provider.accepts(
          const PlatformTrack(
            sourceAppId: 'Spotify.exe',
            trackVersion: '1',
            title: '第一首',
            artist: '歌手 A',
            durationMs: 100000,
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'Queue match must be unique and next item follows playlist order',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'playlist_queue_',
      );
      try {
        final file = File(
          '${directory.path}${Platform.pathSeparator}list.json',
        );
        await file.writeAsString(
          '[{"title":"第一首","artist":"歌手 A"},'
          '{"title":"第二首","artist":"歌手 B"}]',
        );
        final provider = LocalPlaylistQueueProvider(() => file.path);
        final queue = await provider.loadQueue(firstTrack);
        expect(queue?.currentIndex, 0);
        expect(queue?.nextItem()?.title, '第二首');

        await file.writeAsString(
          '[{"title":"第一首","artist":"歌手 A"},'
          '{"title":"第一首","artist":"歌手 A"}]',
        );
        final ambiguous = await provider.loadQueue(firstTrack);
        expect(ambiguous?.currentIndex, isNull);
        expect(ambiguous?.nextItem(), isNull);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('Late provider result cannot replace a newer track queue', () async {
    final registry = PlatformProviderRegistry();
    final provider = DelayedQueueProvider();
    registry.register(provider);
    final coordinator = QueueCoordinator(registry);
    final oldRequest = coordinator.setTrack(firstTrack, enabled: true);
    final newRequest = coordinator.setTrack(
      const PlatformTrack(
        sourceAppId: 'QQMusic.exe',
        trackVersion: '2',
        title: '第二首',
        artist: '歌手 B',
        durationMs: 200000,
      ),
      enabled: true,
    );
    provider.second.complete(
      PlatformQueue(
        items: [const PlatformQueueItem(id: '2', title: '第二首', artist: '歌手 B')],
      ),
    );
    await newRequest;
    provider.first.complete(
      PlatformQueue(
        items: [const PlatformQueueItem(id: '1', title: '第一首', artist: '歌手 A')],
      ),
    );
    await oldRequest;
    expect(coordinator.queue?.items.single.title, '第二首');
    coordinator.dispose();
  });

  test('Near-end prediction hides during shuffle and track repeat', () async {
    final directory = await Directory.systemTemp.createTemp('playlist_state_');
    try {
      final file = File('${directory.path}${Platform.pathSeparator}list.json');
      await file.writeAsString(
        '[{"title":"第一首","artist":"歌手 A"},'
        '{"title":"第二首","artist":"歌手 B"}]',
      );
      AppState.playlistFilePath = file.path;
      AppState.showNextUp = true;
      AppState.isPlaying = true;
      AppState.currentPlatformTrack = firstTrack;
      AppState.isShuffleActive = false;
      AppState.autoRepeatMode = '';
      AppState.nextUpLeadSeconds = 20;
      await AppState.queue.setTrack(firstTrack, enabled: true, force: true);
      AppState.updatePlaybackTimeline(
        positionMs: 70000,
        durationMs: 100000,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      expect(AppState.shouldPreviewNext, isFalse);
      AppState.updatePlaybackTimeline(
        positionMs: 85000,
        durationMs: 100000,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      expect(AppState.shouldPreviewNext, isTrue);
      AppState.isShuffleActive = true;
      expect(AppState.shouldPreviewNext, isFalse);
      AppState.isShuffleActive = false;
      AppState.autoRepeatMode = 'track';
      expect(AppState.shouldPreviewNext, isFalse);
    } finally {
      AppState.showNextUp = false;
      AppState.playlistFilePath = '';
      AppState.currentPlatformTrack = null;
      AppState.isPlaying = false;
      AppState.isShuffleActive = null;
      AppState.autoRepeatMode = '';
      await AppState.queue.setTrack(null, enabled: false, force: true);
      await directory.delete(recursive: true);
    }
  });

  testWidgets('Next-up card changes from queue status to upcoming track', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('next_up_card_');
    try {
      final file = File('${directory.path}${Platform.pathSeparator}list.json');
      file.writeAsStringSync(
        '[{"title":"第一首","artist":"歌手 A"},'
        '{"title":"第二首","artist":"歌手 B"}]',
      );
      AppState.playlistFilePath = file.path;
      AppState.showNextUp = true;
      AppState.currentPlatformTrack = firstTrack;
      AppState.isPlaying = true;
      AppState.isShuffleActive = false;
      AppState.autoRepeatMode = '';
      await tester.runAsync(
        () => AppState.queue.setTrack(firstTrack, enabled: true, force: true),
      );
      AppState.updatePlaybackTimeline(
        positionMs: 70000,
        durationMs: 100000,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 320, height: 48, child: MusicNextUpPanel()),
          ),
        ),
      );
      expect(find.textContaining('播放列表 · 1/2'), findsOneWidget);
      AppState.updatePlaybackTimeline(
        positionMs: 85000,
        durationMs: 100000,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.textContaining('预计下一首 · 第二首'), findsOneWidget);
      AppState.isShuffleActive = true;
      AppState.updatePlaybackTimeline(
        positionMs: 86000,
        durationMs: 100000,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('随机播放中'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      AppState.showNextUp = false;
      AppState.playlistFilePath = '';
      AppState.currentPlatformTrack = null;
      AppState.isPlaying = false;
      AppState.isShuffleActive = null;
      AppState.autoRepeatMode = '';
      await AppState.queue.setTrack(null, enabled: false, force: true);
      directory.deleteSync(recursive: true);
    }
  });

  test('SMTC playback mode fields are optional for older fetchers', () {
    final old = MediaSnapshot.fromJson({
      'processId': 1,
      'title': '第一首',
      'artist': '歌手 A',
    });
    expect(old.isShuffleActive, isNull);
    expect(old.autoRepeatMode, '');
    final current = MediaSnapshot.fromJson({
      'processId': 1,
      'isShuffleActive': true,
      'autoRepeatMode': 'Track',
    });
    expect(current.isShuffleActive, isTrue);
    expect(current.autoRepeatMode, 'track');
  });

  test(
    'Playlist preferences survive reload and remain disabled by default',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AppState.loadSettings();
      expect(AppState.showNextUp, isFalse);
      AppState.showNextUp = true;
      AppState.playlistFilePath = r'C:\music\playlist.m3u8';
      AppState.qqPlaylistLink = '8081238754';
      AppState.nextUpLeadSeconds = 30;
      await AppState.saveSettings();
      await AppState.flushSettings();
      AppState.showNextUp = false;
      AppState.playlistFilePath = '';
      AppState.qqPlaylistLink = '';
      AppState.nextUpLeadSeconds = 20;
      await AppState.loadSettings();
      expect(AppState.showNextUp, isTrue);
      expect(AppState.playlistFilePath, r'C:\music\playlist.m3u8');
      expect(AppState.qqPlaylistLink, '8081238754');
      expect(AppState.nextUpLeadSeconds, 30);
      AppState.showNextUp = false;
      AppState.playlistFilePath = '';
      AppState.qqPlaylistLink = '';
      AppState.nextUpLeadSeconds = 20;
      await AppState.queue.setTrack(null, enabled: false, force: true);
    },
  );
}
