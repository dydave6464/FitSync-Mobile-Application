const mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];

String mealLabel(String mealType) => switch (mealType) {
  'breakfast' => 'Breakfast',
  'lunch' => 'Lunch',
  'dinner' => 'Dinner',
  _ => 'Snack',
};

/// The meal a "Log …" button offers at [instant], by the Manila clock:
/// 21:00–04:59 snack (a late-night meal is a snack), 05:00–09:59 breakfast,
/// 10:00–14:59 lunch, 15:00–20:59 dinner.
String mealForTime(DateTime instant) {
  final hour = instant.toUtc().add(const Duration(hours: 8)).hour;
  if (hour < 5) return 'snack';
  if (hour < 10) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 21) return 'dinner';
  return 'snack';
}

/// Atwater: what the server computes for a manual food.
int manualKcal(double proteinG, double carbsG, double fatG) =>
    (4 * proteinG + 4 * carbsG + 9 * fatG).round();

const _missingLabels = {
  'sex': 'sex',
  'dateOfBirth': 'birthday',
  'heightCm': 'height',
  'weightKg': 'weight',
  'activityLevel': 'activity level',
};

/// "Add your height & weight to see a target", or null when nothing is missing.
String? describeMissing(List<String> fields) {
  final words = [for (final f in fields) _missingLabels[f] ?? f];
  if (words.isEmpty) return null;
  final list = words.length == 1
      ? words.single
      : '${words.sublist(0, words.length - 1).join(', ')} & ${words.last}';
  return 'Add your $list to see a target';
}

double _d(Object? v) => (v as num).toDouble();
double _r2(double v) => (v * 100).round() / 100;

