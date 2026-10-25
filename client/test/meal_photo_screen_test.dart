import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/nutrition/data/meal_photo_picker.dart';
import 'package:fitsync/features/nutrition/data/meal_photo_repository.dart';
import 'package:fitsync/features/nutrition/domain/meal_photo.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/meal_photo_screen.dart';
import 'package:fitsync/features/nutrition/presentation/meal_photo/providers.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

final _bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);
final _photo = PickedPhoto(_bytes, 'image/jpeg');

Map<String, dynamic> _food(int id, String name, num kcal, {String serving = '1 cup (160 g)', bool fs = false}) => {
  'id': id, 'name': name, 'servingDesc': serving, 'fromFatsecret': fs,
  'perServing': {'kcal': kcal, 'proteinG': 4, 'carbsG': 40, 'fatG': 1, 'fiberG': null, 'sugarG': null, 'sodiumMg': null},
};

/// Rice 1.5 servings (309 kcal; or garlic rice), adobo 1 serving (320 kcal), and atchara not on the list.
final _answer = PhotoRecognition.fromJson({
  'recognitionId': 7, 'remainingToday': 12,
  'items': [
    {'itemId': 40, 'confidence': 0.9, 'servings': 1.5, 'food': _food(1, 'White rice', 206),
     'alternatives': [_food(2, 'Garlic fried rice (sinangag)', 299)]},
    {'itemId': 41, 'confidence': 0.8, 'servings': 1, 'food': _food(4, 'Chicken adobo', 320, serving: '1 serving (150 g)'), 'alternatives': []},
  ],
  'unlisted': [{'itemId': 42, 'name': 'Atchara (pickled papaya)'}],
});

class _PhotoRepo implements MealPhotoRepository {
  PhotoRecognition answer = _answer;
  Object? error;
  Completer<PhotoRecognition>? gate;
  int recognizeCalls = 0;
  Object? logError;
  Completer<void>? logGate;
  final logs = <({int recognitionId, String date, String mealType, List<PhotoLogItem> items})>[];

  @override
  Future<PhotoRecognition> recognize(Uint8List bytes, String mimeType) async {
    recognizeCalls++;
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    return answer;
  }

  @override
  Future<int> log({required int recognitionId, required String date, required String mealType, required List<PhotoLogItem> items}) async {
    logs.add((recognitionId: recognitionId, date: date, mealType: mealType, items: items));
    if (logGate != null) await logGate!.future;
    if (logError != null) throw logError!;
    return items.length;
  }
}

class _Picker implements MealPhotoPicker {
  PickedPhoto? next = PickedPhoto(Uint8List.fromList([0xFF, 0xD8, 0xFF, 9]), 'image/jpeg');
  final sources = <PhotoSource>[];

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    sources.add(source);
    return next;
  }
}

class _Harness {
  final repo = _PhotoRepo();
  final picker = _Picker();
  final nutrition = FakeNutritionRepository();
  bool? result;
  String? searchedInsteadFor;
}

