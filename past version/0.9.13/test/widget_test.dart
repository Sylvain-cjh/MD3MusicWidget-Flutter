



import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_widget_flutter/core/app_state.dart';

void main() {
  test('getShapeRadius 为每种形状返回正确的圆角', () {
    const double h = 58;

    expect(
      AppState.getShapeRadius(MD3Shape.circle, h),
      BorderRadius.circular(h / 2),
    );
    expect(
      AppState.getShapeRadius(MD3Shape.stadium, h),
      BorderRadius.circular(999),
    );
    expect(
      AppState.getShapeRadius(MD3Shape.roundedMedium, h),
      BorderRadius.circular(12),
    );
    expect(
      AppState.getShapeRadius(MD3Shape.roundedLarge, h),
      BorderRadius.circular(20),
    );
  });

  test('布局度量：横版为进度条保留额外呼吸空间', () {
    const l = WidgetLayout.horizontal;
    expect(AppState.playerWidthOf(l), 480);
    expect(AppState.corePlayerHeightOf(l), 176);
    expect(AppState.playerAreaHeightOf(l), 176);
    expect(AppState.baseWindowHeightOf(l), 176);
    expect(AppState.expandedWindowHeightOf(l), 636);
    expect(AppState.glowHeaderHeightOf(l), 176);
    expect(AppState.revealCenterOf(l), const Offset(80, 80));
  });

  test('频谱开启时只增加独立底部控件高度', () {
    final oldMode = AppState.spectrumMode;
    AppState.spectrumMode = SpectrumMode.bars;
    expect(
      AppState.playerAreaHeightOf(WidgetLayout.horizontal),
      AppState.corePlayerHeightOf(WidgetLayout.horizontal) + 64,
    );
    expect(
      AppState.playerAreaHeightOf(WidgetLayout.vertical),
      AppState.corePlayerHeightOf(WidgetLayout.vertical) + 64,
    );
    AppState.spectrumMode = oldMode;
  });

  test('布局度量：竖版尺寸自洽（设置为侧板：高度不变、宽度加宽）', () {
    const l = WidgetLayout.vertical;
    expect(
      AppState.baseWindowHeightOf(l),
      AppState.playerAreaHeightOf(l) + AppState.cardMargin * 2,
    );
    
    expect(AppState.expandedWindowHeightOf(l), AppState.baseWindowHeightOf(l));
    expect(
      AppState.settingsWindowWidthOf(l),
      AppState.playerWidthOf(l) + AppState.settingsSideWidth,
    );
    
    const h = WidgetLayout.horizontal;
    expect(AppState.settingsWindowWidthOf(h), AppState.playerWidthOf(h));
    expect(
      AppState.expandedWindowHeightOf(h),
      AppState.baseWindowHeightOf(h) + AppState.settingsPanelHeight,
    );
    
    expect(
      AppState.glowHeaderHeightOf(l),
      lessThanOrEqualTo(AppState.playerAreaHeightOf(l)),
    );
  });

  test('背景画布为所有布局形态的并集（静态画布是反闪烁的关键）', () {
    for (final l in WidgetLayout.values) {
      expect(
        AppState.canvasWidth,
        greaterThanOrEqualTo(AppState.playerWidthOf(l)),
      );
      expect(
        AppState.canvasHeight,
        greaterThanOrEqualTo(AppState.expandedWindowHeightOf(l)),
      );
      expect(
        AppState.canvasHeight,
        greaterThanOrEqualTo(AppState.baseWindowHeightOf(l)),
      );
    }
  });

  test('playback timeline clamps invalid values and stays within duration', () {
    AppState.updatePlaybackTimeline(
      positionMs: double.nan,
      durationMs: double.infinity,
      updatedAtMs: 0,
    );

    expect(AppState.playbackPositionMs, 0);
    expect(AppState.playbackDurationMs, 0);
    expect(AppState.playbackUpdatedAtMs, greaterThan(0));

    AppState.updatePlaybackTimeline(
      positionMs: 999999,
      durationMs: 1000,
      updatedAtMs: 123,
    );

    expect(AppState.playbackPositionMs, 1000);
    expect(AppState.playbackDurationMs, 1000);
    expect(AppState.playbackUpdatedAtMs, 123);
  });

  test('track transition notifications increase monotonically', () {
    final before = AppState.trackTransitionRevision.value;
    AppState.notifyTrackTransition();
    expect(AppState.trackTransitionRevision.value, before + 1);
  });
}
