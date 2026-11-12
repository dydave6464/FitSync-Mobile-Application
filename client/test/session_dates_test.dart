import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/sessions/domain/session_dates.dart';

void main() {
  // 10:00 on Friday, November 6, 2026, in Manila.
  final now = DateTime.utc(2026, 11, 6, 2);

  test('today and yesterday are said in words', () {
    expect(sessionDayLabel('2026-11-06', now: now), 'Today');
    expect(sessionDayLabel('2026-11-05', now: now), 'Yesterday');
  });

  test('an older day this year reads weekday, month and day', () {
    expect(sessionDayLabel('2026-11-04', now: now), 'Wed, Nov 4');
    expect(sessionDayLabel('2026-01-01', now: now), 'Thu, Jan 1');
  });

  test('another year carries its year', () {
    expect(sessionDayLabel('2025-12-31', now: now), 'Wed, Dec 31, 2025');
  });

  test("today is Manila's, not the phone's", () {
    // 23:30 UTC on the 5th is 07:30 on the 6th in Manila.
    final lateUtc = DateTime.utc(2026, 11, 5, 23, 30);
    expect(sessionDayLabel('2026-11-06', now: lateUtc), 'Today');
  });

  test('a date that does not parse is shown as it came', () {
    expect(sessionDayLabel('soon', now: now), 'soon');
  });
}
