import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/units.dart';

void main() {
  test('kilograms render as typed, without trailing zeros', () {
    expect(formatWeight(22.5, WeightUnit.kg), '22.5');
    expect(formatWeight(20, WeightUnit.kg), '20');
    expect(formatWeight(100, WeightUnit.kg), '100');
  });

  test('kilograms render as pounds to one decimal', () {
    // 22.5 / 0.45359237 = 49.6040..., and one pound is 0.45359237 kg by
    // definition -- so 45.359237 kg is exactly 100 lb. Both hand-derived:
    // an expectation computed with the same conversion would pass whatever
    // factor the code used.
    expect(formatWeight(22.5, WeightUnit.lb), '49.6');
    expect(formatWeight(45.359237, WeightUnit.lb), '100');
  });

  test('typed pounds are converted to kilograms for storage', () {
    expect(parseWeight('100', WeightUnit.lb), closeTo(45.359237, 1e-9));
    expect(parseWeight('22.5', WeightUnit.kg), 22.5);
  });

  // The round trip someone in pounds actually sees: type 50, the server
  // stores it in a DECIMAL(6,2) column, the app reads it back. Drift here
  // would show them a number they never typed.
  test('a weight typed in pounds reads back as the number typed', () {
    final typed = parseWeight('50', WeightUnit.lb)!;
    final stored = double.parse(typed.toStringAsFixed(2));
    expect(formatWeight(stored, WeightUnit.lb), '50');
  });

  test('an empty field is nothing recorded, never zero', () {
    expect(parseWeight('', WeightUnit.kg), isNull);
    expect(parseWeight('   ', WeightUnit.lb), isNull);
    expect(parseWeight('abc', WeightUnit.kg), isNull);
  });

  test('the API spelling round-trips, and an unknown one falls back to kg', () {
    expect(WeightUnit.fromApi('lb'), WeightUnit.lb);
    expect(WeightUnit.fromApi('kg'), WeightUnit.kg);
    expect(WeightUnit.fromApi(null), WeightUnit.kg);
    expect(WeightUnit.fromApi('stones'), WeightUnit.kg);
    expect(WeightUnit.lb.api, 'lb');
  });
}
