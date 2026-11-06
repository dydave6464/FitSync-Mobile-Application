import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/onboarding/presentation/steps/level_step.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

/// The location picker's height depends on how tall its rows set, and only
/// the real face measures like a phone. Kept in its own file so the rest of
/// the level step's tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

Future<void> _openPicker(
  WidgetTester tester, {
  required Size size,
  required double textScale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  // A gesture bar, as on a phone with no home button.
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        equipmentOptionsProvider.overrideWith(
          (ref) => Future.value(const <EquipmentOption>[]),
        ),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LevelStep(value: const LevelAnswers(), onChanged: (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('trainingLocation')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('trainingLocation')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
  });

  // R-1: with the theme's drag handle the picker grew 48 dp, and a sheet
  // that is not scroll-controlled stops at 9/16 of the screen. At 2x text on
  // a 640 dp phone the last place overflowed under the gesture bar.
  for (final size in [const Size(360, 640), const Size(320, 568)]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('at ${scale}x on ${size.width.toInt()}x'
          '${size.height.toInt()} the picker fits and every place can be '
          'reached above the gesture bar', (tester) async {
        await _openPicker(tester, size: size, textScale: scale);

        expect(tester.takeException(), isNull);
        final last = find.byKey(const Key('location.other'));
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(last).bottom,
          lessThanOrEqualTo(size.height - 24),
        );
        // And it can still be picked.
        await tester.tap(last);
        await tester.pumpAndSettle();
        expect(last, findsNothing);
      });
    }
  }
}
