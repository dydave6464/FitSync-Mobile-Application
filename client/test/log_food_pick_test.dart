import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/log_food_screen.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

class _Repo extends FakeNutritionRepository {
  final List<String> queries = [];

  @override
  Future<FoodSearchResult> search(String q) async {
    queries.add(q);
    return const FoodSearchResult(fatsecretUnavailable: false, foods: [
      Food(source: 'local', id: 6, name: 'Atchara (pickled green papaya)', servingDesc: '2 tbsp (30 g)', kcal: 20, proteinG: 0.2, carbsG: 5, fatG: 0),
      Food(source: 'fatsecret', externalId: 'fs-2', name: 'Atchara Relish', servingDesc: '1 tbsp', kcal: 15, proteinG: 0, carbsG: 4, fatG: 0),
    ]);
  }

  @override
  Future<List<Food>> recent() async => const [
    // A spirit the user logged at its listed kcal: all of it is alcohol.
    Food(source: 'manual', entryId: 56, name: 'Gin', servingDesc: '1 glass', kcal: 97, proteinG: 0, carbsG: 0, fatG: 0),
  ];
}

Future<({_Repo repo, Food? Function() picked})> _pump(WidgetTester tester, {String? query}) async {
  final repo = _Repo();
  Food? picked;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWithValue(repo),
      nutritionClockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 14, 4)),
    ],
    child: MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async => picked = await pickFood(context, mealType: 'lunch', query: query),
      child: const Text('go'),
    )))),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return (repo: repo, picked: () => picked);
}

void main() {
  testWidgets('opens on the query, already searched, as "Choose a food" with no meal to pick', (tester) async {
    final h = await _pump(tester, query: 'Atchara');
    expect(find.text('Choose a food'), findsOneWidget);
    expect(find.text('ADDING TO'), findsNothing);
    expect(find.text('Lunch'), findsNothing);
    expect(h.repo.queries, ['Atchara']);
    expect(find.text('Atchara (pickled green papaya)'), findsOneWidget);
  });

  testWidgets('a food picked from Recents comes back naming its entry, so Snap a meal keeps its kcal', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('Recents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gin'));
    await tester.pumpAndSettle();
    expect(h.picked()!.kcal, 97);
    expect(h.picked()!.toRef()['basedOnEntryId'], 56);
    expect(h.repo.calls.where((c) => c.startsWith('log')), isEmpty);
  });

  testWidgets('a FitSync food comes straight back, with nothing logged', (tester) async {
    final h = await _pump(tester, query: 'Atchara');
    await tester.tap(find.text('Atchara (pickled green papaya)'));
    await tester.pumpAndSettle();
    expect(h.picked()!.id, 6);
    expect(find.text('Choose a food'), findsNothing);
    expect(h.repo.calls.where((c) => c.startsWith('log')), isEmpty);
  });

  testWidgets('a FatSecret food comes back with its detailed serving', (tester) async {
    final h = await _pump(tester, query: 'Atchara');
    h.repo.fatsecretDetails['fs-2'] = const Food(source: 'fatsecret', externalId: 'fs-2', name: 'Atchara Relish', servingDesc: '1 tbsp (15 g)', kcal: 16, proteinG: 0, carbsG: 4, fatG: 0);
    await tester.tap(find.text('Atchara Relish'));
    await tester.pumpAndSettle();
    expect(h.picked()!.servingDesc, '1 tbsp (15 g)');
    expect(h.repo.fatsecretCalls, ['fs-2']);
  });

  testWidgets('Add manually hands back the typed food instead of logging it', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = await _pump(tester);
    await tester.tap(find.byKey(const Key('food.manual')));
    await tester.pumpAndSettle();
    expect(find.text('Breakfast'), findsNothing, reason: 'the meal is chosen on the confirm screen');
    await tester.enterText(find.byKey(const Key('manual.name')), 'Atchara');
    await tester.enterText(find.byKey(const Key('manual.carbs')), '5');
    await tester.pump();
    expect(find.text('Use this food'), findsOneWidget);
    await tester.tap(find.byKey(const Key('manual.log')));
    await tester.pumpAndSettle();
    final food = h.picked()!;
    expect([food.source, food.name, food.carbsG, food.kcal], ['manual', 'Atchara', 5.0, 20]);
    expect(find.text('Choose a food'), findsNothing, reason: 'Log food closed too');
    expect(h.repo.calls.where((c) => c.startsWith('log')), isEmpty);
  });

  testWidgets('without a query it opens on the usual start hint', (tester) async {
    final h = await _pump(tester);
    expect(find.text('What did you eat?'), findsOneWidget);
    expect(h.repo.queries, isEmpty);
  });
}
