import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/domain/meal_suggestion.dart';

const _rice = <String, dynamic>{
  'foodId': 1, 'name': 'White rice', 'servingDesc': '1 cup (160 g)', 'kcal': 206, 'proteinG': 3, 'carbsG': 45, 'fatG': 0,
};
const _tinola = <String, dynamic>{
  'food': {
    'foodId': 10, 'name': 'Tinolang manok', 'servingDesc': '1 bowl (350 g)', 'kcal': 260, 'proteinG': 26, 'carbsG': 8,
    'fatG': 14,
  },
  'rice': _rice,
  'total': {'kcal': 466, 'proteinG': 29, 'carbsG': 53, 'fatG': 14},
  'highProtein': false,
};
const _egg = <String, dynamic>{
  'food': {
    'foodId': 13, 'name': 'Hard-boiled egg', 'servingDesc': '1 large', 'kcal': 78, 'proteinG': 6.3, 'carbsG': 0.6,
    'fatG': 5.3,
  },
  'rice': null,
  'total': {'kcal': 78, 'proteinG': 6.3, 'carbsG': 0.6, 'fatG': 5.3},
  'highProtein': true,
};

MealSuggestions _read({
  String state = 'fits',
  Map<String, dynamic>? share = const {'kcal': 650, 'proteinG': 40},
  List<Map<String, dynamic>> plates = const [_tinola],
}) => MealSuggestions.fromJson({
  'date': '2026-11-09', 'meal': 'lunch', 'state': state, 'share': share, 'suggestions': plates,
});

void main() {
  test("reads the server's answer: the share and each plate", () {
    final s = _read();
    expect([s.date, s.meal, s.state], ['2026-11-09', 'lunch', SuggestionState.fits]);
    expect([s.share!.kcal, s.share!.proteinG], [650, 40.0]);
    final plate = s.suggestions.single;
    expect(plate.food.foodId, 10);
    expect(plate.food.servingDesc, '1 bowl (350 g)');
    expect(plate.rice!.name, 'White rice');
    expect([plate.total.kcal, plate.total.proteinG, plate.total.carbsG, plate.total.fatG], [466, 29.0, 53.0, 14.0]);
    expect(plate.highProtein, isFalse);
    expect(plate.items.map((f) => f.name), ['Tinolang manok', 'White rice']);
  });

  test('no_target and reached come without a share', () {
    expect(_read(state: 'no_target', share: null).state, SuggestionState.noTarget);
    final reached = _read(state: 'reached', share: null, plates: const [_egg]);
    expect(reached.state, SuggestionState.reached);
    expect(reached.share, isNull);
    expect(reached.suggestions.single.rice, isNull);
    expect(reached.suggestions.single.items.map((f) => f.name), ['Hard-boiled egg']);
  });

  test('an unknown state, or fits without its share, is refused', () {
    expect(() => _read(state: 'maybe'), throwsFormatException);
    expect(() => _read(share: null), throwsFormatException);
  });

  test('the heading says what the plates are for, by state', () {
    expect(suggestionHeading(_read()), 'Fits the ~650 kcal and 40 g protein left for lunch');
    expect(
      suggestionHeading(_read(share: const {'kcal': 1150, 'proteinG': 47.5})),
      'Fits the ~1,150 kcal and 48 g protein left for lunch',
    );
    expect(
      suggestionHeading(_read(state: 'no_target', share: null)),
      'Add your weight and height in Profile to fit these to your day.',
    );
    expect(suggestionHeading(_read(state: 'reached', share: null)), "You've reached today's calories. Light options:");
  });

  test("a plate's title, line and spoken words", () {
    final tinola = MealSuggestion.fromJson(_tinola);
    final egg = MealSuggestion.fromJson(_egg);
    expect(plateTitle(tinola), 'Tinolang manok + 1 cup rice');
    expect(plateTitle(egg), 'Hard-boiled egg');
    expect(plateMeta(tinola), (lead: '1 bowl + 1 cup · 466 kcal', protein: '29 g protein'));
    expect(plateMeta(egg), (lead: '1 large · 78 kcal', protein: '6 g protein'));
    expect(plateSpoken(tinola), 'Tinolang manok with 1 cup rice, 466 kilocalories, 29 grams protein');
    expect(plateSpoken(egg), 'Hard-boiled egg, 78 kilocalories, 6 grams protein, high protein');
  });

  test('a serving loses its weight in brackets', () {
    expect(shortServing('1 bowl (350 g)'), '1 bowl');
    expect(shortServing('1 medium fish, grilled (150 g edible)'), '1 medium fish, grilled');
    expect(shortServing('1 large'), '1 large');
    expect(shortServing('(100 g)'), '1 serving');
    expect(shortServing(null), '1 serving');
  });

  test('a suggested food logs as the FitSync food it is, one serving by its id', () {
    final food = MealSuggestion.fromJson(_tinola).food.toFood();
    expect(food.toRef(), {'source': 'local', 'id': 10});
    expect([food.name, food.servingDesc, food.kcal], ['Tinolang manok', '1 bowl (350 g)', 260]);
  });
}
