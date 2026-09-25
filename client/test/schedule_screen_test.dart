import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/reminders/domain/reminders.dart';
import 'package:fitsync/features/reminders/presentation/providers.dart';
import 'package:fitsync/features/schedule/data/calendar_repository.dart';
import 'package:fitsync/features/schedule/domain/calendar.dart';
import 'package:fitsync/features/schedule/domain/schedule_view.dart';
import 'package:fitsync/features/schedule/presentation/providers.dart';
import 'package:fitsync/features/schedule/presentation/schedule_screen.dart';
import 'package:fitsync/features/schedule/presentation/widgets/month_grid.dart';

/// 10:00 on Thu 24 Sep 2026 in Manila.
final _now = DateTime.utc(2026, 9, 24, 2);

const _upperLower = CalendarWorkout(title: 'Upper/Lower', done: false);

final _fixture = <String, CalendarDay>{
  '2026-09-22': const CalendarDay(
    date: '2026-09-22',
    workout: CalendarWorkout(title: 'Upper/Lower', done: true),
    habits: [
      CalendarHabit(habitId: 1, title: 'Stretch', time: '06:30', done: true),
    ],
  ),
  '2026-09-24': const CalendarDay(
    date: '2026-09-24',
    workout: _upperLower,
    habits: [
      CalendarHabit(habitId: 2, title: 'Mobility', time: '06:30', done: true),
      CalendarHabit(habitId: 3, title: 'Stretch', time: '21:00', done: false),
      CalendarHabit(habitId: 4, title: 'Walk', time: null, done: false),
    ],
  ),
  '2026-09-25': const CalendarDay(
    date: '2026-09-25',
    workout: null,
    habits: [CalendarHabit(habitId: 5, title: 'Read', time: null, done: false)],
  ),
  '2026-09-28': const CalendarDay(
    date: '2026-09-28',
    workout: _upperLower,
    habits: [],
  ),
  '2026-09-29': const CalendarDay(
    date: '2026-09-29',
    workout: null,
    habits: [
      CalendarHabit(habitId: 6, title: 'Swim', time: '07:00', done: false),
    ],
  ),
};

/// Every date from..to, empty unless [days] names it.
CalendarRange _range(
  String from,
  String to, {
  String today = '2026-09-24',
  Map<String, CalendarDay> days = const {},
}) => CalendarRange(
  today: today,
  days: [
    for (var d = from; d.compareTo(to) <= 0; d = addDays(d, 1))
      days[d] ?? CalendarDay(date: d, workout: null, habits: const []),
  ],
);

class _FakeCalendarRepo implements CalendarRepository {
  _FakeCalendarRepo(this.answer, {Set<String>? failOnce})
    : failOnce = failOnce ?? {};

  final CalendarRange Function(String from, String to) answer;

  /// `from..to` spans that fail once, then answer.
  final Set<String> failOnce;
  final requests = <String>[];

  @override
  Future<CalendarRange> range(String from, String to) async {
    final span = '$from..$to';
    requests.add(span);
    if (failOnce.remove(span)) throw const ApiException('SERVER_ERROR', 'nope');
    return answer(from, to);
  }
}

/// Answers [failFrom] once, then throws on every request for it after that
/// -- a refetch (not the first load) failing.
class _FlakyCalendarRepo implements CalendarRepository {
  _FlakyCalendarRepo(this.answer, this.failFrom);

  final CalendarRange Function(String from, String to) answer;
  final String failFrom;
  final _counts = <String, int>{};

  @override
  Future<CalendarRange> range(String from, String to) async {
    final span = '$from..$to';
    final count = (_counts[span] ?? 0) + 1;
    _counts[span] = count;
    if (span == failFrom && count > 1) {
      throw const ApiException('SERVER_ERROR', 'nope');
    }
    return answer(from, to);
  }
}

class _Profile extends ProfileNotifier {
  _Profile(this.masterOn);

  final bool masterOn;

  @override
  Future<Profile> build() async => Profile(
    userId: 1,
    email: 'a@example.com',
    fullName: 'A',
    onboardingCompleted: true,
    isPremium: false,
    notificationsEnabled: masterOn,
    equipment: const [],
    injuries: const [],
  );
}

class _Settings extends ReminderSettingsController {
  _Settings(this.settings);

  final ReminderSettings settings;

  @override
  Future<ReminderSettings> build() async => settings;
}

/// Answers [first] once, then throws on every rebuild after that -- a
/// refetch (not the first load) failing.
class _FlakySettings extends ReminderSettingsController {
  _FlakySettings(this.first);

  final ReminderSettings first;
  int _calls = 0;

  @override
  Future<ReminderSettings> build() async {
    _calls += 1;
    if (_calls == 1) return first;
    throw const ApiException('SERVER_ERROR', 'nope');
  }
}

