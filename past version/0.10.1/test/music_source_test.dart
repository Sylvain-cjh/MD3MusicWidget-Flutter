import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_widget_flutter/core/app_state.dart';
import 'package:music_widget_flutter/core/music_source_service.dart';

void main() {
  test('source list keeps playing state and recognizes common players', () {
    final snapshot = MusicSourceSnapshot.fromJson({
      'selectedSourceAppId': 'QQMusic.exe',
      'sources': [
        {'sourceAppId': 'QQMusic.exe', 'isPlaying': true},
        {'sourceAppId': 'other.exe', 'isPlaying': false},
        {'sourceAppId': '', 'isPlaying': true},
      ],
    });
    expect(snapshot.selectedSourceAppId, 'QQMusic.exe');
    expect(snapshot.sources, hasLength(2));
    expect(snapshot.sources.first.isPlaying, isTrue);
    expect(snapshot.sources.first.label, contains('QQ 音乐'));
    expect(snapshot.sources.last.label, 'other.exe');
  });

  test('manual source choice survives settings reload', () async {
    SharedPreferences.setMockInitialValues({});
    await AppState.loadSettings();
    AppState.selectedSourceAppId = 'QQMusic.exe';
    await AppState.saveSettings();
    await AppState.flushSettings();
    AppState.selectedSourceAppId = '';
    await AppState.loadSettings();
    expect(AppState.selectedSourceAppId, 'QQMusic.exe');
    AppState.selectedSourceAppId = '';
  });
}
