import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/sessions/presentation/open_workout_summary.dart';

void main() {
  final now = DateTime(2026, 10, 18, 15, 30);

  group('openedAgo', () {
    for (final (gap, want) in [
      (const Duration(seconds: 20), 'just now'),
      (const Duration(minutes: 1), '1 min ago'),
      (const Duration(minutes: 59, seconds: 59), '59 min ago'),
      (const Duration(hours: 1), '1 h ago'),
      (const Duration(hours: 23, minutes: 59), '23 h ago'),
      (const Duration(hours: 24), 'yesterday'),
      (const Duration(hours: 47), 'yesterday'),
      (const Duration(days: 2), '2 days ago'),
      (const Duration(days: 9), '9 days ago'),
    ]) {
      test('$gap before reads "$want"', () {
        expect(openedAgo(now.subtract(gap), now), want);
      });
    }

    test('a start time ahead of the phone clock reads "just now"', () {
      // The server stamps startedAt; a phone whose clock runs slow sees it a
      // little in the future, which is not "-3 min ago".
      expect(openedAgo(now.add(const Duration(minutes: 3)), now), 'just now');
    });

    test('an unknown start time says nothing', () {
      expect(openedAgo(null, now), isNull);
    });
  });
}
