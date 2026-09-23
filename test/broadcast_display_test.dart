import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_widget_flutter/core/app_state.dart';
import 'package:music_widget_flutter/core/music_fetcher_frame_decoder.dart';
import 'package:music_widget_flutter/core/music_fetcher_protocol.dart';
import 'package:music_widget_flutter/ui/widgets/track_controls.dart';
import 'package:music_widget_flutter/ui/widgets/settings_panel.dart';

void main() {
  testWidgets('Settings navigation shows only the selected section at 360px', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 460,
            child: SettingsPanel(
              onThemeChanged: () {},
              onVisualChanged: () {},
              onBackgroundChanged: () {},
              onLayoutChanged: () {},
              onWindowBehaviorChanged: () {},
              isMousePassthroughAvailable: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('布局形态'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_section_lyrics')));
    await tester.pumpAndSettle();
    expect(find.text('布局形态'), findsNothing);
    expect(find.text('显示歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final section in ['appearance', 'playback', 'typography', 'window']) {
      await tester.tap(find.byKey(ValueKey('settings_section_$section')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  test(
    'Lyrics provider, visibility and local folder survive settings reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AppState.loadSettings();
      expect(AppState.showLyrics, isFalse);
      AppState.showLyrics = true;
      AppState.lyricsProviderChoice = LyricsProviderChoice.localLrc;
      AppState.localLyricsDirectory = r'D:\Lyrics';
      await AppState.saveSettings();
      await AppState.flushSettings();
      AppState.showLyrics = false;
      AppState.lyricsProviderChoice = LyricsProviderChoice.lrclib;
      AppState.localLyricsDirectory = '';
      await AppState.loadSettings();
      expect(AppState.showLyrics, isTrue);
      expect(AppState.lyricsProviderChoice, LyricsProviderChoice.localLrc);
      expect(AppState.localLyricsDirectory, r'D:\Lyrics');
      AppState.showLyrics = false;
      AppState.lyricsProviderChoice = LyricsProviderChoice.lrclib;
      AppState.localLyricsDirectory = '';
    },
  );

  testWidgets(
    'Lyrics toggle reserves its own panel and reveals provider choice',
    (tester) async {
      AppState.showLyrics = false;
      AppState.spectrumMode = SpectrumMode.bars;
      final before = AppState.innerPlayerHeightOf(WidgetLayout.horizontal);
      int relayouts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 460,
              child: SettingsPanel(
                onThemeChanged: () {},
                onVisualChanged: () {},
                onBackgroundChanged: () {},
                onLayoutChanged: () => relayouts++,
                onWindowBehaviorChanged: () {},
                isMousePassthroughAvailable: false,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('settings_section_lyrics')));
      await tester.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('显示歌词'),
        matching: find.byType(Row),
      );
      final toggle = find.descendant(
        of: row.first,
        matching: find.byType(Switch),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(AppState.showLyrics, isTrue);
      expect(
        AppState.innerPlayerHeightOf(WidgetLayout.horizontal),
        before + 64,
      );
      expect(relayouts, 1);
      expect(find.text('歌词提供商'), findsOneWidget);
      AppState.showLyrics = false;
      AppState.spectrumMode = SpectrumMode.off;
    },
  );

  testWidgets(
    'Settings switch hides transport shape options and requests relayout',
    (tester) async {
      AppState.showPlaybackControls = true;
      AppState.widgetLayout = WidgetLayout.horizontal;
      int relayouts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 480,
              height: 460,
              child: SettingsPanel(
                onThemeChanged: () {},
                onVisualChanged: () {},
                onBackgroundChanged: () {},
                onLayoutChanged: () => relayouts++,
                onWindowBehaviorChanged: () {},
                isMousePassthroughAvailable: false,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('settings_section_playback')));
      await tester.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('显示播放控制'),
        matching: find.byType(Row),
      );
      final toggle = find.descendant(
        of: row.first,
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(AppState.showPlaybackControls, isFalse);
      expect(relayouts, 1);
      expect(find.text('上一首按钮'), findsNothing);
      expect(find.text('下一首按钮'), findsNothing);
      expect(find.text('进度条样式'), findsOneWidget);
      AppState.showPlaybackControls = true;
    },
  );

  test(
    'Large fragmented artwork and following heartbeat preserve exact payloads',
    () {
      final frames = <(int, Uint8List)>[];
      final decoder = MusicFetcherFrameDecoder(
        (type, bytes) => frames.add((type, bytes)),
      );
      final artwork = Uint8List.fromList(
        List.generate(256 * 1024, (i) => i % 251),
      );
      final wire = BytesBuilder()
        ..add(
          MusicFetcherProtocol.encodeFrame(
            MusicFetcherProtocol.artworkType,
            artwork,
          ),
        )
        ..add(
          MusicFetcherProtocol.encodeFrame(
            MusicFetcherProtocol.heartbeatType,
            Uint8List(0),
          ),
        );
      final bytes = wire.takeBytes();
      for (int offset = 0; offset < bytes.length; offset += 7) {
        decoder.add(
          Uint8List.sublistView(
            bytes,
            offset,
            (offset + 7).clamp(0, bytes.length),
          ),
        );
      }
      expect(frames.length, 2);
      expect(frames.first.$2, artwork);
      expect(frames.last.$1, MusicFetcherProtocol.heartbeatType);
      expect(frames.last.$2, isEmpty);
    },
  );

  test(
    'Oversized frame is rejected before allocation and decoder can reset',
    () {
      int count = 0;
      final decoder = MusicFetcherFrameDecoder((_, _) => count++);
      final bytes = MusicFetcherProtocol.encodeFrame(1, Uint8List(0));
      ByteData.sublistView(bytes).setUint32(8, 0xffffffff, Endian.little);
      expect(() => decoder.add(bytes), throwsFormatException);
      decoder.reset();
      decoder.add(MusicFetcherProtocol.encodeFrame(3, Uint8List(0)));
      expect(count, 1);
    },
  );

  test(
    'Broadcast display choice survives settings reload and shrinks both layouts',
    () async {
      SharedPreferences.setMockInitialValues({});
      await AppState.loadSettings();
      final heights = [
        for (final layout in WidgetLayout.values)
          AppState.corePlayerHeightOf(layout),
      ];
      AppState.showPlaybackControls = false;
      await AppState.saveSettings();
      await AppState.flushSettings();
      AppState.showPlaybackControls = true;
      await AppState.loadSettings();
      expect(AppState.showPlaybackControls, isFalse);
      for (int i = 0; i < WidgetLayout.values.length; i++) {
        expect(
          AppState.corePlayerHeightOf(WidgetLayout.values[i]),
          lessThan(heights[i]),
        );
      }
      AppState.showPlaybackControls = true;
    },
  );

  for (final layout in WidgetLayout.values) {
    testWidgets(
      'Broadcast $layout hides only transport buttons and keeps track information',
      (tester) async {
        AppState.showPlaybackControls = true;
        AppState.isPlaying = false;
        AppState.coverProvider = null;
        AppState.trackTitle = 'Broadcast song';
        AppState.artistName = 'Artist';
        AppState.playbackDurationMs = 120000;
        Future<void> render() => tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: AppState.innerPlayerWidthOf(layout),
                height: AppState.corePlayerHeightOf(layout),
                child: ContinuousTrackControls(
                  isVertical: layout == WidgetLayout.vertical,
                ),
              ),
            ),
          ),
        );
        await render();
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        AppState.showPlaybackControls = false;
        await render();
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.skip_previous_rounded), findsNothing);
        expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
        expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
        expect(find.text('Broadcast song'), findsOneWidget);
        expect(find.text('Artist'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        AppState.showPlaybackControls = true;
      },
    );
  }
}
