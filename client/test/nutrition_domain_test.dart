import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/domain/nutrition.dart';

Map<String, dynamic> _entry({
  int id = 1,
  String meal = 'lunch',
  String source = 'local',
  double servings = 2,
  double? fiberG,
  double? sugarG,
  double? sodiumMg,
}) => {
  'id': id, 'mealType': meal, 'name': 'Chicken adobo', 'servingDesc': '1 serving',
  'servings': servings, 'kcal': 640, 'proteinG': 56, 'carbsG': 8, 'fatG': 42, 'fiberG': fiberG,
  'sugarG': sugarG, 'sodiumMg': sodiumMg,
  'source': source, 'foodId': source == 'manual' ? null : 7,
  'externalId': source == 'fatsecret' ? 'fs-1' : null,
};

Map<String, dynamic> _day({List<Map<String, dynamic>> lunch = const []}) => {
  'date': '2026-10-14',
  'target': {'kcal': 1850, 'proteinG': 95, 'carbsG': 253, 'fatG': 51},
  'targetMissing': <String>[],
  'totals': {'kcal': 640, 'proteinG': 56, 'carbsG': 8, 'fatG': 42},
  'meals': {'breakfast': [], 'lunch': lunch, 'dinner': [], 'snack': []},
};

void main() {
  test('mealForTime follows Manila hours', () {
    // Manila = UTC+8.
    expect(mealForTime(DateTime.utc(2026, 10, 14, 1, 59)), 'breakfast'); // 09:59
    expect(mealForTime(DateTime.utc(2026, 10, 14, 2, 0)), 'lunch'); // 10:00
    expect(mealForTime(DateTime.utc(2026, 10, 14, 7, 0)), 'dinner'); // 15:00
    expect(mealForTime(DateTime.utc(2026, 10, 14, 13, 0)), 'snack'); // 21:00
    expect(mealForTime(DateTime.utc(2026, 10, 14, 17, 0)), 'snack'); // 01:00
    expect(mealForTime(DateTime.utc(2026, 10, 13, 20, 59)), 'snack'); // 04:59
    expect(mealForTime(DateTime.utc(2026, 10, 13, 21, 0)), 'breakfast'); // 05:00
  });

  test('manualKcal is 4-4-9, rounded', () {
    expect(manualKcal(2, 34, 6), 198);
    expect(manualKcal(0.3, 0, 0), 1);
  });

  test('manualKcal rounds each gram to 2 decimals first, as the server does', () {
    // Server: fat 0.0551 -> 0.06 g -> 0.54 kcal -> 1. Unrounded: 0.4959 -> 0.
    expect(manualKcal(0, 0, 0.0551), 1);
    // Server: fat 0.1449 -> 0.14 g; 4*4.3 + 4*44.5 + 9*0.14 = 196.46 -> 196.
    expect(manualKcal(4.3, 44.5, 0.1449), 196);
  });

  test('describeMissing names fields in plain words', () {
    expect(describeMissing(const []), isNull);
    expect(describeMissing(const ['weightKg']), 'Add your weight to see a target');
    expect(describeMissing(const ['heightCm', 'weightKg']), 'Add your height & weight to see a target');
    expect(
      describeMissing(const ['sex', 'dateOfBirth', 'activityLevel']),
      'Add your sex, birthday & activity level to see a target',
    );
  });

  test('a day parses, and withEntry/without keep totals in step', () {
    final day = NutritionDay.fromJson(_day(lunch: [_entry()]));
    expect(day.meals['lunch']!.single.name, 'Chicken adobo');
    expect(day.target!.kcal, 1850);
    final food = Food.fromJson(const {
      'id': 3, 'source': 'local', 'externalId': null, 'name': 'Rice', 'servingDesc': '1 cup',
      'kcal': 205, 'proteinG': 4.3, 'carbsG': 44.5, 'fatG': 0.4,
    });
    final added = day.withEntry(FoodEntry.pending(id: -1, food: food, mealType: 'lunch', servings: 2));
    expect(added.meals['lunch']!.length, 2);
    expect(added.totals.kcal, 640 + 410);
    expect(added.totals.carbsG, closeTo(8 + 89, 0.001));
    final removed = added.without(1);
    expect(removed.meals['lunch']!.single.id, -1);
    expect(removed.totals.kcal, 410);
  });

  test('toRef is what POST /nutrition/entries takes', () {
    Food f(String source) => Food.fromJson({
      'id': source == 'local' ? 3 : null, 'source': source,
      'externalId': source == 'fatsecret' ? 'fs-1' : null, 'name': 'Turon', 'servingDesc': null,
      'kcal': 198, 'proteinG': 2, 'carbsG': 34, 'fatG': 6,
    });
    expect(f('local').toRef(), {'source': 'local', 'id': 3});
    expect(f('fatsecret').toRef(), {'source': 'fatsecret', 'externalId': 'fs-1'});
    expect(f('manual').toRef(), {'source': 'manual', 'name': 'Turon', 'proteinG': 2.0, 'carbsG': 34.0, 'fatG': 6.0});
  });

  test('an entry turns back into its per-serving food (for Undo)', () {
    final manual = FoodEntry.fromJson(_entry(source: 'manual'));
    expect(manual.asFood().toRef(), {
      'source': 'manual', 'name': 'Chicken adobo', 'servingDesc': '1 serving',
      'proteinG': 28.0, 'carbsG': 4.0, 'fatG': 21.0,
    });
    expect(FoodEntry.fromJson(_entry(source: 'fatsecret')).asFood().toRef(),
        {'source': 'fatsecret', 'externalId': 'fs-1'});
    expect(FoodEntry.fromJson(_entry()).asFood().toRef(), {'source': 'local', 'id': 7});
  });

  test('hasFatsecret spots a FatSecret entry', () {
    expect(NutritionDay.fromJson(_day(lunch: [_entry()])).hasFatsecret, isFalse);
    expect(NutritionDay.fromJson(_day(lunch: [_entry(source: 'fatsecret')])).hasFatsecret, isTrue);
  });

  test('formatServings drops the decimal only when whole', () {
    expect(formatServings(1), '1');
    expect(formatServings(1.5), '1.5');
  });

  test('Food.fromJson reads fiberG, or null when absent', () {
    Map<String, dynamic> rice([Object? fiberG]) => {
      'id': 3, 'source': 'local', 'externalId': null, 'name': 'Rice', 'servingDesc': '1 cup',
      'kcal': 205, 'proteinG': 4.3, 'carbsG': 44.5, 'fatG': 0.4, 'fiberG': fiberG,
    };
    expect(Food.fromJson(rice(0.6)).fiberG, 0.6);
    expect(Food.fromJson(rice()).fiberG, isNull);
  });

  test('a manual Food.toRef includes fiberG only when known', () {
    const withFiber = Food(
      source: 'manual', name: 'Turon', kcal: 198, proteinG: 2, carbsG: 34, fatG: 6, fiberG: 4.0,
    );
    expect(withFiber.toRef(), {
      'source': 'manual', 'name': 'Turon', 'proteinG': 2.0, 'carbsG': 34.0, 'fatG': 6.0, 'fiberG': 4.0,
    });
    const noFiber = Food(source: 'manual', name: 'Turon', kcal: 198, proteinG: 2, carbsG: 34, fatG: 6);
    expect(noFiber.toRef(), {'source': 'manual', 'name': 'Turon', 'proteinG': 2.0, 'carbsG': 34.0, 'fatG': 6.0});
  });

  test('FoodEntry.fromJson reads a nullable fiberG', () {
    expect(FoodEntry.fromJson(_entry(fiberG: 3.2)).fiberG, 3.2);
    expect(FoodEntry.fromJson(_entry()).fiberG, isNull);
  });

  test('FoodEntry.pending multiplies fiber when known, and keeps null otherwise', () {
    final withFiber = Food.fromJson(const {
      'id': 3, 'source': 'local', 'externalId': null, 'name': 'Rice', 'servingDesc': '1 cup',
      'kcal': 205, 'proteinG': 4.3, 'carbsG': 44.5, 'fatG': 0.4, 'fiberG': 2.0,
    });
    expect(FoodEntry.pending(id: -1, food: withFiber, mealType: 'lunch', servings: 2).fiberG, 4.0);

    final noFiber = Food.fromJson(const {
      'id': 3, 'source': 'local', 'externalId': null, 'name': 'Rice', 'servingDesc': '1 cup',
      'kcal': 205, 'proteinG': 4.3, 'carbsG': 44.5, 'fatG': 0.4, 'fiberG': null,
    });
    expect(FoodEntry.pending(id: -1, food: noFiber, mealType: 'lunch', servings: 2).fiberG, isNull);
  });

  test("asFood divides fiber back, or null", () {
    expect(FoodEntry.fromJson(_entry(fiberG: 8.0, servings: 2)).asFood().fiberG, 4.0);
    expect(FoodEntry.fromJson(_entry()).asFood().fiberG, isNull);
  });

  test('MacroTotals.fromJson reads fiberG, defaulting a missing one to 0', () {
    expect(MacroTotals.fromJson(const {'kcal': 0, 'proteinG': 0, 'carbsG': 0, 'fatG': 0, 'fiberG': 5.5}).fiberG, 5.5);
    expect(MacroTotals.fromJson(const {'kcal': 0, 'proteinG': 0, 'carbsG': 0, 'fatG': 0}).fiberG, 0);
  });

  test('MacroTotals.of sums the known fiber and lets an unknown one add nothing', () {
    final known = FoodEntry.fromJson(_entry(fiberG: 2.0));
    final unknown = FoodEntry.fromJson(_entry(id: 2, fiberG: null));
    expect(MacroTotals.of([known, unknown]).fiberG, 2.0);
  });

  test('NutritionTarget.fromJson reads fiberG as an int', () {
    expect(
      NutritionTarget.fromJson(const {'kcal': 1850, 'proteinG': 95, 'carbsG': 253, 'fatG': 51, 'fiberG': 26}).fiberG,
      26,
    );
  });

  test('Food.fromJson reads sugarG and sodiumMg, or null when absent', () {
    Map<String, dynamic> rice([Object? sugarG, Object? sodiumMg]) => {
      'id': 3, 'source': 'local', 'externalId': null, 'name': 'Rice', 'servingDesc': '1 cup',
      'kcal': 205, 'proteinG': 4.3, 'carbsG': 44.5, 'fatG': 0.4, 'sugarG': sugarG, 'sodiumMg': sodiumMg,
    };
    final food = Food.fromJson(rice(0.1, 1.0));
    expect(food.sugarG, 0.1);
    expect(food.sodiumMg, 1.0);
    expect(Food.fromJson(rice()).sugarG, isNull);
    expect(Food.fromJson(rice()).sodiumMg, isNull);
  });

  test('a manual Food.toRef includes sugarG and sodiumMg only when known', () {
    const withBoth = Food(
      source: 'manual', name: 'Turon', kcal: 198, proteinG: 2, carbsG: 34, fatG: 6,
      sugarG: 9.7, sodiumMg: 124.0,
    );
    expect(withBoth.toRef(), {
      'source': 'manual', 'name': 'Turon', 'proteinG': 2.0, 'carbsG': 34.0, 'fatG': 6.0,
      'sugarG': 9.7, 'sodiumMg': 124.0,
    });
    const neither = Food(source: 'manual', name: 'Turon', kcal: 198, proteinG: 2, carbsG: 34, fatG: 6);
    expect(neither.toRef(), {'source': 'manual', 'name': 'Turon', 'proteinG': 2.0, 'carbsG': 34.0, 'fatG': 6.0});
  });

  test('FoodEntry.fromJson reads sugarG and sodiumMg as nullable', () {
    final entry = FoodEntry.fromJson(_entry(sugarG: 9.7, sodiumMg: 124.0));
    expect(entry.sugarG, 9.7);
    expect(entry.sodiumMg, 124.0);
    expect(FoodEntry.fromJson(_entry()).sugarG, isNull);
    expect(FoodEntry.fromJson(_entry()).sodiumMg, isNull);
  });

  test('FoodEntry.pending multiplies sugar (2dp) and sodium (1dp) by servings, or keeps null', () {
    final withBoth = Food.fromJson(const {
      'id': 3, 'source': 'local', 'externalId': null, 'name': 'Rice', 'servingDesc': '1 cup',
      'kcal': 205, 'proteinG': 4.3, 'carbsG': 44.5, 'fatG': 0.4, 'sugarG': 0.333, 'sodiumMg': 0.37,
    });
    final pending = FoodEntry.pending(id: -1, food: withBoth, mealType: 'lunch', servings: 2);
    expect(pending.sugarG, 0.67);
    expect(pending.sodiumMg, 0.7);

    final neither = Food.fromJson(const {
      'id': 3, 'source': 'local', 'externalId': null, 'name': 'Rice', 'servingDesc': '1 cup',
      'kcal': 205, 'proteinG': 4.3, 'carbsG': 44.5, 'fatG': 0.4, 'sugarG': null, 'sodiumMg': null,
    });
    final pendingNeither = FoodEntry.pending(id: -1, food: neither, mealType: 'lunch', servings: 2);
    expect(pendingNeither.sugarG, isNull);
    expect(pendingNeither.sodiumMg, isNull);
  });

  test('asFood divides sugar and sodium back, or null', () {
    final divided = FoodEntry.fromJson(_entry(sugarG: 8.0, sodiumMg: 250.0, servings: 2)).asFood();
    expect(divided.sugarG, 4.0);
    expect(divided.sodiumMg, 125.0);
    final none = FoodEntry.fromJson(_entry()).asFood();
    expect(none.sugarG, isNull);
    expect(none.sodiumMg, isNull);
  });

  test('MacroTotals.fromJson reads sugarG and sodiumMg, defaulting missing ones to 0', () {
    final full = MacroTotals.fromJson(const {
      'kcal': 0, 'proteinG': 0, 'carbsG': 0, 'fatG': 0, 'sugarG': 9.7, 'sodiumMg': 124.0,
    });
    expect(full.sugarG, 9.7);
    expect(full.sodiumMg, 124.0);
    final missing = MacroTotals.fromJson(const {'kcal': 0, 'proteinG': 0, 'carbsG': 0, 'fatG': 0});
    expect(missing.sugarG, 0);
    expect(missing.sodiumMg, 0);
  });

  test('MacroTotals.of sums the known sugar and sodium and lets an unknown one add nothing', () {
    final known = FoodEntry.fromJson(_entry(sugarG: 2.0, sodiumMg: 50.0));
    final unknown = FoodEntry.fromJson(_entry(id: 2, sugarG: null, sodiumMg: null));
    final totals = MacroTotals.of([known, unknown]);
    expect(totals.sugarG, 2.0);
    expect(totals.sodiumMg, 50.0);
  });
}
