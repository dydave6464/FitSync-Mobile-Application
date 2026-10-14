import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/domain/nutrition.dart';

Map<String, dynamic> _entry({int id = 1, String meal = 'lunch', String source = 'local', double servings = 2}) => {
  'id': id, 'mealType': meal, 'name': 'Chicken adobo', 'servingDesc': '1 serving',
  'servings': servings, 'kcal': 640, 'proteinG': 56, 'carbsG': 8, 'fatG': 42,
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
  });

  test('manualKcal is 4-4-9, rounded', () {
    expect(manualKcal(2, 34, 6), 198);
    expect(manualKcal(0.3, 0, 0), 1);
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
}
