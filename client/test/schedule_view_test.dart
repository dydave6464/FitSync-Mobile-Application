import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/reminders/domain/reminders.dart';
import 'package:fitsync/features/schedule/domain/calendar.dart';
import 'package:fitsync/features/schedule/domain/schedule_view.dart';

CalendarHabit _habit(int id, String title, String? time, {bool done = false}) =>
    CalendarHabit(habitId: id, title: title, time: time, done: done);

CalendarDay _day(
  String date, {
  CalendarWorkout? workout,
  List<CalendarHabit> habits = const [],
}) => CalendarDay(date: date, workout: workout, habits: habits);

ReminderSettings _settings({
  bool habits = true,
  int lead = 15,
  bool workout = false,
  String workoutTime = '07:00',
  bool checkin = false,
}) => ReminderSettings(
  habitsEnabled: habits,
  habitLeadMin: lead,
  workoutEnabled: workout,
  workoutTime: workoutTime,
  checkinEnabled: checkin,
  checkinTime: '07:00',
);

const _timed = ScheduleItem(
  date: '2026-09-24',
  title: 'Stretch',
  time: '06:30',
  done: false,
  isWorkout: false,
);
const _untimed = ScheduleItem(
  date: '2026-09-24',
  title: 'Walk',
  time: null,
  done: false,
  isWorkout: false,
);
const _workout = ScheduleItem(
  date: '2026-09-24',
  title: 'Upper/Lower',
  time: null,
  done: false,
  isWorkout: true,
);

