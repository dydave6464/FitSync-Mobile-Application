import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/presentation/add_food_manually_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

Future<FakeNutritionRepository> _pump(WidgetTester tester, {Size? size, double textScale = 1}) async {
  final repo = FakeNutritionRepository();
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(repo),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Consumer(builder: (context, ref, _) {
        ref.watch(nutritionDayProvider); // loaded, as on the Nutrition tab
        return Scaffold(body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
            builder: (_) => const AddFoodManuallyScreen(mealType: 'snack'),
          )),
          child: const Text('go'),
        ));
      }),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('calories fill in from the macros', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.pump();
    expect(find.text('198 kcal'), findsOneWidget);
  });

  testWidgets('calories match the server, which rounds each gram to 2 decimals first', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.fat')), '0.0551');
    await tester.pump();
    // 0.0551 -> 0.06 g -> 0.54 kcal -> 1 (unrounded it would show 0).
    expect(find.text('1 kcal'), findsOneWidget);
  });

  testWidgets('Log stays off until there is a name and some macros', (tester) async {
    // Tall enough that every field and the Log button are built at once --
    // this test repeatedly jumps between the top and bottom of the form.
    final repo = await _pump(tester, size: const Size(400, 1200));
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pump();
    expect(repo.calls.where((c) => c.startsWith('log')), isEmpty);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pump();
    expect(repo.calls.where((c) => c.startsWith('log')), isEmpty, reason: 'no macros yet');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '600');
    await tester.pump();
    expect(find.text('Each value must be 0–500 g'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.pump();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('log 2026-10-14 snack Turon x1.0'));
    expect(find.text('go'), findsOneWidget, reason: 'back on the screen underneath');
  });

  testWidgets('fiber is optional, logged with the food and never changes kcal', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.enterText(find.byKey(const Key('manual.fiber')), '4');
    await tester.pump();
    expect(find.text('198 kcal'), findsOneWidget, reason: 'kcal comes from protein, carbs and fat only');
    // `.first` is the screen's outer list; the TextFields above it each own a
    // later Scrollable of their own (for text selection/editing).
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.fiberG, 4);
  });

  testWidgets('blank fiber logs as unknown', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.fiberG, isNull);
  });

  testWidgets('an out-of-range fiber says so and Log stays off', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.enterText(find.byKey(const Key('manual.fiber')), '600');
    await tester.pump();
    expect(find.text('Each value must be 0–500 g'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pump();
    expect(repo.calls.where((c) => c.startsWith('log')), isEmpty);
  });

  testWidgets('sugar and sodium are optional, logged with the food and never change kcal', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.enterText(find.byKey(const Key('manual.sugar')), '4');
    await tester.enterText(find.byKey(const Key('manual.sodium')), '250');
    await tester.pump();
    expect(find.text('198 kcal'), findsOneWidget, reason: 'kcal comes from protein, carbs and fat only');
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.sugarG, 4);
    expect(repo.lastLogged!.sodiumMg, 250);
  });

  testWidgets('blank sugar and sodium log as unknown', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.sugarG, isNull);
    expect(repo.lastLogged!.sodiumMg, isNull);
  });

  testWidgets('an out-of-range sodium says so and Log stays off', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byKey(const Key('manual.name')), 'Turon');
    await tester.enterText(find.byKey(const Key('manual.protein')), '2');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '34');
    await tester.enterText(find.byKey(const Key('manual.fat')), '6');
    await tester.enterText(find.byKey(const Key('manual.sodium')), '25000');
    await tester.pump();
    expect(find.text('Sodium must be 0–20,000 mg'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('manual.log')), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pump();
    expect(repo.calls.where((c) => c.startsWith('log')), isEmpty);
  });

  testWidgets('the Fiber, Sugar and Sodium boxes are labelled and the six boxes fit a 320 dp phone at large text', (tester) async {
    await _pump(tester, size: const Size(320, 900), textScale: 1.6);
    expect(find.text('Fiber (g)'), findsOneWidget);
    expect(find.text('Sugar (g)'), findsOneWidget);
    expect(find.text('Sodium (mg)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
