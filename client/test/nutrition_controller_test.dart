import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/nutrition/data/nutrition_repository.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';

NutritionDay emptyDay(String date) => NutritionDay(
  date: date, target: null, targetMissing: const [],
  totals: const MacroTotals(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0),
  meals: {for (final m in mealTypes) m: const []},
);

const rice = Food(source: 'local', id: 3, name: 'Rice', servingDesc: '1 cup', kcal: 205, proteinG: 4.3, carbsG: 44.5, fatG: 0.4);

/// A scriptable repository. [days] is what getDay serves; [failNext] makes the
/// next write throw; [hold] keeps the next write pending until completed.
class FakeNutritionRepository implements NutritionRepository {
  final Map<String, NutritionDay> days = {};
  final List<String> calls = [];
  bool failNext = false;
  Completer<void>? hold;
  int _ids = 100;

  NutritionDay dayOf(String date) => days[date] ?? emptyDay(date);

  @override
  Future<NutritionDay> getDay(String date) async {
    calls.add('get $date');
    return dayOf(date);
  }

  @override
  Future<FoodEntry> logEntry({required String date, required String mealType, required double servings, required Food food}) async {
    calls.add('log $date $mealType ${food.name} x$servings');
    if (hold != null) await hold!.future;
    if (failNext) { failNext = false; throw const ApiException('NETWORK_ERROR', 'offline'); }
    final saved = FoodEntry.pending(id: _ids++, food: food, mealType: mealType, servings: servings);
    days[date] = dayOf(date).withEntry(saved);
    return saved;
  }

  @override
  Future<void> deleteEntry(int id) async {
    calls.add('delete $id');
    if (failNext) { failNext = false; throw const ApiException('NETWORK_ERROR', 'offline'); }
    days.updateAll((_, d) => d.without(id));
  }

  @override
  Future<FoodSearchResult> search(String q) async => const FoodSearchResult(foods: [rice], fatsecretUnavailable: false);

  @override
  Future<List<Food>> recent() async => const [rice];
}

ProviderContainer _container(FakeNutritionRepository repo, {DateTime? now}) {
  final c = ProviderContainer(overrides: [
    nutritionRepositoryProvider.overrideWithValue(repo),
    nutritionClockProvider.overrideWithValue(() => now ?? DateTime.utc(2026, 10, 14, 4)), // 12:00 Manila
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('loads today (Manila) by default, and a chosen day after set/shift', () async {
    final repo = FakeNutritionRepository();
    final c = _container(repo, now: DateTime.utc(2026, 10, 13, 17)); // 01:00 on the 14th in Manila
    expect((await c.read(nutritionDayProvider.future)).date, '2026-10-14');
    c.read(nutritionDateProvider.notifier).shift(-1);
    expect((await c.read(nutritionDayProvider.future)).date, '2026-10-13');
    c.read(nutritionDateProvider.notifier).shift(1);
    expect(c.read(nutritionDateProvider), isNull, reason: 'back on today means following today');
  });

  test('shift never moves past today', () {
    final c = _container(FakeNutritionRepository());
    c.read(nutritionDateProvider.notifier).shift(1);
    expect(c.read(nutritionDateProvider), isNull);
  });

  test('log shows the entry at once, then settles on the server day', () async {
    final repo = FakeNutritionRepository()..hold = Completer<void>();
    final c = _container(repo);
    await c.read(nutritionDayProvider.future);
    final pending = c.read(nutritionDayProvider.notifier).log(rice, mealType: 'lunch', servings: 2);
    final mid = c.read(nutritionDayProvider).value!;
    expect(mid.meals['lunch']!.single.id, isNegative);
    expect(mid.totals.kcal, 410);
    repo.hold!.complete();
    await pending;
    final after = c.read(nutritionDayProvider).value!;
    expect(after.meals['lunch']!.single.id, 100);
  });

  test('a failed log takes the entry back out and throws', () async {
    final repo = FakeNutritionRepository()..failNext = true;
    final c = _container(repo);
    await c.read(nutritionDayProvider.future);
    await expectLater(
      c.read(nutritionDayProvider.notifier).log(rice, mealType: 'lunch', servings: 1),
      throwsA(isA<ApiException>()),
    );
    expect(c.read(nutritionDayProvider).value!.meals['lunch'], isEmpty);
  });

  test('remove hides at once; a failed remove puts it back and throws', () async {
    final repo = FakeNutritionRepository();
    final c = _container(repo);
    await c.read(nutritionDayProvider.future);
    await c.read(nutritionDayProvider.notifier).log(rice, mealType: 'dinner', servings: 1);
    final entry = c.read(nutritionDayProvider).value!.meals['dinner']!.single;

    repo.failNext = true;
    await expectLater(c.read(nutritionDayProvider.notifier).remove(entry), throwsA(isA<ApiException>()));
    expect(c.read(nutritionDayProvider).value!.meals['dinner']!.single.id, entry.id);

    await c.read(nutritionDayProvider.notifier).remove(entry);
    expect(c.read(nutritionDayProvider).value!.meals['dinner'], isEmpty);
    expect(repo.calls, contains('delete ${entry.id}'));
  });

  test('logging on a past day saves to that day', () async {
    final repo = FakeNutritionRepository();
    final c = _container(repo);
    c.read(nutritionDateProvider.notifier).shift(-1);
    await c.read(nutritionDayProvider.future);
    await c.read(nutritionDayProvider.notifier).log(rice, mealType: 'dinner', servings: 1);
    expect(repo.calls, contains('log 2026-10-13 dinner Rice x1.0'));
  });
}
