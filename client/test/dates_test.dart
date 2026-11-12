import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/dates.dart';

void main() {
  // P-2: one day label for nutrition, sessions and the weigh-in sheet.
  group('calendarDayLabel', () {
    final today = DateTime(2026, 11, 6);

    test('today and yesterday are said in words', () {
      expect(calendarDayLabel(DateTime(2026, 11, 6), today), 'Today');
      expect(calendarDayLabel(DateTime(2026, 11, 5), today), 'Yesterday');
    });

    test('an older day this year reads weekday, month and day', () {
      expect(calendarDayLabel(DateTime(2026, 11, 4), today), 'Wed, Nov 4');
      expect(calendarDayLabel(DateTime(2026, 1, 1), today), 'Thu, Jan 1');
    });

    test('another year carries its year after a comma', () {
      expect(
        calendarDayLabel(DateTime(2025, 11, 4), today),
        'Tue, Nov 4, 2025',
      );
    });

    test('yesterday across a new year is still Yesterday', () {
      expect(
        calendarDayLabel(DateTime(2025, 12, 31), DateTime(2026, 1, 1)),
        'Yesterday',
      );
    });

    test('only the calendar day counts, not the clock', () {
      expect(
        calendarDayLabel(DateTime(2026, 11, 5, 23, 59), DateTime(2026, 11, 6)),
        'Yesterday',
      );
      expect(
        calendarDayLabel(DateTime.utc(2026, 11, 6), DateTime(2026, 11, 6, 8)),
        'Today',
      );
    });

    test('a day across a clock change is still one day back', () {
      // Local midnights 23 or 25 hours apart must not change the answer.
      expect(
        calendarDayLabel(DateTime(2026, 3, 8), DateTime(2026, 3, 9)),
        'Yesterday',
      );
      expect(
        calendarDayLabel(DateTime(2026, 11, 1), DateTime(2026, 11, 2)),
        'Yesterday',
      );
    });
  });
}
