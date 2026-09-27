import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_widget_flutter/ui/widgets/cover_parallax.dart';

void main() {
  Widget cover({bool reducedMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: Center(
          child: CoverParallax(
            size: 120,
            borderRadius: BorderRadius.circular(18),
            backgroundColor: Colors.blueGrey,
            accentColor: Colors.teal,
            image: null,
            isPlaying: true,
            enable3D: true,
          ),
        ),
      ),
    ),
  );

  testWidgets('Cover tilt follows pointer, reverses, then settles idle', (
    tester,
  ) async {
    await tester.pumpWidget(cover());
    final target = find.byKey(const ValueKey('cover_parallax_transform'));
    final center = tester.getCenter(find.byType(CoverParallax));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse.moveTo(center + const Offset(40, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final rightTilt = tester.widget<Transform>(target).transform.storage[8];
    expect(rightTilt.abs(), greaterThan(0.01));

    await mouse.moveTo(center - const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 240));
    final leftTilt = tester.widget<Transform>(target).transform.storage[8];
    expect(leftTilt * rightTilt, lessThan(0));

    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();
    final rest = tester.widget<Transform>(target).transform.storage;
    expect(rest[8].abs(), lessThan(0.001));
    expect(rest[0], closeTo(1, 0.001));
    await mouse.removePointer();
  });

  testWidgets('Reduced motion keeps cover stable during hover', (tester) async {
    await tester.pumpWidget(cover(reducedMotion: true));
    final center = tester.getCenter(find.byType(CoverParallax));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse.moveTo(center + const Offset(40, 0));
    await tester.pump();
    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('cover_parallax_transform')),
    );
    expect(transform.transform.storage[8], 0);
    expect(transform.transform.storage[0], 1);
    await mouse.removePointer();
  });
}
