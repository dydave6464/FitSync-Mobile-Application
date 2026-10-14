import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/presentation/add_food_manually_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

Future<FakeNutritionRepository> _pump(WidgetTester tester) async {
  final repo = FakeNutritionRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(repo),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
    ],
    child: MaterialApp(home: Consumer(builder: (context, ref, _) {
      ref.watch(nutritionDayProvider); // loaded, as on the Nutrition tab
      return Scaffold(body: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
          builder: (_) => const AddFoodManuallyScreen(mealType: 'snack'),
        )),
        child: const Text('go'),
      ));
    })),
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

  testWidgets('Log stays off until there is a name and some macros', (tester) async {
    final repo = await _pump(tester);
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
}
