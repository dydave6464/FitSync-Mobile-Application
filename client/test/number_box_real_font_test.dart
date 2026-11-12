import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/nutrition/presentation/add_food_manually_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

/// The real face, not the test harness's square one: whether a box's name
/// fits its two lines depends on how wide the app really draws it.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
  });

  // L-66: two boxes share a row, so at large text a box's dim label takes
  // its second line rather than being cut.
  testWidgets('no number box name is cut on a 320 dp phone at 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nutritionRepositoryProvider.overrideWithValue(
            FakeNutritionRepository(),
          ),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          home: const AddFoodManuallyScreen(mealType: 'snack'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Protein (g)',
      'Carbs (g)',
      'Fat (g)',
      'Fiber (g)',
      'Sugar (g)',
      'Sodium (mg)',
    ]) {
      final p = tester.renderObject<RenderParagraph>(find.text(label));
      expect(p.didExceedMaxLines, isFalse, reason: '$label is cut');
      expect(
        p.size.width,
        greaterThanOrEqualTo(p.getMinIntrinsicWidth(double.infinity) - 0.01),
        reason: 'a word of $label was broken',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
