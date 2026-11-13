import '../../../core/numbers.dart';
import 'nutrition.dart' show Food;

/// What `GET /api/v1/nutrition/suggestions` says about today (spec
/// 2026-11-09, "View Local Filipino Meal Suggestions").
enum SuggestionState {
  /// The plates fit what is left of today's target.
  fits,

  /// The profile has no target yet, so the plates are ranked by protein for
  /// their calories instead.
  noTarget,

  /// Under 100 kcal left today: light snacks only.
  reached,
}

double _d(Object? v) => (v as num).toDouble();

/// One food on a suggested plate, per serving: the dish, or its cup of rice.
class SuggestedFood {
  const SuggestedFood({
    required this.foodId,
    required this.name,
    this.servingDesc,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  factory SuggestedFood.fromJson(Map<String, dynamic> j) => SuggestedFood(
    foodId: (j['foodId'] as num).toInt(),
    name: j['name'] as String,
    servingDesc: j['servingDesc'] as String?,
    kcal: (j['kcal'] as num).round(),
    proteinG: _d(j['proteinG']),
    carbsG: _d(j['carbsG']),
    fatG: _d(j['fatG']),
  );

  final int foodId;
  final String name;
  final String? servingDesc;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// The FitSync food to log, one serving. Sent by its id, so the server
  /// logs its own numbers, as for any food picked from search.
  Food toFood() => Food(
    source: 'local',
    id: foodId,
    name: name,
    servingDesc: servingDesc,
    kcal: kcal,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
  );
}

/// A plate's kcal and macros: the dish and its rice added up.
class PlateTotal {
  const PlateTotal({required this.kcal, required this.proteinG, required this.carbsG, required this.fatG});

  factory PlateTotal.fromJson(Map<String, dynamic> j) => PlateTotal(
    kcal: (j['kcal'] as num).round(),
    proteinG: _d(j['proteinG']),
    carbsG: _d(j['carbsG']),
    fatG: _d(j['fatG']),
  );

  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
}

/// One suggested plate: a dish, with the user's usual rice on a main meal.
class MealSuggestion {
  const MealSuggestion({
    required this.food,
    this.rice,
    this.riceCups = 1,
    required this.total,
    required this.highProtein,
    this.servedWithRice = false,
  });

  factory MealSuggestion.fromJson(Map<String, dynamic> j) {
    final rice = j['rice'] as Map<String, dynamic>?;
    return MealSuggestion(
      food: SuggestedFood.fromJson(j['food'] as Map<String, dynamic>),
      rice: rice == null ? null : SuggestedFood.fromJson(rice),
      // A server older than round 1 sends neither: its rice is 1 cup, and
      // only a plate with rice was served with it.
      riceCups: (rice?['servings'] as num?)?.toDouble() ?? 1,
      total: PlateTotal.fromJson(j['total'] as Map<String, dynamic>),
      highProtein: j['highProtein'] as bool,
      servedWithRice: j['servedWithRice'] as bool? ?? rice != null,
    );
  }

  final SuggestedFood food;
  final SuggestedFood? rice;

  /// The cups of rice [rice] stands for (its numbers are for that amount).
  /// Meaningless without rice.
  final double riceCups;

  final PlateTotal total;

  /// Protein brings 30% of the plate's calories or more.
  final bool highProtein;

  /// The dish is served with rice on this meal and rice exists, so Log to
  /// Lunch offers a rice choice -- also when this plate came without it.
  final bool servedWithRice;

  /// What Log to Lunch lists, in order: the dish, then its rice.
  List<SuggestedFood> get items => [food, ?rice];
}

/// This meal's part of what is left today. Only with [SuggestionState.fits].
class MealShare {
  const MealShare({required this.kcal, required this.proteinG});

  factory MealShare.fromJson(Map<String, dynamic> j) =>
      MealShare(kcal: (j['kcal'] as num).round(), proteinG: _d(j['proteinG']));

  final int kcal;
  final double proteinG;
}

/// Today's suggestions for one meal: up to nine plates, best first.
class MealSuggestions {
  const MealSuggestions({
    required this.date,
    required this.meal,
    required this.state,
    this.share,
    required this.suggestions,
    this.riceCups = 1,
    this.riceFood,
    this.skipped = 0,
  });

  /// A state this app does not know, or "fits" without its share, is a
  /// [FormatException]: the section then says it couldn't load.
  factory MealSuggestions.fromJson(Map<String, dynamic> j) {
    final state = switch (j['state']) {
      'fits' => SuggestionState.fits,
      'no_target' => SuggestionState.noTarget,
      'reached' => SuggestionState.reached,
      final other => throw FormatException('Unknown suggestion state: $other'),
    };
    final share = j['share'] == null ? null : MealShare.fromJson(j['share'] as Map<String, dynamic>);
    if (state == SuggestionState.fits && share == null) {
      throw const FormatException('Suggestions that fit need their share.');
    }
    return MealSuggestions(
      date: j['date'] as String,
      meal: j['meal'] as String,
      state: state,
      share: share,
      suggestions: [
        for (final s in j['suggestions'] as List) MealSuggestion.fromJson(s as Map<String, dynamic>),
      ],
      riceCups: (j['riceCups'] as num?)?.toDouble() ?? 1,
      riceFood: j['riceFood'] == null ? null : SuggestedFood.fromJson(j['riceFood'] as Map<String, dynamic>),
      skipped: (j['skipped'] as num?)?.toInt() ?? 0,
    );
  }

  /// The server's today, YYYY-MM-DD (Manila): the day Log plate logs to.
  final String date;

  /// breakfast, lunch, dinner or snack.
  final String meal;
  final SuggestionState state;
  final MealShare? share;
  final List<MealSuggestion> suggestions;

  /// The user's usual cups of rice (0–2 in halves): what Log to Lunch starts
  /// from and what "from now on" is measured against.
  final double riceCups;

  /// White rice, one cup; null when the server has none to offer.
  final SuggestedFood? riceFood;

  /// Dishes left out because of the user's preferences (round 2): the page offers "Change meal preferences" when above 0.
  final int skipped;
}

/// The food groups a dish can contain and a user can avoid, in the order the
/// app lists them (spec 2026-11-13, round 2).
const foodGroups = ['pork', 'beef', 'chicken', 'fish', 'shellfish', 'egg'];

/// "Pork", "Shrimp & shellfish": a food group as the app shows it. A group
/// this app does not know is shown as sent.
String foodGroupLabel(String g) => switch (g) {
  'pork' => 'Pork',
  'beef' => 'Beef',
  'chicken' => 'Chicken',
  'fish' => 'Fish',
  'shellfish' => 'Shrimp & shellfish',
  'egg' => 'Egg',
  _ => g,
};

/// A dish the user asked not to be suggested ("Don't suggest this").
class HiddenSuggestion {
  const HiddenSuggestion({required this.foodId, required this.name, required this.hiddenAt});

  factory HiddenSuggestion.fromJson(Map<String, dynamic> j) => HiddenSuggestion(
    foodId: (j['foodId'] as num).toInt(),
    name: j['name'] as String,
    hiddenAt: DateTime.parse(j['hiddenAt'] as String),
  );

  final int foodId;
  final String name;
  final DateTime hiddenAt;
}

/// Settings' Meal preferences summary: "1 cup rice", "No rice · avoids 2".
String mealPrefsSummary(double riceCups, List<String> avoid) {
  final rice = riceCups == 0 ? 'No rice' : '${cupsLabel(riceCups)} rice';
  return avoid.isEmpty ? rice : '$rice · avoids ${avoid.length}';
}

/// "1 bowl" from "1 bowl (350 g)": a serving without its weight, for a line
/// with no room to spare. "1 serving" when nothing is left.
String shortServing(String? desc) {
  final short = (desc ?? '').replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  return short.isEmpty ? '1 serving' : short;
}

/// The rice a plate can take, in cups (spec 2026-11-13).
const riceChoices = <double>[0, 0.5, 1, 1.5, 2];

/// "½ cup", "1 cup", "1½ cups", "2 cups". For an amount above 0.
String cupsLabel(double cups) {
  final whole = cups.floor();
  final half = cups - whole >= 0.5;
  final number = whole == 0 ? '½' : '$whole${half ? '½' : ''}';
  return '$number ${cups > 1 ? 'cups' : 'cup'}';
}

/// "half a cup", "1 cup", "1 and a half cups", "2 cups": as a screen reader
/// says it. For an amount above 0.
String cupsSpoken(double cups) {
  final whole = cups.floor();
  final half = cups - whole >= 0.5;
  if (whole == 0) return 'half a cup';
  if (half) return '$whole and a half cups';
  return whole == 1 ? '1 cup' : '$whole cups';
}

/// What Log to Lunch says once the rice differs from the usual.
String riceNote(double cups) =>
    cups == 0 ? 'Plates will come without rice from now on.' : 'Plates will use ${cupsLabel(cups)} from now on.';

double _r1(double v) => (v * 10).roundToDouble() / 10;

/// [p] with [cups] cups of [riceFood] (one cup's numbers) in place of its own
/// rice: Log to Lunch's figures as the rice changes. Rounded as the server
/// rounds: kcal whole, grams to 1 decimal.
MealSuggestion withRiceCups(MealSuggestion p, SuggestedFood riceFood, double cups) {
  final rice = cups == 0
      ? null
      : SuggestedFood(
          foodId: riceFood.foodId,
          name: riceFood.name,
          servingDesc: riceFood.servingDesc,
          kcal: (riceFood.kcal * cups).round(),
          proteinG: _r1(riceFood.proteinG * cups),
          carbsG: _r1(riceFood.carbsG * cups),
          fatG: _r1(riceFood.fatG * cups),
        );
  final dish = p.food;
  final total = PlateTotal(
    kcal: dish.kcal + (rice?.kcal ?? 0),
    proteinG: _r1(dish.proteinG + (rice?.proteinG ?? 0)),
    carbsG: _r1(dish.carbsG + (rice?.carbsG ?? 0)),
    fatG: _r1(dish.fatG + (rice?.fatG ?? 0)),
  );
  return MealSuggestion(
    food: dish,
    rice: rice,
    riceCups: cups == 0 ? 1 : cups,
    total: total,
    highProtein: total.kcal > 0 && total.proteinG * 4 / total.kcal >= 0.3,
    servedWithRice: p.servedWithRice,
  );
}

/// The line under "Suggested for lunch", by state.
String suggestionHeading(MealSuggestions s) => switch (s.state) {
  SuggestionState.fits =>
    'Fits the ~${groupThousands(s.share!.kcal.toDouble())} kcal and ${s.share!.proteinG.round()} g protein '
        'left for ${s.meal}',
  SuggestionState.noTarget => 'Add your weight and height in Profile to fit these to your day.',
  SuggestionState.reached => "You've reached today's calories. Light options:",
};

/// "Tinolang manok + 1½ cups rice", or the dish alone.
String plateTitle(MealSuggestion p) =>
    p.rice == null ? p.food.name : '${p.food.name} + ${cupsLabel(p.riceCups)} rice';

/// A plate's protein in whole grams: the one figure the row, its spoken
/// label and Log to Lunch's plate total all show, so they never disagree.
int plateProteinG(MealSuggestion p) => p.total.proteinG.round();

/// A row's second line, in two parts so the protein figure can take the
/// Protein bar's colour: ("1 bowl + 1 cup · 466 kcal", "29 g protein").
({String lead, String protein}) plateMeta(MealSuggestion p) => (
  lead: '${shortServing(p.food.servingDesc)}${p.rice == null ? '' : ' + ${cupsLabel(p.riceCups)}'} · '
      '${groupThousands(p.total.kcal.toDouble())} kcal',
  protein: '${plateProteinG(p)} g protein',
);

/// A row as a screen reader says it: "Tinolang manok with 1 cup rice, 466
/// kilocalories, 29 grams protein", and "high protein" when it is.
String plateSpoken(MealSuggestion p) => [
  p.rice == null ? p.food.name : '${p.food.name} with ${cupsSpoken(p.riceCups)} rice',
  '${p.total.kcal} kilocalories',
  '${plateProteinG(p)} grams protein',
  if (p.highProtein) 'high protein',
].join(', ');
