const mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];

String mealLabel(String mealType) => switch (mealType) {
  'breakfast' => 'Breakfast',
  'lunch' => 'Lunch',
  'dinner' => 'Dinner',
  _ => 'Snack',
};

/// The meal the Nutrition tab suggests at [instant] -- the Add row it
/// highlights -- by the Manila clock:
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

/// Atwater: what the server computes for a manual food. Like the server, it
/// rounds each gram to 2 decimals first, so the preview never differs.
int manualKcal(double proteinG, double carbsG, double fatG) =>
    (4 * _r2(proteinG) + 4 * _r2(carbsG) + 9 * _r2(fatG)).round();

/// 1.0 -> "1", 1.5 -> "1.5": how a servings count reads on screen.
String formatServings(double servings) =>
    servings == servings.roundToDouble() ? servings.toStringAsFixed(0) : servings.toString();

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
double _r1(double v) => (v * 10).round() / 10;

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
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
    this.group,
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
    fiberG: j['fiberG'] == null ? null : _d(j['fiberG']),
    sugarG: j['sugarG'] == null ? null : _d(j['sugarG']),
    sodiumMg: j['sodiumMg'] == null ? null : _d(j['sodiumMg']),
    group: j['group'] as String?,
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
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;

  /// The food's type in search (a key of [foodGroupLabels]), or null for an
  /// online food, one without a type, or one not from a search.
  final String? group;

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
      if (fiberG != null) 'fiberG': fiberG,
      if (sugarG != null) 'sugarG': sugarG,
      if (sodiumMg != null) 'sodiumMg': sodiumMg,
    },
  };
}

/// The search's food types as headings, in the server's order.
const foodGroupLabels = {
  'home': 'Home-cooked',
  'fruit_veg': 'Fruits & vegetables',
  'bread_kakanin': 'Breads & kakanin',
  'canned_instant': 'Canned & instant',
  'drink': 'Drinks',
  'street': 'Street food',
  'snack_sweet': 'Snacks & sweets',
  'fast_food': 'Fast food',
  'condiment': 'Sauces & condiments',
};

/// A food's heading in search: its type, or "More foods" for an online food
/// or one without a type (the server lists those last). Names no source.
String foodGroupLabel(Food food) => (food.isFatsecret ? null : foodGroupLabels[food.group]) ?? 'More foods';

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
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
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
    fiberG: j['fiberG'] == null ? null : _d(j['fiberG']),
    sugarG: j['sugarG'] == null ? null : _d(j['sugarG']),
    sodiumMg: j['sodiumMg'] == null ? null : _d(j['sodiumMg']),
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
    fiberG: food.fiberG == null ? null : _r2(food.fiberG! * servings),
    sugarG: food.sugarG == null ? null : _r2(food.sugarG! * servings),
    sodiumMg: food.sodiumMg == null ? null : _r1(food.sodiumMg! * servings),
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
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;
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
    fiberG: fiberG == null ? null : _r2(fiberG! / servings),
    sugarG: sugarG == null ? null : _r2(sugarG! / servings),
    sodiumMg: sodiumMg == null ? null : _r1(sodiumMg! / servings),
  );
}

class NutritionTarget {
  const NutritionTarget({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
  });

  factory NutritionTarget.fromJson(Map<String, dynamic> j) => NutritionTarget(
    kcal: (j['kcal'] as num).round(),
    proteinG: (j['proteinG'] as num).round(),
    carbsG: (j['carbsG'] as num).round(),
    fatG: (j['fatG'] as num).round(),
    fiberG: (j['fiberG'] as num? ?? 0).round(),
  );

  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int fiberG;
}

class MacroTotals {
  const MacroTotals({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.sugarG,
    required this.sodiumMg,
  });

  factory MacroTotals.fromJson(Map<String, dynamic> j) => MacroTotals(
    kcal: (j['kcal'] as num).round(),
    proteinG: _d(j['proteinG']),
    carbsG: _d(j['carbsG']),
    fatG: _d(j['fatG']),
    fiberG: j['fiberG'] == null ? 0 : _d(j['fiberG']),
    sugarG: j['sugarG'] == null ? 0 : _d(j['sugarG']),
    sodiumMg: j['sodiumMg'] == null ? 0 : _d(j['sodiumMg']),
  );

  factory MacroTotals.of(Iterable<FoodEntry> entries) {
    var kcal = 0;
    var p = 0.0, c = 0.0, f = 0.0, fb = 0.0, sg = 0.0, na = 0.0;
    for (final e in entries) {
      kcal += e.kcal;
      p += e.proteinG;
      c += e.carbsG;
      f += e.fatG;
      fb += e.fiberG ?? 0;
      sg += e.sugarG ?? 0;
      na += e.sodiumMg ?? 0;
    }
    return MacroTotals(kcal: kcal, proteinG: p, carbsG: c, fatG: f, fiberG: fb, sugarG: sg, sodiumMg: na);
  }

  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sugarG;
  final double sodiumMg;
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

  /// [entry] in place of the one with its id, where that one stood.
  NutritionDay replacing(FoodEntry entry) => _withMeals({
    for (final m in mealTypes) m: [for (final e in meals[m]!) e.id == entry.id ? entry : e],
  });
}

class FoodSearchResult {
  const FoodSearchResult({required this.foods, required this.fatsecretUnavailable});

  final List<Food> foods;
  final bool fatsecretUnavailable;
}
