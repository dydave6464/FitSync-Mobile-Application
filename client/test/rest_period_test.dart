import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/sessions/domain/rest_period.dart';

final _t0 = DateTime(2026, 10, 16, 9);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

void main() {
  test('a rest started now has all of its seconds left', () {
    final rest = RestPeriod.start(_t0, 90);

    expect(rest.secondsLeft(_t0), 90);
    expect(rest.fractionLeft(_t0), 1.0);
    expect(rest.isOverAt(_t0), isFalse);
  });

  // The bug this replaces: a countdown that only moved on timer ticks lost
  // whatever time passed while the phone was locked.
  test('time left comes from the clock, however long since anyone looked', () {
    final rest = RestPeriod.start(_t0, 90);

    expect(rest.secondsLeft(_at(61000)), 29);
  });

  test('part of a second left still reads as a second', () {
    final rest = RestPeriod.start(_t0, 90);

    expect(rest.secondsLeft(_at(89800)), 1);
    expect(rest.isOverAt(_at(89800)), isFalse);
  });

  test('over at its end, and never negative after it', () {
    final rest = RestPeriod.start(_t0, 90);

    expect(rest.isOverAt(_at(90000)), isTrue);
    expect(rest.secondsLeft(_at(90000)), 0);
    expect(rest.secondsLeft(_at(200000)), 0);
    expect(rest.fractionLeft(_at(200000)), 0.0);
  });

  test('the ring empties in proportion', () {
    final rest = RestPeriod.start(_t0, 100);

    expect(rest.fractionLeft(_at(25000)), closeTo(0.75, 1e-9));
  });

  group('adjusted', () {
    test("+30s adds to the time left and grows the ring's total", () {
      // 10 s in: 80 left, +30 = 110, which is more than the 90 started with.
      final rest = RestPeriod.start(
        _t0,
        90,
      ).adjusted(30, _at(10000), maxSeconds: 600)!;

      expect(rest.secondsLeft(_at(10000)), 110);
      expect(rest.totalSeconds, 110);
      expect(rest.fractionLeft(_at(10000)), 1.0);
    });

    test('−30s takes from it and keeps the total', () {
      final rest = RestPeriod.start(
        _t0,
        90,
      ).adjusted(-30, _t0, maxSeconds: 600)!;

      expect(rest.secondsLeft(_t0), 60);
      expect(rest.totalSeconds, 90);
    });

    test('cutting it to nothing ends it', () {
      expect(
        RestPeriod.start(_t0, 20).adjusted(-30, _t0, maxSeconds: 600),
        isNull,
      );
      expect(
        RestPeriod.start(_t0, 30).adjusted(-30, _t0, maxSeconds: 600),
        isNull,
      );
    });

    test('never more than the longest rest allowed', () {
      final rest = RestPeriod.start(
        _t0,
        590,
      ).adjusted(30, _t0, maxSeconds: 600)!;

      expect(rest.secondsLeft(_t0), 600);
    });
  });
}
