import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/reminders/domain/plan_reminders.dart';
import 'package:fitsync/features/reminders/domain/reminders.dart';
import 'package:fitsync/features/routine/domain/routine.dart';

/// 06:00 on Friday 2026-09-25 in Manila (UTC+8).
final _now = DateTime.utc(2026, 9, 24, 22);

Habit _habit(
  int id,
  String title, {
  String? time,
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
}) => Habit(
  habitId: id,
  title: title,
  time: time,
  durationMin: null,
  weekdays: days,
  done: false,
);

/// A Manila wall-clock time as the UTC instant the planner returns.
DateTime _manila(int month, int day, int hour, int minute) => DateTime.utc(
  2026,
  month,
  day,
  hour,
  minute,
).subtract(const Duration(hours: 8));

const _habitsOnly = ReminderSettings(
  habitsEnabled: true,
  habitLeadMin: 15,
  workoutEnabled: false,
  workoutTime: '07:00',
  checkinEnabled: false,
  checkinTime: '07:00',
);

List<PlannedReminder> _plan({
  ReminderSettings settings = _habitsOnly,
  bool masterOn = true,
  List<Habit> habits = const [],
  List<int> trainingDays = const [],
  String? planName,
  TodayDone done = TodayDone.none,
  DateTime? now,
}) => planReminders(
  settings: settings,
  masterOn: masterOn,
  habits: habits,
  trainingDays: trainingDays,
  planName: planName,
  done: done,
  now: now ?? _now,
);

void main() {
  test('a timed habit reminds its lead time before, every day for a week', () {
    final r = _plan(habits: [_habit(1, 'Stretch', time: '06:30')]);
    expect(r.length, 7);
    expect(r.first.at, _manila(9, 25, 6, 15));
    expect(r.last.at, _manila(10, 1, 6, 15));
    expect(r.first.title, 'Stretch');
    expect(r.first.body, 'At 6:30 AM');
    expect(r.first.payload, 'routine');
  });

  test('at a lead of 0 it says now', () {
    final r = _plan(
      settings: const ReminderSettings(
        habitsEnabled: true,
        habitLeadMin: 0,
        workoutEnabled: false,
        workoutTime: '07:00',
        checkinEnabled: false,
        checkinTime: '07:00',
      ),
      habits: [_habit(1, 'Stretch', time: '06:30')],
    );
    expect(r.first.at, _manila(9, 25, 6, 30));
    expect(r.first.body, 'Now');
  });

  test('untimed habits never remind; a habit only reminds on its weekdays', () {
    final r = _plan(
      habits: [
        _habit(1, 'Read'),
        _habit(2, 'Swim', time: '18:00', days: const [1, 3]), // Mon, Wed
      ],
    );
    // Fri 25 .. Thu 1 contains Mon 28 and Wed 30.
    expect(r.map((x) => x.at), [
      _manila(9, 28, 17, 45),
      _manila(9, 30, 17, 45),
    ]);
  });

  test(
    "today's reminder is skipped for a habit already ticked, and only today's",
    () {
      final r = _plan(
        habits: [_habit(1, 'Walk', time: '18:00')],
        done: const TodayDone(habitIds: {1}, workout: false, checkin: false),
      );
      expect(r.first.at, _manila(9, 26, 17, 45));
      expect(r.length, 6);
    },
  );

  test('a time already past is not scheduled', () {
    // 06:00 now: a 05:30 habit's 05:15 reminder today has passed.
    final r = _plan(habits: [_habit(1, 'Early', time: '05:30')]);
    expect(r.first.at, _manila(9, 26, 5, 15));
  });

  test('workouts remind on training days when a plan is active', () {
    const s = ReminderSettings(
      habitsEnabled: false,
      habitLeadMin: 15,
      workoutEnabled: true,
      workoutTime: '17:00',
      checkinEnabled: false,
      checkinTime: '07:00',
    );
    final onDays = _plan(
      settings: s,
      planName: 'Upper/Lower',
      trainingDays: const [1, 5],
    );
    expect(onDays.map((x) => x.at), [
      _manila(9, 25, 17, 0),
      _manila(9, 28, 17, 0),
    ]);
    expect(onDays.first.title, 'Workout today');
    expect(onDays.first.body, 'Upper/Lower');
    expect(onDays.first.payload, 'routine');

    expect(
      _plan(settings: s, planName: 'P').length,
      7,
      reason: 'no days chosen: every day',
    );
    expect(
      _plan(settings: s, planName: null),
      isEmpty,
      reason: 'no active plan',
    );
    expect(
      _plan(
        settings: s,
        planName: 'P',
        done: const TodayDone(habitIds: {}, workout: true, checkin: false),
      ).first.at,
      _manila(9, 26, 17, 0),
      reason: 'already trained today',
    );
  });

  test('the check-in reminds every day unless done today', () {
    const s = ReminderSettings(
      habitsEnabled: false,
      habitLeadMin: 15,
      workoutEnabled: false,
      workoutTime: '07:00',
      checkinEnabled: true,
      checkinTime: '07:00',
    );
    final r = _plan(settings: s);
    expect(r.length, 7);
    expect(r.first.at, _manila(9, 25, 7, 0));
    expect(r.first.title, 'Morning check-in');
    expect(r.first.body, 'How did you sleep?');
    expect(r.first.payload, 'recovery');
    final done = _plan(
      settings: s,
      done: const TodayDone(habitIds: {}, workout: false, checkin: true),
    );
    expect(done.first.at, _manila(9, 26, 7, 0));
  });

  test('the master switch off schedules nothing', () {
    expect(
      _plan(masterOn: false, habits: [_habit(1, 'Stretch', time: '06:30')]),
      isEmpty,
    );
  });

  test('reminders are sorted, numbered, and capped at the soonest 60', () {
    final habits = [
      for (var i = 1; i <= 10; i++)
        _habit(i, 'H$i', time: '${(8 + i).toString().padLeft(2, '0')}:00'),
    ];
    final r = _plan(habits: habits);
    expect(r.length, maxReminders);
    expect(r.map((x) => x.id), List.generate(maxReminders, (i) => i));
    for (var i = 1; i < r.length; i++) {
      expect(r[i].at.isBefore(r[i - 1].at), isFalse);
    }
    // 70 candidates (10 habits x 7 days, 08:45..17:45 after the lead); the
    // soonest 60 are the first six days, so the last kept is Wed 30 at 17:45
    // and all of Thu 1 Oct is dropped.
    expect(r.last.at, _manila(9, 30, 17, 45));
  });

  test(
    'Manila dates, not UTC: late evening UTC is already tomorrow in Manila',
    () {
      // 17:00 UTC Thu 24 = 01:00 Fri 25 in Manila; a Friday-only habit at 07:00
      // is due in six hours, not in a week.
      final r = _plan(
        habits: [
          _habit(1, 'Fri', time: '07:00', days: const [5]),
        ],
        now: DateTime.utc(2026, 9, 24, 17),
      );
      expect(r.first.at, _manila(9, 25, 6, 45));
    },
  );
}
