



import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_widget_flutter/core/app_state.dart';
import 'package:music_widget_flutter/core/spectrum_packet.dart';
import 'package:music_widget_flutter/ui/animations/component_size_motion.dart';
import 'package:music_widget_flutter/ui/widgets/locked_aspect_resize_area.dart';
import 'package:music_widget_flutter/ui/widgets/md3_anchored_select.dart';

void main() {
  testWidgets('MD3 选择菜单围绕当前项展开并返回新选择', (tester) async {
    int selected = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: Md3AnchoredSelect<int>(
              value: selected,
              entries: const [
                DropdownMenuEntry(value: 0, label: '小'),
                DropdownMenuEntry(value: 1, label: '标准'),
                DropdownMenuEntry(value: 2, label: '大'),
              ],
              onSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    final Offset anchorCenter = tester.getCenter(
      find.byType(Md3AnchoredSelect<int>),
    );
    await tester.tap(find.byType(Md3AnchoredSelect<int>));
    await tester.pumpAndSettle();

    expect(find.text('标准'), findsNWidgets(2));
    final Offset selectedItemCenter = tester.getCenter(find.text('标准').last);
    expect(selectedItemCenter.dy, closeTo(anchorCenter.dy, 1.0));

    await tester.tap(find.text('大'));
    await tester.pumpAndSettle();
    expect(selected, 2);
  });

  testWidgets('MD3 选择菜单继承外层组件的真实缩放尺寸', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: Transform.scale(
              scale: 1.22,
              child: Md3AnchoredSelect<int>(
                value: 1,
                entries: const [
                  DropdownMenuEntry(value: 0, label: '小'),
                  DropdownMenuEntry(value: 1, label: '标准'),
                  DropdownMenuEntry(value: 2, label: '大'),
                ],
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final RenderBox anchor = tester.renderObject(
      find.byType(Md3AnchoredSelect<int>),
    );
    final Offset anchorTopLeft = anchor.localToGlobal(Offset.zero);
    final Offset anchorBottomRight = anchor.localToGlobal(
      anchor.size.bottomRight(Offset.zero),
    );
    final Size paintedAnchorSize = Size(
      anchorBottomRight.dx - anchorTopLeft.dx,
      anchorBottomRight.dy - anchorTopLeft.dy,
    );

    await tester.tap(find.byType(Md3AnchoredSelect<int>));
    await tester.pump();

    final Size menuSize = tester.getSize(
      find.byKey(const ValueKey('md3-select-menu-surface')),
    );
    expect(menuSize.width, closeTo(paintedAnchorSize.width, 0.01));

    final ClipPath reveal = tester.widget(
      find.byKey(const ValueKey('md3-select-reveal')),
    );
    final Rect initialRevealBounds = reveal.clipper!
        .getClip(menuSize)
        .getBounds();
    expect(initialRevealBounds.height, closeTo(paintedAnchorSize.height, 0.01));

    await tester.pumpAndSettle();
    await tester.tap(find.text('大'));
    await tester.pumpAndSettle();
  });

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

  test('设置快照恢复普通窗口行为并安全重置鼠标穿透', () async {
    SharedPreferences.setMockInitialValues({
      'settingsSnapshotV2': jsonEncode({
        'themeIsDark': false,
        'themeVariant': 'vibrant',
        'glowMode': 'wallpaper',
        'spectrumMode': 'waveform',
        'progressStyle': 'segmented',
        'widgetLayout': 'vertical',
        'componentSizeMode': 'custom',
        'customComponentScale': 1.31,
        'isAlwaysOnTop': false,
        'isMousePassthrough': true,
        'customFontPaths': <String>[],
      }),
    });

    await AppState.loadSettings();

    expect(AppState.themeBrightness, Brightness.light);
    expect(AppState.themeVariant, DynamicSchemeVariant.vibrant);
    expect(AppState.glowMode, GlowMode.wallpaper);
    expect(AppState.spectrumMode, SpectrumMode.waveform);
    expect(AppState.progressStyle, MD3ProgressStyle.segmented);
    expect(AppState.widgetLayout, WidgetLayout.vertical);
    expect(AppState.componentSizeMode, ComponentSizeMode.custom);
    expect(AppState.customComponentScale, 1.31);
    expect(AppState.isAlwaysOnTop, isFalse);
    expect(AppState.isMousePassthrough, isFalse);
  });

  test('损坏的设置快照会安全回退到旧版设置', () async {
    SharedPreferences.setMockInitialValues({
      'settingsSnapshotV2': '{invalid json',
      'themeIsDark': true,
      'spectrumMode': SpectrumMode.bars.index,
      'widgetLayout': WidgetLayout.horizontal.index,
      'isAlwaysOnTop': true,
      'isMousePassthrough': false,
    });

    await AppState.loadSettings();

    expect(AppState.themeBrightness, Brightness.dark);
    expect(AppState.spectrumMode, SpectrumMode.bars);
    expect(AppState.widgetLayout, WidgetLayout.horizontal);
    expect(AppState.isAlwaysOnTop, isTrue);
    expect(AppState.isMousePassthrough, isFalse);
  });

  test('二进制频谱包会按小端序恢复时间戳和频段', () {
    const int bands = 32;
    final bytes = Uint8List(spectrumPacketHeaderSize + bands * 4);
    final data = ByteData.sublistView(bytes);
    data.setUint8(0, spectrumPacketVersion);
    data.setUint8(1, 1);
    data.setUint16(2, bands, Endian.little);
    data.setInt64(4, 123456789, Endian.little);
    for (int i = 0; i < bands; i++) {
      data.setFloat32(
        spectrumPacketHeaderSize + i * 4,
        i / bands,
        Endian.little,
      );
    }

    final packet = decodeSpectrumPacket(bytes, expectedBandCount: bands);

    expect(packet, isNotNull);
    expect(packet!.available, isTrue);
    expect(packet.updatedAtMs, 123456789);
    expect(packet.levels[16], closeTo(0.5, 0.0001));
  });

  test('二进制频谱包拒绝错误版本和错误长度', () {
    final bytes = Uint8List(spectrumPacketHeaderSize + 32 * 4);
    final data = ByteData.sublistView(bytes);
    data.setUint8(0, 99);
    data.setUint16(2, 32, Endian.little);

    expect(decodeSpectrumPacket(bytes, expectedBandCount: 32), isNull);
    expect(decodeSpectrumPacket(Uint8List(8), expectedBandCount: 32), isNull);
  });

  test('组件固定尺寸档位保持可预期比例', () {
    expect(AppState.scaleForSizeMode(ComponentSizeMode.small), 0.82);
    expect(AppState.scaleForSizeMode(ComponentSizeMode.standard), 1.0);
    expect(AppState.scaleForSizeMode(ComponentSizeMode.large), 1.22);

    AppState.customComponentScale = 1.37;
    expect(AppState.scaleForSizeMode(ComponentSizeMode.custom), 1.37);
  });

  test('组件尺寸使用快速错峰的临界阻尼弹簧', () {
    final simulation = ComponentSizeMotion.frameSimulation(
      begin: 0.82,
      end: 1.22,
    );
    final firstStep = simulation.x(0.04) - simulation.x(0);
    final secondStep = simulation.x(0.08) - simulation.x(0.04);

    expect(ComponentSizeMotion.contentDelay, const Duration(milliseconds: 150));
    expect(ComponentSizeMotion.scaleTolerance.distance, 0.0005);
    expect(ComponentSizeMotion.scaleTolerance.velocity, 0.01);
    expect(firstStep, greaterThan(0));
    expect(secondStep, greaterThan(firstStep));
    expect(simulation.x(0.45), closeTo(1.22, 0.005));
  });

  test('组件尺寸弹簧可从中间状态继承速度并连续重定向', () {
    final outgoing = ComponentSizeMotion.frameSimulation(begin: 1.0, end: 1.22);
    final currentScale = outgoing.x(0.1);
    final currentVelocity = outgoing.dx(0.1);
    final redirected = ComponentSizeMotion.frameSimulation(
      begin: currentScale,
      end: 0.82,
      velocity: currentVelocity,
    );

    expect(redirected.x(0), closeTo(currentScale, 0.000001));
    expect(redirected.dx(0), closeTo(currentVelocity, 0.000001));
    expect(redirected.x(0.6), closeTo(0.82, 0.005));
  });

  testWidgets('component size stage preserves its design canvas when shrunk', (
    tester,
  ) async {
    const stageKey = ValueKey('component-stage');
    const designKey = ValueKey('design-canvas');
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ComponentSizeStage(
            key: stageKey,
            frameWidth: 240,
            frameHeight: 90,
            designWidth: 480,
            designHeight: 180,
            frameScale: 0.5,
            contentScale: 0.5,
            alignment: Alignment.topLeft,
            decoration: const BoxDecoration(),
            frameAnimationDuration: Duration.zero,
            frameAnimationCurve: Curves.linear,
            child: const SizedBox(key: designKey),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(designKey)), const Size(480, 180));
    expect(
      tester.getRect(find.byKey(designKey)),
      tester.getRect(find.byKey(stageKey)),
    );
  });

  test('viewport safety fit never forces an oversized minimum scale', () {
    final scale = ComponentSizeMotion.fitScale(
      viewport: const Size(480, 176),
      design: const Size(340, 584),
      maximumScale: AppState.maximumComponentScale,
    );

    expect(scale, closeTo(176 / 584, 0.000001));
    expect(scale, lessThan(AppState.minimumComponentScale));
  });

  test('locked resize preserves aspect ratio from the bottom-right corner', () {
    final target = LockedAspectResizeGeometry.targetBounds(
      startBounds: const Rect.fromLTWH(100, 100, 480, 240),
      designSize: const Size(480, 240),
      edge: LockedResizeEdge.bottomRight,
      dragDelta: const Offset(120, 60),
      minimumScale: 0.72,
      maximumScale: 1.5,
    );

    expect(target, const Rect.fromLTWH(100, 100, 600, 300));
    expect(target.width / target.height, 2.0);
  });

  test('locked resize anchors the opposite edge and clamps its scale', () {
    final target = LockedAspectResizeGeometry.targetBounds(
      startBounds: const Rect.fromLTWH(100, 100, 480, 240),
      designSize: const Size(480, 240),
      edge: LockedResizeEdge.left,
      dragDelta: const Offset(300, 0),
      minimumScale: 0.72,
      maximumScale: 1.5,
    );

    expect(target.right, closeTo(580, 0.000001));
    expect(target.width, closeTo(480 * 0.72, 0.000001));
    expect(target.height, closeTo(240 * 0.72, 0.000001));
  });
}
