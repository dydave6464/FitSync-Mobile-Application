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

  group('dish photos', () {
    Map<String, dynamic> withPhoto(Object? photoUrl) => {
      ..._tinola,
      'food': {...(_tinola['food'] as Map<String, dynamic>), 'photoUrl': photoUrl},
    };
    MealSuggestions answer(List<Map<String, dynamic>> plates, {String? mediaBase}) => MealSuggestions.fromJson({
      'date': '2026-11-13', 'meal': 'lunch', 'state': 'fits', 'share': {'kcal': 650, 'proteinG': 40},
      'riceFood': _rice, 'suggestions': plates,
    }, mediaBase: mediaBase);

    test("the dish's photo is joined to the server's address", () {
      final s = answer([withPhoto('/storage/foods/a.jpg')], mediaBase: 'http://10.0.2.2:3000');
      expect(s.suggestions.single.food.photoUrl, 'http://10.0.2.2:3000/storage/foods/a.jpg');
    });

    test('without an address the photo is left as sent', () {
      expect(answer([withPhoto('/storage/foods/a.jpg')]).suggestions.single.food.photoUrl, '/storage/foods/a.jpg');
      expect(
        SuggestedFood.fromJson({...(_tinola['food'] as Map<String, dynamic>), 'photoUrl': '/storage/foods/b.png'}).photoUrl,
        '/storage/foods/b.png',
      );
    });

    test('a dish without a photo, or from an older server, has none', () {
      final s = answer([withPhoto(null), _egg], mediaBase: 'http://10.0.2.2:3000');
      expect(s.suggestions.map((p) => p.food.photoUrl), [null, null]);
    });

    test('rice never has one', () {
      final s = answer([withPhoto('/storage/foods/a.jpg')], mediaBase: 'http://10.0.2.2:3000');
      expect(s.suggestions.single.rice!.photoUrl, isNull);
      expect(s.riceFood!.photoUrl, isNull);
    });

    test('the photo stays with the dish when the rice changes', () {
      final s = answer([withPhoto('/storage/foods/a.jpg')], mediaBase: 'http://10.0.2.2:3000');
      final p = withRiceCups(s.suggestions.single, s.riceFood!, 2);
      expect(p.food.photoUrl, 'http://10.0.2.2:3000/storage/foods/a.jpg');
      expect(p.rice!.photoUrl, isNull);
    });
  });

  test('no_target and reached come without a share', () {
    expect(_read(state: 'no_target', share: null).state, SuggestionState.noTarget);
    final reached = _read(state: 'reached', share: null, plates: const [_egg]);
    expect(reached.state, SuggestionState.reached);
    expect(reached.share, isNull);
    expect(reached.suggestions.single.rice, isNull);
    expect(reached.suggestions.single.items.map((f) => f.name), ['Hard-boiled egg']);
  });

  test('skipped reads from the answer, and is 0 from a server that sends none', () {
    expect(_read().skipped, 0);
    final s = MealSuggestions.fromJson({
      'date': '2026-11-13', 'meal': 'lunch', 'state': 'no_target', 'share': null, 'suggestions': const [],
      'skipped': 4,
    });
    expect(s.skipped, 4);
  });

  test('the six food groups, in order, and their labels', () {
    expect(foodGroups, ['pork', 'beef', 'chicken', 'fish', 'shellfish', 'egg']);
    expect(foodGroups.map(foodGroupLabel), ['Pork', 'Beef', 'Chicken', 'Fish', 'Shrimp & shellfish', 'Egg']);
    expect(foodGroupLabel('tofu'), 'tofu');
  });

  test('a hidden dish reads its id, name and when it was hidden', () {
    final h = HiddenSuggestion.fromJson({'foodId': 10, 'name': 'Tinolang manok', 'hiddenAt': '2026-11-13T04:00:00.000Z'});
    expect(h.foodId, 10);
    expect(h.name, 'Tinolang manok');
    expect(h.hiddenAt, DateTime.utc(2026, 11, 13, 4));
  });

  test("Settings' meal preferences summary: the rice, then how many foods are avoided", () {
    expect(mealPrefsSummary(1, const []), '1 cup rice');
    expect(mealPrefsSummary(0, const ['pork', 'egg']), 'No rice · avoids 2');
    expect(mealPrefsSummary(1.5, const ['fish']), '1½ cups rice · avoids 1');
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

  group('rice cups', () {
    Map<String, dynamic> plate({Object? servings, Object? served}) => {
      ..._tinola,
      'rice': {..._rice, 'servings': ?servings},
      'servedWithRice': ?served,
    };

    test('reads the usual cups, White rice per cup, and each plate\'s cups', () {
      final s = MealSuggestions.fromJson({
        'date': '2026-11-13', 'meal': 'lunch', 'state': 'fits', 'share': {'kcal': 650, 'proteinG': 40},
        'riceCups': 1.5, 'riceFood': _rice,
        'suggestions': [plate(servings: 1.5, served: true)],
      });
      expect(s.riceCups, 1.5);
      expect(s.riceFood!.kcal, 206);
      expect(s.suggestions.single.riceCups, 1.5);
      expect(s.suggestions.single.servedWithRice, isTrue);
    });

    test('an older answer reads as 1 cup, rice served when it has rice', () {
      final s = _read(plates: [_tinola, _egg]);
      expect([s.riceCups, s.riceFood], [1.0, null]);
      expect(s.suggestions.map((p) => (p.riceCups, p.servedWithRice)), [(1.0, true), (1.0, false)]);
    });

    test('cups in words, as a row shows them and as a screen reader says them', () {
      expect([for (final c in [0.5, 1.0, 1.5, 2.0]) cupsLabel(c)], ['½ cup', '1 cup', '1½ cups', '2 cups']);
      expect([for (final c in [0.5, 1.0, 1.5, 2.0]) cupsSpoken(c)], ['half a cup', '1 cup', '1 and a half cups', '2 cups']);
      expect(riceNote(1.5), 'Plates will use 1½ cups from now on.');
      expect(riceNote(0), 'Plates will come without rice from now on.');
      expect(riceChoices, [0, 0.5, 1, 1.5, 2]);
    });

    test("a plate's title, line and spoken words say its own cups", () {
      final p = MealSuggestion.fromJson({
        'food': _tinola['food'], 'rice': {..._rice, 'kcal': 309, 'servings': 1.5},
        'total': {'kcal': 569, 'proteinG': 30.5, 'carbsG': 75.5, 'fatG': 14}, 'servedWithRice': true, 'highProtein': false,
      });
      expect(plateTitle(p), 'Tinolang manok + 1½ cups rice');
      expect(plateMeta(p).lead, '1 bowl + 1½ cups · 569 kcal');
      expect(plateSpoken(p), 'Tinolang manok with 1 and a half cups rice, 569 kilocalories, 31 grams protein');
    });

    test('withRiceCups: White rice scaled and the plate re-added, as the server rounds', () {
      final p = MealSuggestion.fromJson(plate(servings: 1, served: true));
      final rice = SuggestedFood.fromJson(_rice);
      final more = withRiceCups(p, rice, 1.5);
      expect([more.rice!.kcal, more.rice!.proteinG, more.rice!.carbsG, more.riceCups], [309, 4.5, 67.5, 1.5]);
      expect([more.total.kcal, more.total.proteinG, more.total.carbsG, more.total.fatG], [569, 30.5, 75.5, 14.0]);
      expect(more.servedWithRice, isTrue);
      final none = withRiceCups(p, rice, 0);
      expect(none.rice, isNull);
      expect([none.total.kcal, none.total.proteinG], [260, 26.0]);
      expect(none.servedWithRice, isTrue);
      // High protein follows the new total: 26 g of 260 kcal is 40%.
      expect(none.highProtein, isTrue);
    });
  });
}
