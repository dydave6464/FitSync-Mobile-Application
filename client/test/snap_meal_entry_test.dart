import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/nutrition/data/meal_photo_picker.dart';
import 'package:fitsync/features/nutrition/data/meal_photo_repository.dart';
import 'package:fitsync/features/nutrition/domain/meal_photo.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/log_food_screen.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/providers.dart';
import 'package:fitsync/features/nutrition/presentation/nutrition_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

class _Profile extends ProfileNotifier {
  _Profile({required this.premium});

  final bool premium;

  @override
  Future<Profile> build() async => Profile(
    userId: 7, email: 'juan@example.com', fullName: 'Juan Dela Cruz', onboardingCompleted: true,
    isPremium: premium, notificationsEnabled: true, equipment: const [], injuries: const [],
  );
}

class _Picker implements MealPhotoPicker {
  final sources = <PhotoSource>[];
  final List<Object?> answers;

  _Picker(this.answers);

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    sources.add(source);
    final a = answers.removeAt(0);
    if (a is Exception) throw a;
    return a as PickedPhoto?;
  }
}

class _Repo implements MealPhotoRepository {
  int logged = 0;

  @override
  Future<PhotoRecognition> recognize(Uint8List bytes, String mimeType) async => PhotoRecognition.fromJson({
    'recognitionId': 7, 'remainingToday': 12, 'unlisted': [],
    'items': [{'itemId': 40, 'confidence': 0.9, 'servings': 1, 'alternatives': [], 'food': {
      'id': 1, 'name': 'White rice', 'servingDesc': '1 cup (160 g)', 'fromFatsecret': false,
      'perServing': {'kcal': 206, 'proteinG': 3.4, 'carbsG': 47.5, 'fatG': 0.3, 'fiberG': null, 'sugarG': null, 'sodiumMg': null},
    }}],
  });

  @override
  Future<int> log({required int recognitionId, required String date, required String mealType, required List<PhotoLogItem> items}) async {
    logged += items.length;
    return items.length;
  }
}

final _jpeg = PickedPhoto(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');

NutritionDay _emptyDay(String date) => NutritionDay(
  date: date, target: null, targetMissing: const [],
  totals: const MacroTotals(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 0, sodiumMg: 0),
  meals: {for (final m in mealTypes) m: const []},
);

Future<({_Repo repo, _Picker picker, int Function() settingsOpened})> _pump(
  WidgetTester tester, {
  required Widget home,
  bool premium = true,
  List<Object?>? picks,
  Size size = const Size(400, 1000),
  double scale = 1,
  bool dark = false,
}) async {
  final repo = _Repo();
  final picker = _Picker(picks ?? [_jpeg]);
  var settings = 0;
  final nutrition = FakeNutritionRepository()..days['2026-10-14'] = _emptyDay('2026-10-14');
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => _Profile(premium: premium)),
      mealPhotoRepositoryProvider.overrideWithValue(repo),
      mealPhotoPickerProvider.overrideWithValue(picker),
      appSettingsOpenerProvider.overrideWithValue(() async => settings++),
      nutritionRepositoryProvider.overrideWithValue(nutrition),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)), // 12:00 Manila: lunch
    ],
    child: MaterialApp(
      theme: dark ? fsDarkTheme() : fsLightTheme(),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: home,
    ),
  ));
  await tester.pumpAndSettle();
  return (repo: repo, picker: picker, settingsOpened: () => settings);
}

