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

/// One suggested plate: a dish, with 1 cup of white rice on a main meal.
class MealSuggestion {
  const MealSuggestion({required this.food, this.rice, required this.total, required this.highProtein});

  factory MealSuggestion.fromJson(Map<String, dynamic> j) => MealSuggestion(
    food: SuggestedFood.fromJson(j['food'] as Map<String, dynamic>),
    rice: j['rice'] == null ? null : SuggestedFood.fromJson(j['rice'] as Map<String, dynamic>),
    total: PlateTotal.fromJson(j['total'] as Map<String, dynamic>),
    highProtein: j['highProtein'] as bool,
  );

  final SuggestedFood food;
  final SuggestedFood? rice;
  final PlateTotal total;

  /// Protein brings 30% of the plate's calories or more.
  final bool highProtein;

  /// What Log plate saves, in order: the dish, then its rice.
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

/// Today's suggestions for one meal: up to three plates, best first.
class MealSuggestions {
  const MealSuggestions({
    required this.date,
    required this.meal,
    required this.state,
    this.share,
    required this.suggestions,
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
    );
  }

  /// The server's today, YYYY-MM-DD (Manila): the day Log plate logs to.
  final String date;

  /// breakfast, lunch, dinner or snack.
  final String meal;
  final SuggestionState state;
  final MealShare? share;
  final List<MealSuggestion> suggestions;
}

/// "1 bowl" from "1 bowl (350 g)": a serving without its weight, for a line
/// with no room to spare. "1 serving" when nothing is left.
String shortServing(String? desc) {
  final short = (desc ?? '').replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  return short.isEmpty ? '1 serving' : short;
}

/// The line under "Suggested for lunch", by state.
String suggestionHeading(MealSuggestions s) => switch (s.state) {
  SuggestionState.fits =>
    'Fits the ~${groupThousands(s.share!.kcal.toDouble())} kcal and ${s.share!.proteinG.round()} g protein '
        'left for ${s.meal}',
  SuggestionState.noTarget => 'Add your weight and height in Profile to fit these to your day.',
  SuggestionState.reached => "You've reached today's calories. Light options:",
};

/// "Tinolang manok + 1 cup rice", or the dish alone.
String plateTitle(MealSuggestion p) => p.rice == null ? p.food.name : '${p.food.name} + 1 cup rice';

/// A plate's protein in whole grams: the one figure the row, its spoken
/// label and Log to Lunch's plate total all show, so they never disagree.
int plateProteinG(MealSuggestion p) => p.total.proteinG.round();

/// A row's second line, in two parts so the protein figure can take the
/// Protein bar's colour: ("1 bowl + 1 cup · 466 kcal", "29 g protein").
({String lead, String protein}) plateMeta(MealSuggestion p) => (
  lead: '${shortServing(p.food.servingDesc)}${p.rice == null ? '' : ' + 1 cup'} · '
      '${groupThousands(p.total.kcal.toDouble())} kcal',
  protein: '${plateProteinG(p)} g protein',
);

/// A row as a screen reader says it: "Tinolang manok with 1 cup rice, 466
/// kilocalories, 29 grams protein", and "high protein" when it is.
String plateSpoken(MealSuggestion p) => [
  p.rice == null ? p.food.name : '${p.food.name} with 1 cup rice',
  '${p.total.kcal} kilocalories',
  '${plateProteinG(p)} grams protein',
  if (p.highProtein) 'high protein',
].join(', ');
