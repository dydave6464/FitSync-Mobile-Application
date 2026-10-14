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

/// A scriptable repository. [days] is what getDay serves, and [today] is the
/// server's today, served for a null date; [failNext] makes the next write
/// throw and [failNextGet] the next getDay; [hold] keeps writes pending until
/// completed; [recentCalls] counts recents fetches.
class FakeNutritionRepository implements NutritionRepository {
  final Map<String, NutritionDay> days = {};
  final List<String> calls = [];
  /// The tests' clocks sit on this day in Manila.
  String today = '2026-10-14';
  bool failNext = false;
  /// The last food passed to logEntry, so a test can see what was saved.
  Food? lastLogged;
  bool failNextGet = false;
  Completer<void>? hold;
  int recentCalls = 0;
  int _ids = 100;

  NutritionDay dayOf(String date) => days[date] ?? emptyDay(date);

  @override
  Future<NutritionDay> getDay(String? date) async {
    calls.add('get ${date ?? 'today'}');
    if (failNextGet) { failNextGet = false; throw const ApiException('NETWORK_ERROR', 'offline'); }
    return dayOf(date ?? today);
  }

  @override
  Future<FoodEntry> logEntry({required String date, required String mealType, required double servings, required Food food}) async {
    calls.add('log $date $mealType ${food.name} x$servings');
    lastLogged = food;
    if (hold != null) await hold!.future;
    if (failNext) { failNext = false; throw const ApiException('NETWORK_ERROR', 'offline'); }
    final saved = FoodEntry.pending(id: _ids++, food: food, mealType: mealType, servings: servings);
    days[date] = dayOf(date).withEntry(saved);
    return saved;
  }

  @override
  Future<void> deleteEntry(int id) async {
    calls.add('delete $id');
    if (hold != null) await hold!.future;
    if (failNext) { failNext = false; throw const ApiException('NETWORK_ERROR', 'offline'); }
    days.updateAll((_, d) => d.without(id));
  }

  @override
  Future<FoodSearchResult> search(String q) async => const FoodSearchResult(foods: [rice], fatsecretUnavailable: false);

  @override
  Future<List<Food>> recent() async {
    recentCalls++;
    return const [rice];
  }
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

  test('Undo after a day switch logs back to the day the entry came from', () async {
    final repo = FakeNutritionRepository();
    final c = _container(repo);
    final dates = c.read(nutritionDateProvider.notifier);
    dates.shift(-1);
    await c.read(nutritionDayProvider.future);
    await c.read(nutritionDayProvider.notifier).log(rice, mealType: 'dinner', servings: 1);
    final entry = c.read(nutritionDayProvider).value!.meals['dinner']!.single;
    await c.read(nutritionDayProvider.notifier).remove(entry);

    dates.shift(1);
    expect((await c.read(nutritionDayProvider.future)).date, '2026-10-14');
    await c.read(nutritionDayProvider.notifier)
        .log(entry.asFood(), mealType: entry.mealType, servings: entry.servings, date: '2026-10-13');
    expect(repo.calls, contains('log 2026-10-13 dinner Rice x1.0'));
    final shown = c.read(nutritionDayProvider).value!;
    expect(shown.date, '2026-10-14');
    expect(shown.entries, isEmpty, reason: "today's day is unchanged");
    expect(repo.dayOf('2026-10-13').meals['dinner'], hasLength(1));
  });

  test("following today asks for the server's today, and logs to the day it returned", () async {
    final repo = FakeNutritionRepository()..today = '2026-10-13'; // the phone's clock runs ahead
    final c = _container(repo); // 12:00 on the 14th in Manila, by the phone
    expect((await c.read(nutritionDayProvider.future)).date, '2026-10-13');
    expect(repo.calls, ['get today']);
    await c.read(nutritionDayProvider.notifier).log(rice, mealType: 'lunch', servings: 1);
    expect(repo.calls, contains('log 2026-10-13 lunch Rice x1.0'));
  });

  test('a failed delete after a day switch does not paint the entry into the new day', () async {
    final repo = FakeNutritionRepository();
    final c = _container(repo);
    c.read(nutritionDateProvider.notifier).shift(-1);
    await c.read(nutritionDayProvider.future);
    await c.read(nutritionDayProvider.notifier).log(rice, mealType: 'dinner', servings: 1);
    final entry = c.read(nutritionDayProvider).value!.meals['dinner']!.single;

    repo
      ..hold = Completer<void>()
      ..failNext = true;
    final removing = c.read(nutritionDayProvider.notifier).remove(entry);
    final failed = expectLater(removing, throwsA(isA<ApiException>()));
    c.read(nutritionDateProvider.notifier).shift(1);
    expect((await c.read(nutritionDayProvider.future)).date, '2026-10-14');
    repo.hold!.complete();
    await failed;
    expect(c.read(nutritionDayProvider).value!.entries, isEmpty);
  });

  test('log and remove throw while no day is loaded, so the caller can say so', () async {
    final c = _container(FakeNutritionRepository());
    final day = c.read(nutritionDayProvider.notifier); // starts the load; nothing has arrived yet
    expect(c.read(nutritionDayProvider).hasValue, isFalse);
    final logging = day.log(rice, mealType: 'lunch', servings: 1);
    final removing = day.remove(FoodEntry.pending(id: 5, food: rice, mealType: 'lunch', servings: 1));
    await expectLater(logging, throwsStateError);
    await expectLater(removing, throwsStateError);
  });

  test('a saved entry replaces its pending one even if the refresh after it fails', () async {
    final repo = FakeNutritionRepository();
    final c = _container(repo);
    await c.read(nutritionDayProvider.future);
    repo.failNextGet = true;
    await c.read(nutritionDayProvider.notifier).log(rice, mealType: 'lunch', servings: 1);
    expect(c.read(nutritionDayProvider).value!.meals['lunch']!.single.id, 100,
        reason: "the server's id, so its delete button works");
  });

  test('a delete refreshes recents', () async {
    final repo = FakeNutritionRepository();
    final c = _container(repo);
    c.listen(recentFoodsProvider, (_, _) {});
    await c.read(nutritionDayProvider.future);
    await c.read(nutritionDayProvider.notifier).log(rice, mealType: 'lunch', servings: 1);
    final entry = c.read(nutritionDayProvider).value!.meals['lunch']!.single;
    await c.read(recentFoodsProvider.future);
    final before = repo.recentCalls;
    await c.read(nutritionDayProvider.notifier).remove(entry);
    await c.read(recentFoodsProvider.future);
    expect(repo.recentCalls, before + 1);
  });
}
