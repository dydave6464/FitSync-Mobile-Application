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
}) =>
    estimateDailyTargets(
      sex: sex,
      dateOfBirth: dateOfBirth,
      heightCm: heightCm,
      weightKg: weightKg,
      activityLevel: activityLevel,
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
}
