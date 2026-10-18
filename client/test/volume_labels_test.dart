import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/sessions/domain/volume_labels.dart';

void main() {
  // A Sunday. Every expected date below was worked out by hand from it.
  final today = DateTime(2026, 10, 18);

  ({String axis, String full}) name(String period, int index, int count) =>
      volumeBucketName(
        period: period,
        index: index,
        count: count,
        fallback: 'server',
        today: today,
      );

  group('a week reads as days', () {
    test('the last bar is today', () {
      expect(name('week', 6, 7), (axis: 'Sun', full: 'Today'));
    });

    test('the first bar is six days back', () {
      expect(name('week', 0, 7), (axis: 'Mon', full: 'Mon, Oct 12'));
    });
  });

  group('a month reads as five-day spans', () {
    test('the last span ends today', () {
      expect(name('month', 5, 6), (axis: 'Oct 18', full: 'Oct 14 – Oct 18'));
    });

    test('the first span ends 25 days back', () {
      expect(name('month', 0, 6), (axis: 'Sep 23', full: 'Sep 19 – Sep 23'));
    });
  });

  group('a year reads as months', () {
    test('the last span ends today and is named by its month', () {
      expect(name('year', 11, 12), (axis: 'Oct', full: 'Sep 18 – Oct 18'));
    });

    test('every other month is labelled, counting back from now', () {
      // Twelve month names do not fit under twelve bars on a phone.
      expect(name('year', 10, 12).axis, '');
      expect(name('year', 10, 12).full, 'Aug 18 – Sep 17');
      expect(name('year', 9, 12).axis, isNotEmpty);
    });

    test('the first span reaches back into last year', () {
      expect(name('year', 0, 12).full, 'Oct 12 – Nov 11');
    });
  });

  test('a period it does not know keeps the server\'s label', () {
    expect(name('decade', 2, 5), (axis: 'server', full: 'server'));
  });
}
