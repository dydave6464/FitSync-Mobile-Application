import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/onboarding/domain/daily_targets.dart';

/// A fixed "now" so an age never shifts under the test.
final _today = DateTime(2024, 6, 16);

DailyTargets? _estimate({
  String? sex = 'male',
  String? dateOfBirth = '1998-03-14',
  double? heightCm = 175,
  double? weightKg = 72,
  String? activityLevel = 'light',
  String? mainGoal,
}) => estimateDailyTargets(
  sex: sex,
  dateOfBirth: dateOfBirth,
  heightCm: heightCm,
  weightKg: weightKg,
  activityLevel: activityLevel,
  mainGoal: mainGoal,
  today: _today,
);

void main() {
  test('Mifflin-St Jeor for a man, times the activity multiplier', () {
    // BMR = 10(72) + 6.25(175) - 5(26) + 5 = 1688.75, x1.375 = 2322 -> 2300.
    expect(_estimate()!.kcal, 2300);
  });

  test('the female constant lowers the same body by 166 kcal of BMR', () {
    // The only term that changes is +5 becoming -161: 1522.75 x1.375 = 2094.
    expect(_estimate(sex: 'female')!.kcal, 2100);
  });

  test('protein comes from body weight, not from the calorie total', () {
    // 1.6 g/kg on 72 kg = 115.2, to the nearest 5.
    expect(_estimate()!.proteinG, 115);
    expect(_estimate(weightKg: 90)!.proteinG, 145);
  });

  test('activity multiplies the whole day', () {
    final sedentary = _estimate(activityLevel: 'sedentary')!.kcal;
    final veryActive = _estimate(activityLevel: 'very_active')!.kcal;

    expect(sedentary, 2050);
    expect(veryActive, 3200);
    expect(veryActive, greaterThan(sedentary));
  });

  test('a birthday still to come this year has not been counted', () {
    // Born in December, so on 16 June the user is 25, not 26 — one year of
    // Mifflin's -5/year, which is the difference between two estimates.
    final younger = _estimate(dateOfBirth: '1998-12-01')!.kcal;
    final older = _estimate(dateOfBirth: '1998-03-14')!.kcal;

    expect(younger, greaterThan(older));
  });

  group('returns null rather than a confident guess', () {
    test('when a measurement is missing', () {
      expect(_estimate(weightKg: null), isNull);
      expect(_estimate(heightCm: null), isNull);
    });

    test('when the date of birth is missing or unreadable', () {
      expect(_estimate(dateOfBirth: null), isNull);
      expect(_estimate(dateOfBirth: 'not a date'), isNull);
    });

    test('when no activity level has been chosen', () {
      expect(_estimate(activityLevel: null), isNull);
    });

    test('when sex is unset, or a value the formula has no constant for', () {
      expect(_estimate(sex: null), isNull);
      // Profiles saved before the two-option segmented control still carry
      // this, and Mifflin-St Jeor has no term for it. Better no card than a
      // target computed as though the user had answered something they
      // deliberately declined to answer.
      expect(_estimate(sex: 'prefer_not_to_say'), isNull);
    });
  });

  // The food log's target (server/src/lib/nutrition-target.js) moves the
  // same maintenance by the main goal and never goes under a floor; this
  // must say the same number, or onboarding and Nutrition disagree.
  group('the main goal moves the target as the food log does', () {
    test('losing weight takes 500 off', () {
      expect(_estimate(mainGoal: 'lose_weight')!.kcal, 1800);
    });

    test('building muscle adds 250', () {
      expect(_estimate(mainGoal: 'build_muscle')!.kcal, 2550);
    });

    test('any other goal, or none, is maintenance', () {
      expect(_estimate(mainGoal: 'general_fitness')!.kcal, 2300);
      expect(_estimate()!.kcal, 2300);
    });

    test('never under 1,200 kcal for a woman or 1,500 for a man', () {
      // Sedentary, small and older: maintenance 1,100 for her, 1,300 for him,
      // so 500 off would go far under either floor.
      final female = _estimate(
        sex: 'female',
        heightCm: 150,
        weightKg: 45,
        dateOfBirth: '1960-01-01',
        activityLevel: 'sedentary',
        mainGoal: 'lose_weight',
      )!;
      final male = _estimate(
        heightCm: 150,
        weightKg: 45,
        dateOfBirth: '1960-01-01',
        activityLevel: 'sedentary',
        mainGoal: 'lose_weight',
      )!;
      expect(female.kcal, 1200);
      expect(male.kcal, 1500);
    });

    test('protein does not move with the goal', () {
      expect(_estimate(mainGoal: 'lose_weight')!.proteinG, 115);
    });
  });
}