Future<_Harness> _open(WidgetTester tester, {_Harness? h, PhotoSource source = PhotoSource.camera, bool settle = true, Size size = const Size(400, 1400), double scale = 1}) async {
  final harness = h ?? _Harness();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mealPhotoRepositoryProvider.overrideWithValue(harness.repo),
      mealPhotoPickerProvider.overrideWithValue(harness.picker),
      nutritionRepositoryProvider.overrideWithValue(harness.nutrition),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
    ],
    child: MaterialApp(
      theme: fsLightTheme(),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async => harness.result = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => MealPhotoScreen(
            photo: _photo, source: source, mealType: 'lunch',
            onSearchInstead: (ctx, meal) {
              harness.searchedInsteadFor = meal;
              Navigator.of(ctx).pop(false);
            },
          ),
        )),
        child: const Text('go'),
      ))),
    ),
  ));
  await tester.tap(find.text('go'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  return harness;
}

Finder _kcal(String text) => find.descendant(of: find.byKey(const Key('snap.total')), matching: find.text(text));

void main() {
  testWidgets('shows the photo and "Looking at your meal…" while the AI works, then the list', (tester) async {
    final h = _Harness()..repo.gate = Completer();
    await _open(tester, h: h, settle: false);
    expect(find.byKey(const Key('snap.photo')), findsOneWidget);
    expect(find.text('Looking at your meal…'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const Key('snap.analysing'))), isSemantics(isLiveRegion: true));
    expect(find.byKey(const Key('snap.log')), findsNothing);
    h.repo.gate!.complete(_answer);
    await tester.pumpAndSettle();
    expect(find.text('White rice'), findsOneWidget);
  });

  testWidgets('the confirm list: every item, the one not on the list, the meal, the total and Log N items', (tester) async {
    await _open(tester);
    expect(find.text('AI SUGGESTS · CHECK BEFORE LOGGING'), findsOneWidget); // FsEyebrow upper-cases
    expect(find.text('White rice'), findsOneWidget);
    expect(find.text('Chicken adobo'), findsOneWidget);
    expect(find.text('"Atchara (pickled papaya)" isn\'t in FitSync\'s list'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const Key('snap.meal.lunch'))), isSemantics(isSelected: true));
    expect(tester.getSemantics(find.byKey(const Key('snap.meal.dinner'))), isSemantics(isSelected: false));
    expect(_kcal('629 kcal'), findsOneWidget);
    expect(find.text('Log 2 items'), findsOneWidget);
    expect(find.text('Estimates only — review each item and portion before logging.'), findsOneWidget);
    expect(find.text("Your photo is only used to recognise the food and isn't saved."), findsOneWidget);
  });

  testWidgets('a swap chip replaces the food, keeps the old one as a chip, and the total follows', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('snap.alt.0.0')));
    await tester.pumpAndSettle();
    expect(find.text('Garlic fried rice (sinangag)'), findsOneWidget);
    expect(find.bySemanticsLabel('Swap to White rice'), findsOneWidget);
    expect(_kcal('769 kcal'), findsOneWidget); // 299 × 1.5 = 449, + 320
  });

  testWidgets('the stepper changes a portion and the total', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('snap.plus.1')));
    await tester.pumpAndSettle();
    expect(find.text('1.5 × 1 serving (150 g) · 480 kcal'), findsOneWidget); // + is half a serving
    expect(_kcal('789 kcal'), findsOneWidget);
  });

  testWidgets('✕ removes an item with Undo, which puts it back where it was', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('snap.remove.0')));
    await tester.pumpAndSettle();
    expect(find.text('White rice'), findsNothing);
    expect(find.text('Removed White rice'), findsOneWidget);
    expect(find.text('Log 1 item'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('snap.item.0')), matching: find.text('White rice'))).data, 'White rice');
    expect(find.text('Log 2 items'), findsOneWidget);
  });

  testWidgets('"Search for it" opens the search on the name without its bracket; the pick takes the card\'s place', (tester) async {
    final h = await _open(tester);
    await tester.tap(find.byKey(const Key('snap.unlisted.search.2')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a food'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Atchara'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Rice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('snap.item.2')), findsOneWidget);
    expect(find.text('Log 3 items'), findsOneWidget);
    expect(h.nutrition.calls.where((c) => c.startsWith('log')), isEmpty);
  });

  testWidgets('"Add an item" adds the chosen food as a new card', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('snap.add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'rice');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Rice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('snap.item.3')), findsOneWidget);
    expect(find.text('Log 3 items'), findsOneWidget);
  });

  testWidgets('Log sends the kept cards to the chosen meal, closes, and says so', (tester) async {
    final h = await _open(tester);
    await tester.tap(find.byKey(const Key('snap.meal.dinner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('snap.log')));
    await tester.pumpAndSettle();
    final sent = h.repo.logs.single;
    expect([sent.recognitionId, sent.date, sent.mealType], [7, '2026-10-14', 'dinner']);
    expect(sent.items.map((i) => i.toJson()).toList(), [
      {'itemId': 40, 'servings': 1.5, 'food': {'source': 'local', 'id': 1}},
      {'itemId': 41, 'servings': 1.0, 'food': {'source': 'local', 'id': 4}},
    ]);
    expect(h.result, isTrue);
    expect(find.text('Logged 2 items to dinner'), findsOneWidget);
  });

  testWidgets('while Log is sending, the list can\'t be changed and no search opens over it', (tester) async {
    final h = _Harness()..repo.logGate = Completer();
    await _open(tester, h: h);
    await tester.tap(find.byKey(const Key('snap.log')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('snap.add')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsNothing, reason: 'no picker opened mid-log');
    h.repo.logGate!.complete();
    await tester.pumpAndSettle();
    expect(h.repo.logs.single.items, hasLength(2));
    expect(h.result, isTrue);
    expect(find.text('Logged 2 items to lunch'), findsOneWidget);
  });

  testWidgets('Undo tapped while Log is sending doesn\'t put the item back', (tester) async {
    final h = _Harness()..repo.logGate = Completer();
    await _open(tester, h: h);
    await tester.tap(find.byKey(const Key('snap.remove.0')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('snap.log')));
    await tester.pump();
    // Called directly: in the test the busy Log button sits under the snack bar.
    tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('White rice'), findsNothing, reason: 'the list stays as it was sent');
    h.repo.logGate!.complete();
    await tester.pumpAndSettle();
    expect(h.repo.logs.single.items, hasLength(1));
    expect(h.result, isTrue);
    expect(find.text('Logged 1 item to lunch'), findsOneWidget);
  });

  testWidgets('a failed log keeps the list and shows the server\'s message', (tester) async {
    final h = _Harness()..repo.logError = const ApiException('FATSECRET_UNAVAILABLE', "Couldn't reach FatSecret. Try again, or add the food manually.");
    await _open(tester, h: h);
    await tester.tap(find.byKey(const Key('snap.log')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't reach FatSecret. Try again, or add the food manually."), findsOneWidget);
    expect(find.text('White rice'), findsOneWidget);
    expect(tester.widget<FsButton>(find.byKey(const Key('snap.log'))).onPressed, isNotNull, reason: 'Log works again');
    expect(h.result, isNull);
  });

  testWidgets('a food copied from FatSecret shows the FatSecret attribution', (tester) async {
    final h = _Harness()..repo.answer = PhotoRecognition.fromJson({
      'recognitionId': 8, 'remainingToday': 10, 'unlisted': [],
      'items': [{'itemId': 50, 'confidence': 0.7, 'servings': 1, 'food': _food(9, 'Mango Shake', 250, serving: '1 glass', fs: true), 'alternatives': []}],
    });
    await _open(tester, h: h);
    expect(find.text('Powered by fatsecret Platform API'), findsOneWidget);
  });

  group('when something goes wrong', () {
    testWidgets('no food: Retake (the same source again) and Search instead', (tester) async {
      final h = _Harness()..repo.answer = PhotoRecognition.fromJson({'recognitionId': 9, 'remainingToday': 13, 'items': [], 'unlisted': []});
      await _open(tester, h: h);
      expect(find.text("Couldn't spot any food in this photo."), findsOneWidget);
      expect(tester.getSemantics(find.byKey(const Key('snap.error'))), isSemantics(isLiveRegion: true));
      h.repo.answer = _answer;
      await tester.tap(find.byKey(const Key('snap.retake')));
      await tester.pumpAndSettle();
      expect(h.picker.sources, [PhotoSource.camera]);
      expect(h.repo.recognizeCalls, 2);
      expect(find.text('White rice'), findsOneWidget);
    });

    testWidgets('from the library, Retake reads "Choose another photo"', (tester) async {
      final h = _Harness()..repo.answer = PhotoRecognition.fromJson({'recognitionId': 9, 'remainingToday': 13, 'items': [], 'unlisted': []});
      await _open(tester, h: h, source: PhotoSource.library);
      expect(find.text('Choose another photo'), findsOneWidget);
    });

    for (final code in ['VISION_BUSY', 'VISION_UNAVAILABLE', 'NETWORK_ERROR']) {
      testWidgets('$code: Try again sends the same photo', (tester) async {
        final h = _Harness()..repo.error = ApiException(code, 'x');
        await _open(tester, h: h);
        expect(find.text("Couldn't look at your photo right now."), findsOneWidget);
        h.repo.error = null;
        await tester.tap(find.byKey(const Key('snap.retry')));
        await tester.pumpAndSettle();
        expect(h.repo.recognizeCalls, 2);
        expect(h.picker.sources, isEmpty);
        expect(find.text('White rice'), findsOneWidget);
      });
    }

    testWidgets('the daily limit: only Search instead', (tester) async {
      final h = _Harness()..repo.error = const ApiException('PHOTO_LIMIT_REACHED', 'x');
      await _open(tester, h: h);
      expect(find.text("You've used today's meal photos. Try again tomorrow."), findsOneWidget);
      expect(find.byKey(const Key('snap.retake')), findsNothing);
      expect(find.byKey(const Key('snap.retry')), findsNothing);
      await tester.tap(find.byKey(const Key('snap.searchInstead')));
      await tester.pumpAndSettle();
      expect(h.searchedInsteadFor, 'lunch');
    });

    testWidgets('a photo the server can\'t read: Retake', (tester) async {
      final h = _Harness()..repo.error = const ApiException('INVALID_IMAGE', 'x');
      await _open(tester, h: h);
      expect(find.text("Couldn't read this photo. Try another one."), findsOneWidget);
      expect(find.byKey(const Key('snap.retake')), findsOneWidget);
    });

    testWidgets('PRO_REQUIRED closes the screen and opens Pro', (tester) async {
      final h = _Harness()..repo.error = const ApiException('PRO_REQUIRED', 'x');
      await _open(tester, h: h);
      expect(find.text('FitSync Pro'), findsOneWidget);
      expect(h.result, isFalse);
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the confirm screen fits a 320 dp phone at ${scale}x text', (tester) async {
      await _open(tester, size: const Size(320, 640), scale: scale);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(const Key('snap.total')), 200, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });
  }
}
