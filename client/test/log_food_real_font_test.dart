import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/nutrition/presentation/log_food_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

/// The real faces, not the test harness's: whether "Breakfast" fits beside
/// "ADDING TO" on a small phone depends on how wide they are drawn. Kept in
/// its own file so the rest of the Log food tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  });

  // Showing the meal is the picker's one job: on a 320 dp phone at large
  // text "Breakfast" was cut to "Brea...". The line wraps instead, and the
  // foods to tap still show without scrolling.
  for (final scale in [1.0, 1.8, 2.0]) {
    testWidgets('"Breakfast" shows whole on a 320 dp phone at ${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
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
            home: const LogFoodScreen(mealType: 'breakfast'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final meal = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(const Key('log.meal')),
          matching: find.text('Breakfast'),
        ),
      );
      expect(
        meal.size.width,
        greaterThanOrEqualTo(meal.getMaxIntrinsicWidth(double.infinity) - 0.01),
        reason: 'the meal was cut short',
      );

      // The first food to tap is on screen, above Add manually.
      expect(
        tester.getRect(find.text('Rice')).bottom,
        lessThan(tester.getRect(find.byKey(const Key('food.manual'))).top),
      );
    });
  }
}
