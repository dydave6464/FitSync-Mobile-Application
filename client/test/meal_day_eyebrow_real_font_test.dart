import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/nutrition/data/meal_photo_picker.dart';
import 'package:fitsync/features/nutrition/data/meal_photo_repository.dart';
import 'package:fitsync/features/nutrition/domain/meal_photo.dart';
import 'package:fitsync/features/nutrition/presentation/add_food_manually_screen.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/meal_photo_screen.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/providers.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

/// The real faces, not the test harness's square one: whether "MEAL · WED,
/// OCT 14" fits its lines depends on how wide the app really draws it.
/// Kept in its own file so the other tests keep the harness font.
Future<void> _load(String family, String path) async {
  final bytes = await File(path).readAsBytes();
  await (FontLoader(
    family,
  )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
}

class _PhotoRepo implements MealPhotoRepository {
  @override
  Future<PhotoToday> today() => throw UnimplementedError();

  @override
  Future<PhotoRecognition> recognize(
    Uint8List bytes,
    String mimeType, {
    Future<void>? cancel,
  }) async => PhotoRecognition.fromJson({
    'recognitionId': 7,
    'remainingToday': 12,
    'items': [
      {
        'itemId': 40,
        'confidence': 0.9,
        'servings': 1,
        'food': {
          'id': 1,
          'name': 'White rice',
          'servingDesc': '1 cup (160 g)',
          'fromFatsecret': false,
          'perServing': {
            'kcal': 206,
            'proteinG': 4,
            'carbsG': 40,
            'fatG': 1,
            'fiberG': null,
            'sugarG': null,
            'sodiumMg': null,
          },
        },
        'alternatives': [],
      },
    ],
    'unlisted': [],
  });

  @override
  Future<int> log({
    required int recognitionId,
    required String date,
    required String mealType,
    required List<PhotoLogItem> items,
  }) async => items.length;
}

/// The eyebrow [text] is drawn whole: within its lines, no word broken.
void _expectWhole(WidgetTester tester, String text) {
  final p = tester.renderObject<RenderParagraph>(find.text(text));
  expect(p.didExceedMaxLines, isFalse, reason: '"$text" was cut short');
  expect(
    p.size.width,
    greaterThanOrEqualTo(p.getMinIntrinsicWidth(double.infinity) - 0.01),
    reason: 'a word of "$text" was broken',
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required double scale,
  required DateTime clock,
  required Widget home,
}) async {
  tester.view.physicalSize = const Size(320, 1400);
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
        mealPhotoRepositoryProvider.overrideWithValue(_PhotoRepo()),
        nutritionClockProvider.overrideWithValue(() => clock),
      ],
      child: MaterialApp(theme: fsLightTheme(), home: home),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    await _load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk-Variable.ttf');
    await _load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Variable.ttf');
  });

  // P-8: logging to a past day names it above the meal chips (NU-7), on
  // Add manually and on Snap a meal's confirm list. The fake server's day
  // is Wed, Oct 14, 2026; the clock makes it an older day this year or one
  // in the year before, the longest the label gets.
  final clocks = {
    'an older day': (DateTime.utc(2026, 10, 16, 4), 'MEAL · WED, OCT 14'),
    'a day last year': (
      DateTime.utc(2027, 1, 2, 4),
      'MEAL · WED, OCT 14, 2026',
    ),
  };
  for (final MapEntry(key: day, value: (clock, eyebrow)) in clocks.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Add manually names $day whole on a 320 dp phone at '
          '${scale}x', (tester) async {
        await _pump(
          tester,
          scale: scale,
          clock: clock,
          home: const AddFoodManuallyScreen(mealType: 'lunch'),
        );
        _expectWhole(tester, eyebrow);
      });

      testWidgets('the photo confirm names $day whole on a 320 dp phone at '
          '${scale}x', (tester) async {
        await _pump(
          tester,
          scale: scale,
          clock: clock,
          home: MealPhotoScreen(
            photo: PickedPhoto(
              Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
              'image/jpeg',
            ),
            source: PhotoSource.camera,
            mealType: 'lunch',
            date: '2026-10-14',
            onSearchInstead: (_, _) {},
          ),
        );
        _expectWhole(tester, eyebrow);
      });
    }
  }
}
