import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/log_food_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

class _SearchRepo extends FakeNutritionRepository {
  final List<String> queries = [];
  bool unavailable = false;

  @override
  Future<FoodSearchResult> search(String q) async {
    queries.add(q);
    return FoodSearchResult(fatsecretUnavailable: unavailable, foods: [
      const Food(source: 'local', id: 6, name: 'Chicken adobo', servingDesc: '1 serving', kcal: 320, proteinG: 28, carbsG: 4, fatG: 21),
      if (!unavailable)
        const Food(source: 'fatsecret', externalId: 'fs-2', name: 'Adobo Flakes', servingDesc: '1 cup', kcal: 410, proteinG: 30, carbsG: 2, fatG: 31),
    ]);
  }

  @override
  Future<List<Food>> recent() async =>
      const [Food(source: 'manual', name: 'Turon', kcal: 198, proteinG: 2, carbsG: 34, fatG: 6)];
}

Future<void> _pump(WidgetTester tester, _SearchRepo repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(repo),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
    ],
    child: MaterialApp(home: Consumer(builder: (context, ref, _) {
      ref.watch(nutritionDayProvider); // loaded, as on the Nutrition tab
      return Scaffold(body: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const LogFoodScreen(mealType: 'lunch'),
        )),
        child: const Text('go'),
      ));
    })),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('waits for typing to pause, then shows results with labels', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    expect(find.text('Log lunch'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('food.search')), 'ad');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repo.queries, ['adobo']);
    expect(find.text('Chicken adobo'), findsOneWidget);
    expect(find.text('Adobo Flakes'), findsOneWidget);
    expect(find.text('FatSecret'), findsOneWidget);
    expect(find.text('Powered by fatsecret Platform API'), findsOneWidget);
  });

  testWidgets('the search stops at 60 characters, the most the server accepts', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'a' * 70);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repo.queries, ['a' * 60]);
  });

  testWidgets('FatSecret down shows a quiet note', (tester) async {
    final repo = _SearchRepo()..unavailable = true;
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Showing FitSync foods only'), findsOneWidget);
    expect(find.text('Powered by fatsecret Platform API'), findsNothing);
  });

  testWidgets('Recents lists recent foods', (tester) async {
    await _pump(tester, _SearchRepo());
    await tester.tap(find.text('Recents'));
    await tester.pumpAndSettle();
    expect(find.text('Turon'), findsOneWidget);
  });

  testWidgets('choosing a food logs it and returns to Nutrition', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken adobo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget, reason: 'back on the screen underneath');
    expect(repo.calls, contains('log 2026-10-14 lunch Chicken adobo x1.0'));
  });

  testWidgets('a failed save says so after returning', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    repo.failNext = true;
    await tester.tap(find.text('Chicken adobo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save — try again."), findsOneWidget);
  });

  testWidgets('a food with edited numbers is saved as your own entry', (tester) async {
    final repo = _SearchRepo();
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('food.search')), 'adobo');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken adobo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logSheet.edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const Key('logSheet.protein')), matching: find.byType(TextField)), '30');
    await tester.pump();
    await tester.tap(find.byKey(const Key('logSheet.log')));
    await tester.pumpAndSettle();
    expect(repo.lastLogged!.source, 'manual');
    expect(repo.lastLogged!.name, 'Chicken adobo');
    expect(repo.lastLogged!.proteinG, 30);
  });
}
