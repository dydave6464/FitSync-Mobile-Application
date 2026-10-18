import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/log_food_screen.dart';
import 'package:fitsync/features/nutrition/presentation/nutrition_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/nutrition/presentation/widgets/log_food_sheet.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

NutritionDay _day(String date, {bool target = true, List<FoodEntry> lunch = const [], List<String> missing = const []}) {
  final base = NutritionDay(
    date: date,
    target: target ? const NutritionTarget(kcal: 2150, proteinG: 95, carbsG: 280, fatG: 60, fiberG: 0) : null,
    targetMissing: missing,
    totals: const MacroTotals(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 0, sodiumMg: 0),
    meals: {for (final m in mealTypes) m: const []},
  );
  return lunch.fold(base, (d, e) => d.withEntry(e));
}

FoodEntry _adobo({int id = 7, String source = 'local'}) => FoodEntry(
  id: id, mealType: 'lunch', name: 'Chicken adobo', servingDesc: '1 serving', servings: 1,
  kcal: 1160, proteinG: 78, carbsG: 140, fatG: 36, source: source, foodId: 6,
  externalId: source == 'fatsecret' ? 'fs-1' : null,
);

/// Holds one date's load until the test says, so the screen can be caught
/// busy -- the previous day shown, the next one on its way.
class _HeldRepo extends FakeNutritionRepository {
  String? heldDate;
  final gate = Completer<void>();

  @override
  Future<NutritionDay> getDay(String? date) async {
    if (date != null && date == heldDate) await gate.future;
    return super.getDay(date);
  }
}

Future<FakeNutritionRepository> _pump(
  WidgetTester tester, {
  required NutritionDay today,
  FakeNutritionRepository? repo,
  DateTime? now,
  Size size = const Size(390, 844),
  double textScale = 1,
  VoidCallback? onGoToProfile,
}) async {
  final repo0 = (repo ?? FakeNutritionRepository())..days[today.date] = today;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(repo0),
      nutritionClockProvider.overrideWithValue(() => now ?? DateTime.utc(2026, 10, 14, 11)), // 19:00 Manila
    ],
    child: MaterialApp(
      // Inside the app, so it adjusts the MediaQuery MaterialApp builds from
      // the view rather than being replaced by it.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: NutritionScreen(onGoToProfile: onGoToProfile),
    ),
  ));
  await tester.pumpAndSettle();
  return repo0;
}

