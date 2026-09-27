import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:music_widget_flutter/core/app_state.dart';
import 'package:music_widget_flutter/core/lyrics_coordinator.dart';
import 'package:music_widget_flutter/core/lyrics_document.dart';
import 'package:music_widget_flutter/core/local_lrc_lyrics_provider.dart';
import 'package:music_widget_flutter/core/lrclib_lyrics_provider.dart';
import 'package:music_widget_flutter/core/media_provider.dart';
import 'package:music_widget_flutter/core/platform_provider.dart';
import 'package:music_widget_flutter/core/qq_music_lyrics_provider.dart';
import 'package:music_widget_flutter/ui/widgets/music_lyrics_panel.dart';

void main() {
  test('LRC supports multiple timestamps, offsets, metadata and lookup', () {
    final document = LyricsDocument.parseLrc('''
[ti:Example]
[ar:Singer]
[offset:+120]
[00:01.50][00:03.250]First line
[00:02.1]Second line
[00:04.00]Last line
''');
    expect(document.title, 'Example');
    expect(document.artist, 'Singer');
    expect(document.lines.map((line) => line.startMs), [
      1620,
      2220,
      3370,
      4120,
    ]);
    expect(document.lineAt(1000), isNull);
    expect(document.lineAt(2300)?.text, 'Second line');
    expect(document.lineAt(3500)?.text, 'First line');
  });

  test('Untimed lyrics and malformed timestamps remain safe', () {
    final plain = LyricsDocument.parseLrc('One\nTwo\n[bad:tag]');
    expect(plain.isTimed, isFalse);
    expect(plain.plainText, 'One\nTwo');
    expect(plain.lineAt(5000), isNull);
    final timed = LyricsDocument.parseLrc('[00:70.00]Invalid\n[00:01.00]Valid');
    expect(timed.lines.length, 1);
    expect(timed.lineIndexAt(double.nan), -1);
  });

  test('Older MusicFetcher snapshots still allow metadata lyric lookup', () {
    final old = MediaSnapshot.fromJson({
      'title': 'Track',
      'artist': 'Artist',
      'trackVersion': '7',
    });
    expect(old.sourceAppId, isEmpty);
    expect(PlatformTrack.fromSnapshot(old)?.title, 'Track');
    final current = MediaSnapshot.fromJson({
      'sourceAppId': 'QQMusic.exe',
      'title': 'Track',
      'artist': 'Artist',
      'trackVersion': '7',
    });
    expect(PlatformTrack.fromSnapshot(current)?.sourceAppId, 'QQMusic.exe');
  });

  test('Platform registry selects only matching lyric providers', () {
    final registry = PlatformProviderRegistry();
    final provider = _FakeLyricsProvider('qqmusic.exe', (_) async => null);
    registry.register(provider);
    expect(registry.lyricsFor(_track('QQMusic.exe', '1')), same(provider));
    expect(registry.lyricsFor(_track('other.exe', '1')), isNull);
    expect(registry.queueFor(_track('QQMusic.exe', '1')), isNull);
    registry.unregister(provider.id);
    expect(registry.lyricsFor(_track('QQMusic.exe', '1')), isNull);
  });

  test(
    'Common desktop players are identified without changing SMTC metadata',
    () {
      expect(identifyMusicPlatform('QQMusic.exe'), MusicPlatform.qqMusic);
      expect(
        identifyMusicPlatform('cloudmusic.exe'),
        MusicPlatform.neteaseCloud,
      );
      expect(identifyMusicPlatform('Spotify.exe'), MusicPlatform.spotify);
      expect(identifyMusicPlatform('AppleMusic.exe'), MusicPlatform.appleMusic);
      expect(identifyMusicPlatform('msedge.exe'), MusicPlatform.other);
    },
  );

  test(
    'LRCLIB provider validates response and caches a matching result',
    () async {
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      int requests = 0;
      String? userAgent;
      server.listen((request) async {
        requests++;
        userAgent = request.headers.value(HttpHeaders.userAgentHeader);
        expect(request.uri.queryParameters['track_name'], 'Track');
        expect(request.uri.queryParameters['artist_name'], 'Artist');
        expect(request.uri.queryParameters['duration'], '10');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'trackName': 'Track',
            'artistName': 'Artist',
            'duration': 10,
            'syncedLyrics': '[00:01.00]Line',
          }),
        );
        await request.response.close();
      });
      final provider = LrclibLyricsProvider(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/api/get'),
      );
      final track = _track('QQMusic.exe', '1');
      expect((await provider.loadLyrics(track))?.lineAt(1500)?.text, 'Line');
      expect((await provider.loadLyrics(track))?.lineAt(1500)?.text, 'Line');
      expect(requests, 1);
      expect(userAgent, contains('MD3MusicWidget'));
    },
  );

  test(
    'LRCLIB searches after an exact miss and rejects unrelated songs',
    () async {
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      int exactRequests = 0;
      int searchRequests = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/api/get') {
          exactRequests++;
          request.response.statusCode = HttpStatus.notFound;
        } else {
          searchRequests++;
          expect(request.uri.path, '/api/search');
          request.response.write(
            jsonEncode([
              {
                'trackName': 'Unrelated',
                'artistName': 'Artist',
                'duration': 10,
                'syncedLyrics': '[00:01.00]Wrong',
              },
              {
                'trackName': 'Track',
                'artistName': 'Artist',
                'duration': 10,
                'syncedLyrics': '[00:01.00]Correct',
              },
            ]),
          );
        }
        await request.response.close();
      });
      final provider = LrclibLyricsProvider(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/api/get'),
      );
      final document = await provider.loadLyrics(_track('QQMusic.exe', '1'));
      expect(document?.lineAt(1500)?.text, 'Correct');
      expect(exactRequests, 1);
      expect(searchRequests, 1);
    },
  );

  test(
    'QQ lyric source matches a candidate and falls back on a miss',
    () async {
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var qqHasResult = true;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/qq/search') {
          request.response.write(
            jsonEncode({
              'data': {
                'song': {
                  'list': qqHasResult
                      ? [
                          {
                            'songname': 'Track',
                            'songmid': 'mid-1',
                            'interval': 10,
                            'singer': [
                              {'name': 'Artist'},
                            ],
                          },
                        ]
                      : [],
                },
              },
            }),
          );
        } else if (request.uri.path == '/qq/lyric') {
          expect(request.uri.queryParameters['songmid'], 'mid-1');
          request.response.write(
            jsonEncode({'retcode': 0, 'lyric': '[00:01.00]QQ line'}),
          );
        } else {
          expect(request.uri.path, '/api/get');
          request.response.write(
            jsonEncode({
              'trackName': 'Track',
              'artistName': 'Artist',
              'duration': 10,
              'syncedLyrics': '[00:01.00]Fallback line',
            }),
          );
        }
        await request.response.close();
      });
      final root = Uri.parse('http://127.0.0.1:${server.port}');
      final provider = QqMusicLyricsProvider(
        fallback: LrclibLyricsProvider(
          endpoint: root.replace(path: '/api/get'),
        ),
        searchEndpoint: root.replace(path: '/qq/search'),
        lyricEndpoint: root.replace(path: '/qq/lyric'),
      );
      final qqDocument = await provider.loadLyrics(_track('QQMusic.exe', '1'));
      expect(qqDocument?.lineAt(1500)?.text, 'QQ line');
      expect(qqDocument?.sourceProviderId, 'qqMusic');
      qqHasResult = false;
      final fallbackProvider = QqMusicLyricsProvider(
        fallback: LrclibLyricsProvider(
          endpoint: root.replace(path: '/api/get'),
        ),
        searchEndpoint: root.replace(path: '/qq/search'),
        lyricEndpoint: root.replace(path: '/qq/lyric'),
      );
      final fallbackDocument = await fallbackProvider.loadLyrics(
        _track('QQMusic.exe', '2'),
      );
      expect(fallbackDocument?.lineAt(1500)?.text, 'Fallback line');
      expect(fallbackDocument?.sourceProviderId, 'lrclib');
    },
  );

  test('Local LRC provider reads an exact track filename', () async {
    final folder = await Directory.systemTemp.createTemp('musicwidget-lrc-');
    addTearDown(() => folder.delete(recursive: true));
    await File(
      '${folder.path}${Platform.pathSeparator}Artist - Track.lrc',
    ).writeAsString('[00:01.00]Local line');
    final provider = LocalLrcLyricsProvider(() => folder.path);
    expect(
      (await provider.loadLyrics(
        _track('QQMusic.exe', '1'),
      ))?.lineAt(1500)?.text,
      'Local line',
    );
  });

  test('Local LRC accepts a metadata-matched UTF-16 file', () async {
    final folder = await Directory.systemTemp.createTemp('musicwidget-lrc-');
    addTearDown(() => folder.delete(recursive: true));
    final contents = '[ti:Track]\n[ar:Artist]\n[00:01.00]Unicode line';
    final units = contents.codeUnits;
    await File(
      '${folder.path}${Platform.pathSeparator}Artist - Track (live).lrc',
    ).writeAsBytes([
      0xff,
      0xfe,
      for (final unit in units) ...[unit & 0xff, unit >> 8],
    ]);
    final provider = LocalLrcLyricsProvider(() => folder.path);
    expect(
      (await provider.loadLyrics(
        _track('QQMusic.exe', '1'),
      ))?.lineAt(1500)?.text,
      'Unicode line',
    );
  });

  testWidgets('Lyrics panel shows the synchronized current line', (
    tester,
  ) async {
    final track = _track('test', '1');
    AppState.platformProviders.register(
      _FakeLyricsProvider(
        'test',
        (_) async => LyricsDocument.parseLrc('[00:01.00]Current line'),
      ),
    );
    AppState.currentPlatformTrack = track;
    AppState.isPlaying = false;
    await AppState.lyrics.setTrack(track, providerId: 'test');
    AppState.lyrics.setPositionMs(1500);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: 48, child: MusicLyricsPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current line'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await AppState.lyrics.setTrack(null);
    AppState.platformProviders.unregister('test');
    AppState.currentPlatformTrack = null;
  });

  testWidgets('Lyrics source badge follows the resolved fallback provider', (
    tester,
  ) async {
    final track = _track('resolvedsourcetest', 'badge');
    AppState.platformProviders.register(
      _FakeLyricsProvider(
        'resolvedsourcetest',
        (_) async => LyricsDocument.parseLrc(
          '[00:01.00]Fallback line',
        ).withSourceProviderId('lrclib'),
      ),
    );
    AppState.currentPlatformTrack = track;
    await AppState.lyrics.setTrack(track, providerId: 'resolvedsourcetest');
    AppState.lyrics.setPositionMs(1500);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: 48, child: MusicLyricsPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(AppState.lyrics.state.providerId, 'lrclib');
    expect(find.byKey(const ValueKey('lyrics_source_lrclib')), findsOneWidget);
    expect(find.text('Fallback line'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await AppState.lyrics.setTrack(null);
    AppState.platformProviders.unregister('resolvedsourcetest');
    AppState.currentPlatformTrack = null;
  });

  test('Registering a platform later refreshes the current track', () async {
    final registry = PlatformProviderRegistry();
    final coordinator = LyricsCoordinator(registry);
    final track = _track('QQMusic.exe', '1');
    await coordinator.setTrack(track);
    expect(coordinator.state.status, LyricsStatus.unavailable);
    registry.register(
      _FakeLyricsProvider(
        'qqmusic.exe',
        (_) async => LyricsDocument.parseLrc('[00:00.00]Available'),
      ),
    );
    await coordinator.setTrack(track);
    expect(coordinator.state.currentLine?.text, 'Available');
    coordinator.dispose();
  });

  test('A failed lyric lookup can retry the same track', () async {
    var requests = 0;
    final registry = PlatformProviderRegistry()
      ..register(
        _FakeLyricsProvider('qqmusic.exe', (_) async {
          requests++;
          if (requests == 1) throw const SocketException('offline');
          return LyricsDocument.parseLrc('[00:01.00]Recovered');
        }),
      );
    final coordinator = LyricsCoordinator(registry);
    final track = _track('QQMusic.exe', '1');
    await coordinator.setTrack(track);
    expect(coordinator.state.issue, LyricsIssue.network);
    await coordinator.setTrack(track, force: true);
    expect(coordinator.state.status, LyricsStatus.ready);
    expect(requests, 2);
    coordinator.dispose();
  });

  test(
    'Late lyrics from the previous song cannot replace the new song',
    () async {
      final first = Completer<LyricsDocument?>();
      final second = Completer<LyricsDocument?>();
      final registry = PlatformProviderRegistry()
        ..register(
          _FakeLyricsProvider(
            'qqmusic.exe',
            (track) => track.trackVersion == '1' ? first.future : second.future,
          ),
        );
      final coordinator = LyricsCoordinator(registry);
      final firstLoad = coordinator.setTrack(_track('QQMusic.exe', '1'));
      final secondLoad = coordinator.setTrack(_track('QQMusic.exe', '2'));
      coordinator.setPositionMs(1800);
      second.complete(LyricsDocument.parseLrc('[00:01.00]New song'));
      await secondLoad;
      expect(coordinator.state.status, LyricsStatus.ready);
      expect(coordinator.state.currentLine?.text, 'New song');
      first.complete(LyricsDocument.parseLrc('[00:01.00]Old song'));
      await firstLoad;
      expect(coordinator.state.currentLine?.text, 'New song');
      coordinator.setPositionMs(0);
      expect(coordinator.state.currentLine, isNull);
      coordinator.dispose();
    },
  );
}

PlatformTrack _track(String source, String version) => PlatformTrack(
  sourceAppId: source,
  trackVersion: version,
  title: 'Track',
  artist: 'Artist',
  durationMs: 10000,
);

final class _FakeLyricsProvider implements LyricsPlatformProvider {
  @override
  final String id;
  final Future<LyricsDocument?> Function(PlatformTrack) load;

  _FakeLyricsProvider(this.id, this.load);

  @override
  bool accepts(PlatformTrack track) => track.sourceAppId.toLowerCase() == id;

  @override
  Future<LyricsDocument?> loadLyrics(PlatformTrack track) => load(track);
}