/// A food to log: per serving.
class Food {
  const Food({
    required this.source,
    this.id,
    this.externalId,
    required this.name,
    this.servingDesc,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  factory Food.fromJson(Map<String, dynamic> j) => Food(
    source: j['source'] as String,
    id: j['id'] as int?,
    externalId: j['externalId'] as String?,
    name: j['name'] as String,
    servingDesc: j['servingDesc'] as String?,
    kcal: (j['kcal'] as num).round(),
    proteinG: _d(j['proteinG']),
    carbsG: _d(j['carbsG']),
    fatG: _d(j['fatG']),
  );

  /// 'local', 'fatsecret' or 'manual'.
  final String source;
  final int? id;
  final String? externalId;
  final String name;
  final String? servingDesc;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  bool get isFatsecret => source == 'fatsecret';

  /// The `food` object POST /nutrition/entries takes. A FatSecret food is
  /// sent by id only: the server fetches its numbers itself.
  Map<String, dynamic> toRef() => switch (source) {
    'local' => {'source': 'local', 'id': id},
    'fatsecret' => {'source': 'fatsecret', 'externalId': externalId},
    _ => {
      'source': 'manual',
      'name': name,
      if (servingDesc != null) 'servingDesc': servingDesc,
      'proteinG': proteinG,
      'carbsG': carbsG,
      'fatG': fatG,
    },
  };
}

/// One logged item. Its numbers are totals (per serving × servings).
class FoodEntry {
  const FoodEntry({
    required this.id,
    required this.mealType,
    required this.name,
    this.servingDesc,
    required this.servings,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.source,
    this.foodId,
    this.externalId,
  });

  factory FoodEntry.fromJson(Map<String, dynamic> j) => FoodEntry(
    id: j['id'] as int,
    mealType: j['mealType'] as String,
    name: j['name'] as String,
    servingDesc: j['servingDesc'] as String?,
    servings: _d(j['servings']),
    kcal: (j['kcal'] as num).round(),
    proteinG: _d(j['proteinG']),
    carbsG: _d(j['carbsG']),
    fatG: _d(j['fatG']),
    source: j['source'] as String,
    foodId: j['foodId'] as int?,
    externalId: j['externalId'] as String?,
  );

  /// Shown at once while the save is in flight. [id] is negative so it can
  /// never collide with a server id.
  factory FoodEntry.pending({
    required int id,
    required Food food,
    required String mealType,
    required double servings,
  }) => FoodEntry(
    id: id,
    mealType: mealType,
    name: food.name,
    servingDesc: food.servingDesc,
    servings: servings,
    kcal: (food.kcal * servings).round(),
    proteinG: _r2(food.proteinG * servings),
    carbsG: _r2(food.carbsG * servings),
    fatG: _r2(food.fatG * servings),
    source: food.source,
    foodId: food.id,
    externalId: food.externalId,
  );

  final int id;
  final String mealType;
  final String name;
  final String? servingDesc;
  final double servings;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final String source;
  final int? foodId;
  final String? externalId;

  /// The per-serving food this entry came from, so Undo can log it again.
  Food asFood() => Food(
    source: source,
    id: foodId,
    externalId: externalId,
    name: name,
    servingDesc: servingDesc,
    kcal: (kcal / servings).round(),
    proteinG: _r2(proteinG / servings),
    carbsG: _r2(carbsG / servings),
    fatG: _r2(fatG / servings),
  );
}

class NutritionTarget {
  const NutritionTarget({required this.kcal, required this.proteinG, required this.carbsG, required this.fatG});

  factory NutritionTarget.fromJson(Map<String, dynamic> j) => NutritionTarget(
    kcal: (j['kcal'] as num).round(),
    proteinG: (j['proteinG'] as num).round(),
    carbsG: (j['carbsG'] as num).round(),
    fatG: (j['fatG'] as num).round(),
  );

  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
}

class MacroTotals {
  const MacroTotals({required this.kcal, required this.proteinG, required this.carbsG, required this.fatG});

  factory MacroTotals.fromJson(Map<String, dynamic> j) => MacroTotals(
    kcal: (j['kcal'] as num).round(),
    proteinG: _d(j['proteinG']),
    carbsG: _d(j['carbsG']),
    fatG: _d(j['fatG']),
  );

  factory MacroTotals.of(Iterable<FoodEntry> entries) {
    var kcal = 0;
    var p = 0.0, c = 0.0, f = 0.0;
    for (final e in entries) {
      kcal += e.kcal;
      p += e.proteinG;
      c += e.carbsG;
      f += e.fatG;
    }
    return MacroTotals(kcal: kcal, proteinG: p, carbsG: c, fatG: f);
  }

  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
}

class NutritionDay {
  const NutritionDay({
    required this.date,
    required this.target,
    required this.targetMissing,
    required this.totals,
    required this.meals,
  });

  factory NutritionDay.fromJson(Map<String, dynamic> j) {
    final meals = j['meals'] as Map<String, dynamic>;
    return NutritionDay(
      date: j['date'] as String,
      target: j['target'] == null ? null : NutritionTarget.fromJson(j['target'] as Map<String, dynamic>),
      targetMissing: (j['targetMissing'] as List).cast<String>(),
      totals: MacroTotals.fromJson(j['totals'] as Map<String, dynamic>),
      meals: {
        for (final m in mealTypes)
          m: [for (final e in (meals[m] as List? ?? const [])) FoodEntry.fromJson(e as Map<String, dynamic>)],
      },
    );
  }

  final String date;
  final NutritionTarget? target;
  final List<String> targetMissing;
  final MacroTotals totals;
  final Map<String, List<FoodEntry>> meals;

  Iterable<FoodEntry> get entries => meals.values.expand((e) => e);

  bool get hasFatsecret => entries.any((e) => e.source == 'fatsecret');

  NutritionDay _withMeals(Map<String, List<FoodEntry>> next) => NutritionDay(
    date: date,
    target: target,
    targetMissing: targetMissing,
    totals: MacroTotals.of(next.values.expand((e) => e)),
    meals: next,
  );

  NutritionDay withEntry(FoodEntry entry) => _withMeals({
    for (final m in mealTypes) m: [...meals[m]!, if (m == entry.mealType) entry],
  });

  NutritionDay without(int entryId) => _withMeals({
    for (final m in mealTypes) m: [for (final e in meals[m]!) if (e.id != entryId) e],
  });
}

class FoodSearchResult {
  const FoodSearchResult({required this.foods, required this.fatsecretUnavailable});

  final List<Food> foods;
  final bool fatsecretUnavailable;
}
