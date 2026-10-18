import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/sessions/domain/volume_labels.dart';

void main() {
  // A Sunday. Every expected date below was worked out by hand from it.
  final today = DateTime(2026, 10, 18);

  ({String axis, String full}) name(
    String period,
    int index,
    int count, {
    DateTime? on,
  }) => volumeBucketName(
    period: period,
    index: index,
    count: count,
    fallback: 'server',
    today: on ?? today,
  );

  group('a week reads as days', () {
    test('the last bar is today', () {
      expect(name('week', 6, 7), (axis: 'Sun', full: 'Today'));
    });

    test('the first bar is six days back', () {
      expect(name('week', 0, 7), (axis: 'Mon', full: 'Mon, Oct 12'));
    });

    test('a week across a clock change keeps every day', () {
      // Counted back in local time, a day where the clocks went forward is
      // 23 hours long, and the week came out "Sat, Mon": Sunday vanished.
      // Run under TZ=America/New_York to see it; this is March 8 there.
      final dst = DateTime(2026, 3, 10);
      expect(
        [for (var i = 0; i < 7; i++) name('week', i, 7, on: dst).axis],
        ['Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue'],
      );
      expect(name('week', 4, 7, on: dst).full, 'Sun, Mar 8');
    });
  });

  group('a month reads as five-day spans', () {
    test('the last span ends today', () {
      expect(name('month', 5, 6), (axis: 'Oct 18', full: 'Oct 14 – Oct 18'));
    });

    test('the first span ends 25 days back', () {
      expect(name('month', 0, 6), (axis: 'Sep 23', full: 'Sep 19 – Sep 23'));
    });

    test('a span across a clock change is still five days', () {
      final dst = DateTime(2026, 3, 10);
      expect(name('month', 5, 6, on: dst).full, 'Mar 6 – Mar 10');
    });
  });

  group('a year reads as months', () {
    test('the last span ends today and is named by its middle', () {
      expect(name('year', 11, 12), (axis: 'Oct', full: 'Sep 18 – Oct 18'));
    });

    test('a span is named by the month most of it falls in', () {
      // On October 2 the last span runs September 2 to October 2: September,
      // not the two days of October it ends on.
      expect(name('year', 11, 12, on: DateTime(2026, 10, 2)).axis, 'Sep');
    });

    test('every other month is labelled, counting back from now', () {
      // Twelve month names do not fit under twelve bars on a phone.
      expect(name('year', 10, 12).axis, '');
      expect(name('year', 10, 12).full, 'Aug 18 – Sep 17');
      expect(
        [for (var i = 1; i < 12; i += 2) name('year', i, 12).axis],
        ['Nov', 'Jan', 'Mar', 'Jun', 'Aug', 'Oct'],
      );
    });

    test('the first span starts where the year does, last year', () {
      // The server's window is the last 365 days, so the oldest span is cut
      // short at its start; and a span in another year says which.
      expect(name('year', 0, 12).full, 'Oct 19 – Nov 11, 2025');
    });
  });

  test("a period it does not know keeps the server's label", () {
    expect(name('decade', 2, 5), (axis: 'server', full: 'server'));
  });
}
