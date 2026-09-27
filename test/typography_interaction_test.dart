import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_widget_flutter/core/app_state.dart';
import 'package:music_widget_flutter/ui/widgets/settings_panel.dart';

void main() {
  testWidgets('Title and artist weight sliders update the preview live', (
    tester,
  ) async {
    AppState.titleWeightValue = 700;
    AppState.artistWeightValue = 400;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
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
    await tester.tap(find.byKey(const ValueKey('settings_section_typography')));
    await tester.pumpAndSettle();
    final titleSlider = find.byKey(const ValueKey('title_weight_slider'));
    await tester.ensureVisible(titleSlider);
    await tester.drag(titleSlider, const Offset(-35, 0));
    await tester.pump();
    expect(AppState.titleWeightValue, lessThan(700));
    final artistSlider = find.byKey(const ValueKey('artist_weight_slider'));
    await tester.ensureVisible(artistSlider);
    await tester.drag(artistSlider, const Offset(35, 0));
    await tester.pump();
    expect(AppState.artistWeightValue, greaterThan(400));
    final preview = find.byKey(const ValueKey('preview_播放信息实时预览'));
    await tester.ensureVisible(preview);
    expect(
      tester.widget<Text>(preview).style?.fontVariations?.single.value,
      AppState.titleWeightValue,
    );
    expect(tester.takeException(), isNull);
    AppState.titleWeightValue = 700;
    AppState.artistWeightValue = 400;
  });

  testWidgets('Lyrics font controls preview independently at narrow width', (
    tester,
  ) async {
    AppState.showLyrics = true;
    AppState.lyricsUseThemeFont = true;
    AppState.lyricsWeightValue = 500;
    AppState.lyricsFontSize = 14;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
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
    await tester.tap(find.byKey(const ValueKey('settings_section_lyrics')));
    await tester.pumpAndSettle();
    expect(find.text('歌词字体'), findsNothing);
    expect(find.text('跟随主题字体'), findsOneWidget);
    final switchRow = find.ancestor(
      of: find.text('跟随主题字体'),
      matching: find.byType(Row),
    );
    await tester.ensureVisible(switchRow.first);
    await tester.tap(
      find.descendant(of: switchRow.first, matching: find.byType(Switch)),
    );
    await tester.pumpAndSettle();
    expect(find.text('歌词字体'), findsOneWidget);
    final slider = find.byKey(const ValueKey('lyrics_weight_slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(45, 0));
    await tester.pump();
    expect(AppState.lyricsWeightValue, greaterThan(500));
    final preview = find.byKey(const ValueKey('preview_歌词实时预览'));
    await tester.ensureVisible(preview);
    final text = tester.widget<Text>(preview);
    expect(
      text.style?.fontVariations?.single.value,
      AppState.lyricsWeightValue,
    );
    expect(tester.takeException(), isNull);
    AppState.showLyrics = false;
    AppState.lyricsUseThemeFont = true;
    AppState.lyricsWeightValue = 500;
  });
}
