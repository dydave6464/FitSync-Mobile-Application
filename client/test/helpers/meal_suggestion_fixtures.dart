import 'package:fitsync/features/nutrition/domain/meal_suggestion.dart';

const fixtureToday = '2026-10-14';

Map<String, dynamic> suggestedFoodJson(int id, String name, String serving, int kcal, num proteinG, num carbsG, num fatG) => {
  'foodId': id, 'name': name, 'servingDesc': serving, 'kcal': kcal, 'proteinG': proteinG, 'carbsG': carbsG, 'fatG': fatG,
};

/// White rice, one cup.
final riceJson = suggestedFoodJson(1, 'White rice', '1 cup (160 g)', 206, 3, 45, 0);

/// A plate as the server sends it: the dish, [cups] of rice (none for 0 or
/// [rice] false) and the two added up.
Map<String, dynamic> plateJson(
  Map<String, dynamic> food, {
  bool rice = true,
  double cups = 1,
  bool? servedWithRice,
  bool high = false,
}) {
  final withRice = rice && cups > 0;
  final scaled = withRice
      ? {
          ...riceJson,
          'servings': cups,
          'kcal': ((riceJson['kcal'] as num) * cups).round(),
          'proteinG': (riceJson['proteinG'] as num) * cups,
          'carbsG': (riceJson['carbsG'] as num) * cups,
          'fatG': (riceJson['fatG'] as num) * cups,
        }
      : null;
  final items = [food, ?scaled];
  num sum(String key) => items.fold<num>(0, (total, f) => total + (f[key] as num));
  return {
    'food': food,
    'rice': scaled,
    'total': {'kcal': sum('kcal'), 'proteinG': sum('proteinG'), 'carbsG': sum('carbsG'), 'fatG': sum('fatG')},
    'servedWithRice': servedWithRice ?? rice,
    'highProtein': high,
  };
}

final tinolaJson = suggestedFoodJson(10, 'Tinolang manok', '1 bowl (350 g)', 260, 26, 8, 14);
final sinigangJson = suggestedFoodJson(11, 'Sinigang na bangus (milkfish sour soup)', '1 bowl with broth (350 g)', 195, 23, 9, 7);
final bangusJson = suggestedFoodJson(12, 'Grilled bangus', '1 piece (150 g)', 206, 35, 0, 7);
final eggJson = suggestedFoodJson(13, 'Hard-boiled egg', '1 large', 78, 6.3, 0.6, 5.3);

MealSuggestions suggestionsAnswer(
  String state,
  List<Map<String, dynamic>> plates, {
  String meal = 'lunch',
  Map<String, dynamic>? share,
  double riceCups = 1,
  bool riceFood = true,
}) => MealSuggestions.fromJson({
  'date': fixtureToday, 'meal': meal, 'state': state, 'share': share, 'riceCups': riceCups,
  'riceFood': riceFood ? riceJson : null, 'suggestions': plates,
});