void main() {
  testWidgets('Nutrition shows the Snap a meal card, as the prototype does', (tester) async {
    await _pump(tester, home: const NutritionScreen());
    expect(find.byKey(const Key('snap.card')), findsOneWidget);
    expect(find.text('Snap a meal'), findsOneWidget);
    expect(find.text('AI suggests the food — you confirm & log.'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('snap.card')), matching: find.text('Pro')), findsOneWidget);
  });

  testWidgets('a free account goes to the Pro screen, and the camera never opens', (tester) async {
    final h = await _pump(tester, home: const NutritionScreen(), premium: false);
    await tester.tap(find.byKey(const Key('snap.card')));
    await tester.pumpAndSettle();
    expect(find.text('FitSync Pro'), findsOneWidget);
    expect(find.text('Take a photo'), findsNothing);
    expect(h.picker.sources, isEmpty);
  });

  testWidgets('Pro: choose, confirm, log -- back on Nutrition with the message', (tester) async {
    final h = await _pump(tester, home: const NutritionScreen());
    await tester.tap(find.byKey(const Key('snap.card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snap.library')));
    await tester.pumpAndSettle();
    expect(h.picker.sources, [PhotoSource.library]);
    expect(find.text('White rice'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const Key('snap.meal.lunch'))), isSemantics(isSelected: true));
    await tester.tap(find.byKey(const Key('snap.log')));
    await tester.pumpAndSettle();
    expect(h.repo.logged, 1);
    expect(find.text('Logged 1 item to lunch'), findsOneWidget);
    expect(find.byKey(const Key('snap.card')), findsOneWidget, reason: 'back on Nutrition');
  });

  testWidgets('camera refused: the dialog, then the library', (tester) async {
    final h = await _pump(tester, home: const NutritionScreen(), picks: [const CameraAccessDenied(), _jpeg]);
    await tester.tap(find.byKey(const Key('snap.card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snap.camera')));
    await tester.pumpAndSettle();
    expect(find.text('Camera is off for FitSync'), findsOneWidget);
    await tester.tap(find.byKey(const Key('snap.denied.library')));
    await tester.pumpAndSettle();
    expect(h.picker.sources, [PhotoSource.camera, PhotoSource.library]);
    expect(find.text('White rice'), findsOneWidget);
  });

  testWidgets('camera refused: Open Settings opens FitSync\'s settings and stops there', (tester) async {
    final h = await _pump(tester, home: const NutritionScreen(), picks: [const CameraAccessDenied()]);
    await tester.tap(find.byKey(const Key('snap.card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snap.camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snap.denied.settings')));
    await tester.pumpAndSettle();
    expect(h.settingsOpened(), 1);
    expect(find.text('White rice'), findsNothing);
  });

  testWidgets('a photo that is not a JPEG or PNG says so', (tester) async {
    await _pump(tester, home: const NutritionScreen(), picks: [const UnsupportedPhoto()]);
    await tester.tap(find.byKey(const Key('snap.card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snap.library')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't read this photo. Try another one."), findsOneWidget);
  });

  testWidgets('Log food has Snap a meal beside Add manually; a logged photo closes Log food too', (tester) async {
    final h = await _pump(tester, home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LogFoodScreen(mealType: 'dinner'))),
      child: const Text('go'),
    ))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('food.snap')), findsOneWidget);
    expect(find.byKey(const Key('food.manual')), findsOneWidget);
    await tester.tap(find.byKey(const Key('food.snap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snap.camera')));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.byKey(const Key('snap.meal.dinner'))), isSemantics(isSelected: true));
    await tester.tap(find.byKey(const Key('snap.log')));
    await tester.pumpAndSettle();
    expect(h.repo.logged, 1);
    expect(find.text('Log food'), findsNothing);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('choosing a food for a photo offers no second Snap a meal', (tester) async {
    await _pump(tester, home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => pickFood(context, mealType: 'lunch'),
      child: const Text('go'),
    ))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('food.snap')), findsNothing);
    expect(find.byKey(const Key('food.manual')), findsOneWidget);
  });

  for (final (width, scale, labelled) in [(420.0, 1.0, true), (320.0, 1.0, false), (420.0, 2.0, false)]) {
    testWidgets('Log food\'s bar at ${width.toInt()} dp, ${scale}x: one row, ${labelled ? 'labelled' : 'a camera button'}', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, home: const LogFoodScreen(mealType: 'lunch'), size: Size(width, 800), scale: scale);
      expect(tester.takeException(), isNull);
      final snap = tester.getRect(find.byKey(const Key('food.snap')));
      final manual = tester.getRect(find.byKey(const Key('food.manual')));
      expect(snap.top, manual.top, reason: 'one row, never stacked');
      expect(snap.height, greaterThanOrEqualTo(48));
      expect(snap.width >= 48, isTrue);
      expect(find.descendant(of: find.byKey(const Key('food.snap')), matching: find.text('Snap a meal')), labelled ? findsOneWidget : findsNothing);
      expect(find.bySemanticsLabel('Snap a meal, Pro'), findsOneWidget);
      handle.dispose();
    });
  }

  testWidgets('the card and the photo screen build in the dark theme too', (tester) async {
    await _pump(tester, home: const NutritionScreen(), dark: true);
    await tester.tap(find.byKey(const Key('snap.card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snap.library')));
    await tester.pumpAndSettle();
    expect(find.text('White rice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the Snap a meal card fits a 320 dp phone at ${scale}x', (tester) async {
      await _pump(tester, home: const NutritionScreen(), size: const Size(320, 900), scale: scale);
      expect(tester.takeException(), isNull);
    });
  }
}