void main() {
  group('dates', () {
    test('addDays crosses month and year ends', () {
      expect(addDays('2026-09-30', 1), '2026-10-01');
      expect(addDays('2026-12-31', 1), '2027-01-01');
      expect(addDays('2026-03-01', -1), '2026-02-28');
    });

    test('shiftMonth wraps the year', () {
      expect(shiftMonth((year: 2026, month: 12), 1), (year: 2027, month: 1));
      expect(shiftMonth((year: 2026, month: 1), -1), (year: 2025, month: 12));
      expect(monthOf('2026-09-24'), (year: 2026, month: 9));
    });

    test('a month grid is six Monday-first weeks from the Monday on or before the 1st', () {
      // 1 Sep 2026 is a Tuesday.
      final sep = monthGridDates((year: 2026, month: 9));
      expect(sep.length, 42);
      expect(sep.first, '2026-08-31');
      expect(sep.last, '2026-10-11');

      // 1 Jun 2026 is a Monday: the grid starts on the 1st itself.
      expect(monthGridDates((year: 2026, month: 6)).first, '2026-06-01');
    });

    test('a month starting on a Sunday takes the maximum 6-day offset', () {
      // 1 Nov 2026 is a Sunday.
      final nov = monthGridDates((year: 2026, month: 11));
      expect(nov.first, '2026-10-26');
      expect(nov.length, 42);
    });

    test('labels', () {
      expect(formatMonthTitle((year: 2026, month: 9)), 'September 2026');
      expect(formatDayLabel('2026-09-24'), 'Thu 24 Sep');
      expect(relativeDayLabel('2026-09-24', '2026-09-24'), 'Today');
      expect(relativeDayLabel('2026-09-25', '2026-09-24'), 'Tomorrow');
      expect(relativeDayLabel('2026-10-01', '2026-09-24'), 'Thu 1 Oct');
    });
  });

  group('items', () {
    test(
      "a day's items: timed habits, then the workout, then untimed habits",
      () {
        final items = dayItems(
          _day(
            '2026-09-24',
            workout: const CalendarWorkout(title: 'Upper/Lower', done: false),
            habits: [
              _habit(1, 'Mobility', '06:30', done: true),
              _habit(2, 'Stretch', '21:00'),
              _habit(3, 'Walk', null),
            ],
          ),
        );
        expect(items.map((i) => i.title), [
          'Mobility',
          'Stretch',
          'Upper/Lower',
          'Walk',
        ]);
        expect(items.map((i) => i.isWorkout), [false, false, true, false]);
        expect(items.first.done, isTrue);
        expect(items.every((i) => i.date == '2026-09-24'), isTrue);
      },
    );

    test('upcoming lists what is not done, from today on, in date order', () {
      final range = CalendarRange(
        today: '2026-09-24',
        days: [
          _day('2026-09-23', habits: [_habit(9, 'Yesterday', null)]),
          _day(
            '2026-09-24',
            workout: const CalendarWorkout(title: 'Upper/Lower', done: true),
            habits: [
              _habit(1, 'Mobility', '06:30', done: true),
              _habit(3, 'Walk', null),
            ],
          ),
          _day(
            '2026-09-25',
            workout: const CalendarWorkout(title: 'Upper/Lower', done: false),
            habits: [_habit(4, 'Swim', '07:00')],
          ),
        ],
      );
      expect(upcomingItems(range).map((i) => '${i.date} ${i.title}'), [
        '2026-09-24 Walk',
        '2026-09-25 Swim',
        '2026-09-25 Upper/Lower',
      ]);
    });

    test('lines', () {
      expect(itemLine(_timed), 'Stretch · 6:30 AM');
      expect(itemLine(_untimed), 'Walk · Any time');
      expect(itemLine(_workout), 'Workout · Upper/Lower');
      expect(upcomingLine(_timed, '2026-09-24'), 'Today · Stretch · 6:30 AM');
      expect(
        upcomingLine(_workout, '2026-09-23'),
        'Tomorrow · Workout · Upper/Lower',
      );
    });
  });

  group('reminders', () {
    test('a timed habit: minutes before, or at the time at lead 0', () {
      expect(
        reminderLine(_timed, (masterOn: true, settings: _settings())),
        'Reminder 15 min before',
      );
      expect(
        reminderLine(_timed, (masterOn: true, settings: _settings(lead: 0))),
        'Reminder at the time',
      );
    });

    test(
      'nothing for an untimed habit, habit reminders off, or the master off',
      () {
        expect(
          reminderLine(_untimed, (masterOn: true, settings: _settings())),
          isNull,
        );
        expect(
          reminderLine(_timed, (
            masterOn: true,
            settings: _settings(habits: false),
          )),
          isNull,
        );
        expect(
          reminderLine(_timed, (masterOn: false, settings: _settings())),
          isNull,
        );
      },
    );

    test('the workout: at its time when workout reminders are on', () {
      expect(
        reminderLine(_workout, (masterOn: true, settings: _settings())),
        isNull,
      );
      expect(
        reminderLine(_workout, (
          masterOn: true,
          settings: _settings(workout: true, workoutTime: '18:15'),
        )),
        'Reminder at 6:15 PM',
      );
      expect(
        reminderLine(_workout, (
          masterOn: false,
          settings: _settings(workout: true),
        )),
        isNull,
      );
    });

    test('on when the master switch and any one reminder are on', () {
      expect(remindersOn((masterOn: true, settings: _settings())), isTrue);
      expect(
        remindersOn((
          masterOn: true,
          settings: _settings(habits: false, checkin: true),
        )),
        isTrue,
      );
      expect(
        remindersOn((masterOn: true, settings: _settings(habits: false))),
        isFalse,
      );
      expect(remindersOn((masterOn: false, settings: _settings())), isFalse);
    });
  });

  group('dots', () {
    test('workout: none, planned, done', () {
      expect(workoutDot(_day('2026-09-24')), DotState.none);
      expect(
        workoutDot(
          _day(
            '2026-09-24',
            workout: const CalendarWorkout(title: 'W', done: false),
          ),
        ),
        DotState.planned,
      );
      expect(
        workoutDot(
          _day(
            '2026-09-24',
            workout: const CalendarWorkout(title: 'W', done: true),
          ),
        ),
        DotState.done,
      );
    });

    test('habits: none, due when none is done, done when any is', () {
      expect(habitsDot(_day('2026-09-24')), DotState.none);
      expect(
        habitsDot(_day('2026-09-24', habits: [_habit(1, 'A', null)])),
        DotState.planned,
      );
      expect(
        habitsDot(
          _day(
            '2026-09-24',
            habits: [_habit(1, 'A', null), _habit(2, 'B', null, done: true)],
          ),
        ),
        DotState.done,
      );
    });
  });
}
