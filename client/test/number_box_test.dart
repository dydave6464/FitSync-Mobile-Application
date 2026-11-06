import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/presentation/widgets/number_box.dart';

// L-60: the grams and sodium limits live in one place, which the error
// text, the log sheet and Add manually all go by.
void main() {
  test("the limits are the server's: 0-500 g and 0-20,000 mg", () {
    expect(maxGrams, 500);
    expect(maxSodiumMg, 20000);
  });

  test('in range: 0 to the limit, never below, above or NaN', () {
    expect([0.0, 250.0, 500.0].every(inGramsRange), isTrue);
    expect([-0.1, 500.1, double.nan].any(inGramsRange), isFalse);
    expect([0.0, 20000.0].every(inSodiumRange), isTrue);
    expect([-1.0, 20000.5, double.nan].any(inSodiumRange), isFalse);
  });

  test('the error text agrees with the range checks', () {
    expect(gramsError('500'), isNull);
    expect(gramsError('500.1'), 'Must be 0–500 g');
    expect(sodiumError('20000'), isNull);
    expect(sodiumError('20001'), 'Must be 0–20,000 mg');
    expect(gramsError('abc'), 'Enter a number');
    expect(gramsError(''), isNull);
  });
}