const _grid = '2026-08-31..2026-10-11';
const _week = '2026-09-24..2026-09-30';

Future<_FakeCalendarRepo> _pump(
  WidgetTester tester, {
  DateTime? now,
  CalendarRange Function(String from, String to)? answer,
  bool masterOn = true,
  ReminderSettings settings = ReminderSettings.defaults,
  Set<String>? failOnce,
}) async {
  // Tall enough that the grid and the whole list are built at once.
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = _FakeCalendarRepo(
    answer ?? (from, to) => _range(from, to, days: _fixture),
    failOnce: failOnce,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        calendarRepositoryProvider.overrideWithValue(repo),
        profileProvider.overrideWith(() => _Profile(masterOn)),
        reminderSettingsProvider.overrideWith(() => _Settings(settings)),
      ],
      child: MaterialApp(home: ScheduleScreen(now: () => now ?? _now)),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets(
    'opens on the current month and asks for it and the coming week',
    (tester) async {
      final repo = await _pump(tester);

      expect(find.text('Schedule'), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      expect(repo.requests, containsAll([_grid, _week]));
    },
  );

  testWidgets("the server's today decides the month", (tester) async {
    // 20:00 on 30 Sep in Manila by the phone; the server already says 1 Oct.
    final repo = await _pump(
      tester,
      now: DateTime.utc(2026, 9, 30, 12),
      answer: (from, to) => _range(from, to, today: '2026-10-01'),
    );

    expect(find.text('October 2026'), findsOneWidget);
    expect(repo.requests, contains('2026-09-28..2026-11-08'));
  });

  testWidgets('prev and next move the month and ask for its range', (
    tester,
  ) async {
    final repo = await _pump(tester);

    await tester.tap(find.byKey(const Key('schedule.next')));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(repo.requests, contains('2026-09-28..2026-11-08'));

    await tester.tap(find.byKey(const Key('schedule.prev')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule.prev')));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
    expect(repo.requests, contains('2026-07-27..2026-09-06'));
  });

  testWidgets('upcoming lists what is left, in order, with its reminders', (
    tester,
  ) async {
    await _pump(tester);

    const order = [
      'Today · Stretch · 9:00 PM',
      'Today · Workout · Upper/Lower',
      'Today · Walk · Any time',
      'Tomorrow · Read · Any time',
      'Mon 28 Sep · Workout · Upper/Lower',
      'Tue 29 Sep · Swim · 7:00 AM',
    ];
    for (final line in order) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    for (var i = 1; i < order.length; i++) {
      expect(
        _y(tester, order[i]),
        greaterThan(_y(tester, order[i - 1])),
        reason: order[i],
      );
    }
    expect(find.textContaining('Mobility'), findsNothing, reason: 'done');

    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Reminders on'), findsOneWidget);
    // Defaults: habit reminders 15 min before; workout reminders off.
    expect(find.text('Reminder 15 min before'), findsNWidgets(2));
    expect(find.textContaining('Reminder at'), findsNothing);
  });

  testWidgets('with the master switch off: Reminders off, no reminder lines', (
    tester,
  ) async {
    await _pump(tester, masterOn: false);

    expect(find.text('Reminders off'), findsOneWidget);
    expect(find.textContaining('Reminder '), findsNothing);
  });

  testWidgets('workout reminders on: the workout rows say when', (
    tester,
  ) async {
    await _pump(
      tester,
      settings: const ReminderSettings(
        habitsEnabled: false,
        habitLeadMin: 15,
        workoutEnabled: true,
        workoutTime: '07:00',
        checkinEnabled: false,
        checkinTime: '07:00',
      ),
    );

    expect(find.text('Reminders on'), findsOneWidget);
    expect(find.text('Reminder at 7:00 AM'), findsNWidgets(2));
    expect(find.text('Reminder 15 min before'), findsNothing);
  });

  testWidgets('an empty week says so', (tester) async {
    await _pump(tester, answer: (from, to) => _range(from, to));

    expect(find.text('Nothing coming up this week.'), findsOneWidget);
  });

  testWidgets('a past day shows what was done', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('schedule.day.2026-09-22')));
    await tester.pumpAndSettle();

    expect(find.text('Tue 22 Sep'), findsOneWidget);
    expect(find.text('Upcoming'), findsNothing);
    expect(find.text('Stretch · 6:30 AM'), findsOneWidget);
    expect(find.text('Workout · Upper/Lower'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(
      tester
          .widget<ScheduleDayCell>(
            find.byKey(const Key('schedule.day.2026-09-22')),
          )
          .selected,
      isTrue,
    );
  });

  testWidgets('a past day with nothing done, and an empty future day', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('schedule.day.2026-09-23')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing logged this day.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('schedule.day.2026-09-27')));
    await tester.pumpAndSettle();
    expect(find.text('Sun 27 Sep'), findsOneWidget);
    expect(find.text('Nothing planned.'), findsOneWidget);
  });

  testWidgets('today shows everything, the done items marked', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('schedule.day.2026-09-24')));
    await tester.pumpAndSettle();

    expect(find.text('Thu 24 Sep'), findsOneWidget);
    for (final line in [
      'Mobility · 6:30 AM',
      'Stretch · 9:00 PM',
      'Workout · Upper/Lower',
      'Walk · Any time',
    ]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(find.byIcon(Icons.check_circle), findsOneWidget, reason: 'Mobility');
  });

  testWidgets('Back to upcoming, or a second tap, returns to Upcoming', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('schedule.day.2026-09-25')));
    await tester.pumpAndSettle();
    expect(find.text('Read · Any time'), findsOneWidget);

    await tester.tap(find.byKey(const Key('schedule.upcoming')));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming'), findsOneWidget);

    await tester.tap(find.byKey(const Key('schedule.day.2026-09-25')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule.day.2026-09-25')));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming'), findsOneWidget);
  });

  testWidgets("the grid's error and Retry leave the list showing", (
    tester,
  ) async {
    await _pump(tester, failOnce: {_grid});

    expect(find.text("Couldn't load this month"), findsOneWidget);
    expect(find.text('Today · Walk · Any time'), findsOneWidget);
    expect(
      find.byKey(const Key('schedule.dot.workout.2026-09-22')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('schedule.grid.retry')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load this month"), findsNothing);
    expect(
      find.byKey(const Key('schedule.dot.workout.2026-09-22')),
      findsOneWidget,
    );
  });

  testWidgets("the list's error and Retry leave the grid showing", (
    tester,
  ) async {
    await _pump(tester, failOnce: {_week});

    expect(find.text("Couldn't load what's coming up"), findsOneWidget);
    expect(
      find.byKey(const Key('schedule.dot.workout.2026-09-22')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('schedule.list.retry')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load what's coming up"), findsNothing);
    expect(find.text('Today · Walk · Any time'), findsOneWidget);
  });

  testWidgets(
    'a reminder settings refetch that errors hides the tag and lines, not stale ones',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            calendarRepositoryProvider.overrideWithValue(
              _FakeCalendarRepo((from, to) => _range(from, to, days: _fixture)),
            ),
            profileProvider.overrideWith(() => _Profile(true)),
            reminderSettingsProvider.overrideWith(
              () => _FlakySettings(ReminderSettings.defaults),
            ),
          ],
          child: MaterialApp(home: ScheduleScreen(now: () => _now)),
        ),
      );
      await tester.pumpAndSettle();

      // Sanity: reminders show while the settings are good.
      expect(find.text('Reminders on'), findsOneWidget);
      expect(find.text('Reminder 15 min before'), findsNWidgets(2));

      // A refetch fails; the settings provider keeps its old value
      // (Riverpod 3's AsyncError.copyWithPrevious) but is now in error.
      ProviderScope.containerOf(tester.element(find.byType(ScheduleScreen)))
          .invalidate(reminderSettingsProvider);
      await tester.pumpAndSettle();

      expect(find.text('Reminders on'), findsNothing);
      expect(find.text('Reminders off'), findsNothing);
      expect(find.textContaining('Reminder '), findsNothing);
      // The Upcoming rows themselves are unaffected.
      expect(find.text('Today · Walk · Any time'), findsOneWidget);
    },
  );

  testWidgets(
    "a tapped day gives way to Upcoming if the grid's refetch errors",
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            calendarRepositoryProvider.overrideWithValue(
              _FlakyCalendarRepo(
                (from, to) => _range(from, to, days: _fixture),
                _grid,
              ),
            ),
            profileProvider.overrideWith(() => _Profile(true)),
            reminderSettingsProvider.overrideWith(
              () => _Settings(ReminderSettings.defaults),
            ),
          ],
          child: MaterialApp(home: ScheduleScreen(now: () => _now)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('schedule.day.2026-09-25')));
      await tester.pumpAndSettle();
      expect(find.text('Read · Any time'), findsOneWidget);

      // The grid's span reloads and this time fails.
      ProviderScope.containerOf(tester.element(find.byType(ScheduleScreen)))
          .invalidate(calendarProvider((from: '2026-08-31', to: '2026-10-11')));
      await tester.pumpAndSettle();

      expect(find.text('Nothing planned.'), findsNothing);
      expect(find.text('Nothing logged this day.'), findsNothing);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text("Couldn't load this month"), findsOneWidget);
    },
  );
}
