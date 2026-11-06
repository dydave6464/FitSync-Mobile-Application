import 'dart:io';
import 'dart:typed_data' show ByteData;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/nutrition/presentation/log_food_screen.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/snap_meal.dart';
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

Future<void> _pumpLogFood(
  WidgetTester tester, {
  required double width,
  required double scale,
  String meal = 'breakfast',
}) async {
  tester.view.physicalSize = Size(width, 640);
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
        // The fake server's today, so the screen is logging to today and
        // "ADDING TO" names no other day.
        nutritionClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 14, 4),
        ),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: LogFoodScreen(mealType: meal),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// [text] inside [key] is drawn whole: no ellipsis, no word broken.
void _expectWhole(WidgetTester tester, Key key, String text) {
  final p = tester.renderObject<RenderParagraph>(
    find.descendant(of: find.byKey(key), matching: find.text(text)),
  );
  expect(p.didExceedMaxLines, isFalse, reason: '"$text" was cut short');
  expect(
    p.size.width,
    greaterThanOrEqualTo(p.getMinIntrinsicWidth(double.infinity) - 0.01),
    reason: 'a word of "$text" was broken',
  );
}

bool _labelled(WidgetTester tester) =>
    !tester.widget<SnapMealButton>(find.byKey(const Key('food.snap'))).compact;

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
            // Logging to the fake server's today: "ADDING TO" alone.
            nutritionClockProvider.overrideWithValue(
              () => DateTime.utc(2026, 10, 14, 4),
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

      // Add manually stays whole: in the camera-button row it may wrap.
      _expectWhole(tester, const Key('food.manual'), 'Add manually');

      // The first food to tap is on screen, above Add manually.
      expect(
        tester.getRect(find.text('Rice')).bottom,
        lessThan(tester.getRect(find.byKey(const Key('food.manual'))).top),
      );
    });
  }

  // The labelled pill only when it measures whole beside Add manually: a
  // fixed width rule cut "Snap a meal" short on 380-393 dp phones at 1.1x.
  testWidgets('a 390 dp phone at 1x shows the labelled "Snap a meal" whole', (
    tester,
  ) async {
    await _pumpLogFood(tester, width: 390, scale: 1);
    expect(_labelled(tester), isTrue);
    _expectWhole(tester, const Key('food.snap'), 'Snap a meal');
    _expectWhole(tester, const Key('food.manual'), 'Add manually');
  });

  for (final width in [380.0, 390.0, 393.0]) {
    for (final scale in [1.0, 1.1, 1.3]) {
      testWidgets('no label in the bar is cut at $width dp, ${scale}x', (
        tester,
      ) async {
        await _pumpLogFood(tester, width: width, scale: scale);
        if (_labelled(tester)) {
          _expectWhole(tester, const Key('food.snap'), 'Snap a meal');
        }
        _expectWhole(tester, const Key('food.manual'), 'Add manually');
      });
    }
  }
}
