import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/activity/domain/step_readings.dart';

const _midnight = 1_000_000_000_000;
const _hour = 3_600_000;
const _boot = 900_000_000_000;

StepReading _r(int offsetHours, int steps, {int boot = _boot}) =>
    StepReading(atMs: _midnight + offsetHours * _hour, steps: steps, bootMs: boot);

void main() {
  test('first day: counted from the first reading after turning it on', () {
    final d = stepsSince([_r(1, 1000), _r(3, 1600)], _midnight);
    expect(d.steps, 600);
    expect(d.sinceTurnedOn, isTrue);
    expect(d.includesEarlierDays, isFalse);
  });

  test('today = latest - last reading before midnight', () {
    final d = stepsSince([_r(-5, 4000), _r(-2, 5000), _r(2, 5800), _r(4, 6200)], _midnight);
    expect(d.steps, 1200);
    expect(d.sinceTurnedOn, isFalse);
    expect(d.includesEarlierDays, isFalse);
  });

  test('unsorted readings are sorted first', () {
    final d = stepsSince([_r(4, 6200), _r(-2, 5000), _r(2, 5800)], _midnight);
    expect(d.steps, 1200);
  });

  test('a restart adds the new total on top', () {
    final d = stepsSince(
      [_r(-1, 5000), _r(1, 5400), _r(2, 300, boot: _boot + 7 * _hour)],
      _midnight,
    );
    expect(d.steps, 700);
  });

  test('a drop in the total also counts as a restart', () {
    final d = stepsSince([_r(-1, 5000), _r(1, 5400), _r(2, 100)], _midnight);
    expect(d.steps, 500);
  });

  test('a day without opening the app lands on the next day, flagged', () {
    final d = stepsSince([_r(-30, 5000), _r(1, 9000)], _midnight);
    expect(d.steps, 4000);
    expect(d.includesEarlierDays, isTrue);
  });

  test('nothing read today yet is zero', () {
    expect(stepsSince([_r(-2, 5000)], _midnight).steps, 0);
    expect(stepsSince(const [], _midnight).steps, 0);
    expect(stepsSince(const [], _midnight).sinceTurnedOn, isTrue);
  });

  test('pruning keeps the last reading before midnight and all of today', () {
    final kept = pruneReadings([_r(-30, 1), _r(-5, 2), _r(-2, 3), _r(1, 4), _r(2, 5)], _midnight);
    expect(kept.map((r) => r.steps), [3, 4, 5]);
  });

  test('a reading round-trips through JSON', () {
    final r = _r(1, 42);
    expect(StepReading.fromJson(r.toJson()).steps, 42);
    expect(StepReading.fromJson(r.toJson()).atMs, r.atMs);
    expect(StepReading.fromJson(r.toJson()).bootMs, r.bootMs);
  });
}
