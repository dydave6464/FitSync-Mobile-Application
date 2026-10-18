import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/numbers.dart';

void main() {
  test('groupThousands puts a comma every three digits', () {
    expect(groupThousands(0), '0');
    expect(groupThousands(999), '999');
    expect(groupThousands(1000), '1,000');
    expect(groupThousands(8053), '8,053');
    expect(groupThousands(1234567), '1,234,567');
  });

  test('groupThousands rounds to a whole number first', () {
    // A gram of barbell volume, or a milligram of sodium, is noise.
    expect(groupThousands(2399.6), '2,400');
    expect(groupThousands(12.4), '12');
  });
}