void main() {
  testWidgets('shows eaten against the target, macros and meals', (tester) async {
    await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
    expect(find.text('1,160'), findsOneWidget);
    expect(find.text('/ 2,150 kcal'), findsOneWidget);
    expect(find.text('78 / 95 g'), findsOneWidget);
    expect(find.text('Chicken adobo'), findsOneWidget);
    // A meal with food is headed with its name and subtotal; one without is
    // a single row to add to it.
    expect(find.text('LUNCH'), findsOneWidget);
    // The subtotal and its one food, which here are the same number.
    expect(find.text('1160 kcal'), findsNWidgets(2));
    for (final m in ['breakfast', 'dinner', 'snack']) {
      expect(find.text('Add $m'), findsOneWidget, reason: m);
    }
    expect(find.text('Today'), findsOneWidget);
  });

  // Four rows of "0 kcal +" said nothing; an empty meal now says what to do.
  testWidgets('an empty meal is one Add row, with no zero subtotal', (tester) async {
    await _pump(tester, today: _day('2026-10-14'));
    for (final m in ['breakfast', 'lunch', 'dinner', 'snack']) {
      expect(find.text('Add $m'), findsOneWidget, reason: m);
    }
    expect(find.text('0 kcal'), findsNothing);
    // One way to add, by meal: no second button repeating one of them.
    expect(find.byKey(const Key('nutrition.log')), findsNothing);
  });

  // The clock's guess is a hint on the row, not a decision in a label.
  testWidgets('the meal the clock suggests is the highlighted row', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, today: _day('2026-10-14')); // 19:00 Manila: dinner
    Color colourOf(String text) => tester.widget<Text>(find.text(text)).style!.color!;
    final fs = tester.element(find.text('Add dinner')).fs;
    expect(colourOf('Add dinner'), fs.accentText);
    for (final m in ['breakfast', 'lunch', 'snack']) {
      expect(colourOf('Add $m'), fs.text2, reason: m);
    }
    // Not by colour alone: a screen reader hears it too.
    expect(
      tester.getSemantics(find.byKey(const Key('meal.add.dinner'))),
      matchesSemantics(
        label: 'Add dinner',
        hint: 'Suggested for now',
        isButton: true,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  // Solid against dashed is the suggested row's cue beside its colour, so
  // its outline is drawn in the strong text green, not the faint tint.
  testWidgets("the suggested row's outline is the text green", (tester) async {
    await _pump(tester, today: _day('2026-10-14'));
    final row = find.byKey(const Key('meal.add.dinner'));
    final material = tester.widget<Material>(find.ancestor(of: row, matching: find.byType(Material)).first);
    final side = (material.shape! as RoundedRectangleBorder).side;
    expect(side.color, tester.element(row).fs.accentText);
  });

  // Disabled while the next day loads, and it shows: the green suggestion
  // dims with the rest instead of inviting a tap that does nothing.
  testWidgets('while a day loads, the Add rows are off and look it', (tester) async {
    final semantics = tester.ensureSemantics();
    final repo = _HeldRepo()..heldDate = '2026-10-13';
    await _pump(tester, today: _day('2026-10-14'), repo: repo);
    await tester.tap(find.byKey(const Key('day.prev')));
    await tester.pump();

    final fs = tester.element(find.text('Add dinner')).fs;
    expect(tester.widget<Text>(find.text('Add dinner')).style!.color, fs.text3);
    final node = tester.getSemantics(find.byKey(const Key('meal.add.dinner')));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    await tester.tap(find.byKey(const Key('meal.add.dinner')));
    await tester.pump();
    expect(find.byType(LogFoodScreen), findsNothing);

    repo.gate.complete();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  // One verb for one action: an empty meal says "Add lunch", so its + once
  // it has food says the same, not "Log lunch".
  testWidgets("a meal's + is named as adding to it", (tester) async {
    await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
    expect(find.byTooltip('Add to lunch'), findsOneWidget);
  });

  testWidgets('on another day no meal is suggested', (tester) async {
    await _pump(tester, today: _day('2026-10-14'));
    await tester.tap(find.byKey(const Key('day.prev')));
    await tester.pumpAndSettle();
    final fs = tester.element(find.text('Add dinner')).fs;
    expect(tester.widget<Text>(find.text('Add dinner')).style!.color, fs.text2);
  });

  testWidgets('an Add row opens Log food with that meal picked', (tester) async {
    await _pump(tester, today: _day('2026-10-14'));
    await tester.tap(find.byKey(const Key('meal.add.breakfast')));
    await tester.pumpAndSettle();
    expect(tester.widget<LogFoodScreen>(find.byType(LogFoodScreen)).mealType, 'breakfast');
  });

  testWidgets("a meal with food keeps its + for adding more", (tester) async {
    await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
    expect(find.text('Add lunch'), findsNothing);
    await tester.tap(find.byKey(const Key('meal.add.lunch')));
    await tester.pumpAndSettle();
    expect(tester.widget<LogFoodScreen>(find.byType(LogFoodScreen)).mealType, 'lunch');
  });

  testWidgets('day switch: back a day, and never past today', (tester) async {
    final repo = await _pump(tester, today: _day('2026-10-14'));
    final next = tester.widget<IconButton>(find.byKey(const Key('day.next')));
    expect(next.onPressed, isNull);
    await tester.tap(find.byKey(const Key('day.prev')));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(repo.calls, contains('get 2026-10-13'));
  });

  testWidgets('delete hides the food and Undo logs it again', (tester) async {
    final repo = await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
    await tester.tap(find.byKey(const Key('entry.delete.7')));
    await tester.pumpAndSettle();
    expect(find.text('Chicken adobo'), findsNothing);
    expect(find.text('Removed Chicken adobo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repo.calls.last, startsWith('get'));
    expect(repo.calls, contains('log 2026-10-14 lunch Chicken adobo x1.0'));
    expect(find.text('Chicken adobo'), findsOneWidget);
  });

  testWidgets('the Undo message goes away on its own', (tester) async {
    // A SnackBar with an action persists by default, which left "Removed …"
    // over the meals for as long as the tab stayed open.
    await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
    await tester.tap(find.byKey(const Key('entry.delete.7')));
    await tester.pumpAndSettle();
    expect(find.text('Removed Chicken adobo'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Removed Chicken adobo'), findsNothing);
  });

  testWidgets('the Undo message stays up for screen-reader users', (tester) async {
    // Reaching Undo with TalkBack takes longer than four seconds, so with a
    // screen reader on it waits, as the workout review's Undo does.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
    await tester.tap(find.byKey(const Key('entry.delete.7')));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Removed Chicken adobo'), findsOneWidget);
  });

  testWidgets('a second removal replaces the first message rather than queueing', (tester) async {
    // With a screen reader the message waits, so one queued behind it would
    // never show, and its Undo would be out of reach.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    const rice = FoodEntry(
      id: 8, mealType: 'lunch', name: 'Garlic rice', servingDesc: '1 cup', servings: 1,
      kcal: 240, proteinG: 4, carbsG: 50, fatG: 3, source: 'local', foodId: 9,
    );
    await _pump(tester, today: _day('2026-10-14', lunch: [_adobo(), rice]));
    await tester.tap(find.byKey(const Key('entry.delete.7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('entry.delete.8')));
    await tester.pumpAndSettle();

    expect(find.text('Removed Garlic rice'), findsOneWidget);
    expect(find.text('Removed Chicken adobo'), findsNothing);
  });

  testWidgets('Undo after switching days logs back to the day it was removed from', (tester) async {
    final repo = await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
    await tester.tap(find.byKey(const Key('entry.delete.7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day.prev')));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('log 2026-10-14 lunch Chicken adobo x1.0'));
    expect(repo.calls.where((c) => c.startsWith('log 2026-10-13')), isEmpty);
    expect(find.text('Chicken adobo'), findsNothing, reason: 'yesterday stays as it was');
  });

  testWidgets('no target: names what is missing and links to the profile', (tester) async {
    var opened = false;
    await _pump(tester,
        today: _day('2026-10-14', target: false, missing: const ['heightCm', 'weightKg']),
        onGoToProfile: () => opened = true);
    expect(find.text('Add your height & weight to see a target'), findsOneWidget);
    await tester.tap(find.text('Update profile'));
    expect(opened, isTrue);
  });

  testWidgets('a FatSecret entry brings the attribution', (tester) async {
    await _pump(tester, today: _day('2026-10-14', lunch: [_adobo(source: 'fatsecret')]));
    await tester.scrollUntilVisible(find.text('Powered by fatsecret Platform API'), 200);
    expect(find.text('Powered by fatsecret Platform API'), findsOneWidget);
  });

  // Tall enough that the list builds every meal row, empty ones included.
  testWidgets('the Add rows fit a 320 dp phone at 2x text', (tester) async {
    await _pump(tester, today: _day('2026-10-14'), size: const Size(320, 2400), textScale: 2);
    expect(tester.takeException(), isNull);
    for (final m in ['breakfast', 'lunch', 'dinner', 'snack']) {
      expect(find.text('Add $m'), findsOneWidget, reason: m);
      expect(tester.getSize(find.byKey(Key('meal.add.$m'))).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('fits a 320 dp phone at large text without overflow', (tester) async {
    await _pump(tester,
        today: _day('2026-10-14', lunch: [_adobo()]), size: const Size(320, 640), textScale: 1.6);
    expect(tester.takeException(), isNull);
  });

  group('changing a logged food', () {
    Finder sheet() => find.byType(LogFoodSheet);

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('logSheet.log')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logSheet.log')));
      await tester.pumpAndSettle();
    }

    testWidgets("tapping a row opens the sheet on the entry's meal and servings", (tester) async {
      final adobo = FoodEntry(
        id: 7, mealType: 'lunch', name: 'Chicken adobo', servingDesc: '1 serving', servings: 1.5,
        kcal: 480, proteinG: 42, carbsG: 6, fatG: 31.5, source: 'local', foodId: 6,
      );
      await _pump(tester, today: _day('2026-10-14', lunch: [adobo]));
      await tester.tap(find.byKey(const Key('entry.7')));
      await tester.pumpAndSettle();
      final open = tester.widget<LogFoodSheet>(sheet());
      expect(open.mealType, 'lunch');
      expect(open.servings, 1.5);
      expect(open.food.kcal, 320, reason: 'per serving');
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('Snack and Save changes moves the food under Snack', (tester) async {
      final repo = await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
      await tester.tap(find.byKey(const Key('entry.7')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: sheet(), matching: find.text('Snack')));
      await tester.pump();
      await save(tester);
      expect(repo.calls, contains('update 7 snack x1.0'));
      expect(find.text('SNACK'), findsOneWidget);
      expect(find.text('Add lunch'), findsOneWidget, reason: 'lunch is empty now');
    });

    testWidgets('saving with nothing changed sends nothing', (tester) async {
      final repo = await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
      await tester.tap(find.byKey(const Key('entry.7')));
      await tester.pumpAndSettle();
      await save(tester);
      expect(sheet(), findsNothing);
      expect(repo.calls.where((c) => c.startsWith('update')), isEmpty);
    });

    testWidgets('a failed save says so and leaves the day as it was', (tester) async {
      final repo = await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
      await tester.tap(find.byKey(const Key('entry.7')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: sheet(), matching: find.text('Snack')));
      await tester.pump();
      repo.failNext = true;
      await save(tester);
      expect(find.text("Couldn't save — try again."), findsOneWidget);
      expect(find.text('LUNCH'), findsOneWidget);
      expect(find.text('Add snack'), findsOneWidget);
    });

    testWidgets('the ✕ removes without opening the sheet', (tester) async {
      await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
      await tester.tap(find.byKey(const Key('entry.delete.7')));
      await tester.pumpAndSettle();
      expect(sheet(), findsNothing);
      expect(find.text('Removed Chicken adobo'), findsOneWidget);
    });

    testWidgets('a food still saving does not open the sheet', (tester) async {
      final repo = await _pump(tester, today: _day('2026-10-14'));
      repo.hold = Completer<void>();
      final container = ProviderScope.containerOf(tester.element(find.byType(NutritionScreen)));
      final logging = container.read(nutritionDayProvider.notifier)
          .log(const Food(source: 'local', id: 3, name: 'Rice', kcal: 205, proteinG: 4, carbsG: 45, fatG: 0),
              mealType: 'dinner', servings: 1);
      await tester.pump();
      await tester.tap(find.text('Rice'));
      await tester.pumpAndSettle();
      expect(sheet(), findsNothing);
      repo.hold!.complete();
      await logging;
      await tester.pumpAndSettle();
    });

    testWidgets('while a day loads, a row does not open the sheet', (tester) async {
      final repo = _HeldRepo()..heldDate = '2026-10-13';
      await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]), repo: repo);
      await tester.tap(find.byKey(const Key('day.prev')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('entry.7')));
      await tester.pump(); // the progress bar never settles
      await tester.pump(const Duration(milliseconds: 500));
      expect(sheet(), findsNothing);
      repo.gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a row is one button with a Change hint, and the ✕ its own', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, today: _day('2026-10-14', lunch: [_adobo()]));
      expect(
        tester.getSemantics(find.byKey(const Key('entry.7'))),
        matchesSemantics(
          label: 'Chicken adobo\n1 serving\n1160 kcal',
          onTapHint: 'Change',
          isButton: true,
          hasTapAction: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('entry.delete.7'))),
        matchesSemantics(
          tooltip: 'Remove Chicken adobo',
          isButton: true,
          hasTapAction: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a row is at least 48 dp tall and fits a 320 dp phone at 2x text', (tester) async {
      await _pump(tester,
          today: _day('2026-10-14', lunch: [_adobo()]), size: const Size(320, 2400), textScale: 2);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const Key('entry.7'))).height, greaterThanOrEqualTo(48));
    });
  });

  group('after logging', () {
    Future<FakeNutritionRepository> logRiceToDinner(WidgetTester tester) async {
      final repo = await _pump(tester, today: _day('2026-10-14'));
      await tester.tap(find.byKey(const Key('meal.add.dinner')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('food.search')), 'rice');
      await tester.pump(foodSearchDebounce);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rice'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logSheet.log')));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('Log food closes and says where the food went', (tester) async {
      await logRiceToDinner(tester);
      expect(find.byType(LogFoodScreen), findsNothing);
      expect(find.text('Added Rice to dinner'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('Change opens the sheet on the saved food, and Snack moves it', (tester) async {
      final repo = await logRiceToDinner(tester);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      final open = tester.widget<LogFoodSheet>(find.byType(LogFoodSheet));
      expect(open.mealType, 'dinner');
      expect(find.text('Save changes'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(LogFoodSheet), matching: find.text('Snack')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('logSheet.log')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('update 100 snack x1.0'));
      expect(find.text('SNACK'), findsOneWidget);
      expect(find.text('Add dinner'), findsOneWidget);
    });

    testWidgets('the Added message goes away on its own', (tester) async {
      await logRiceToDinner(tester);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Added Rice to dinner'), findsNothing);
    });

    testWidgets('the Added message stays up for screen-reader users', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await logRiceToDinner(tester);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Added Rice to dinner'), findsOneWidget);
    });

    testWidgets('Add manually says the same, and its Change opens the sheet', (tester) async {
      final repo = await _pump(tester, today: _day('2026-10-14'), size: const Size(400, 1400));
      await tester.tap(find.byKey(const Key('meal.add.dinner')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('food.manual')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
      await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
      await tester.pump();
      await tester.tap(find.byKey(const Key('manual.log')));
      await tester.pumpAndSettle();
      expect(find.byType(LogFoodScreen), findsNothing);
      expect(find.text('Added Turon to dinner'), findsOneWidget);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('servings.plus')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('logSheet.log')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('update 100 dinner x1.5'));
    });
  });
}
