import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/all_habits_screen.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';
import 'package:fitsync/features/routine/presentation/routine_screen.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/reminders/presentation/providers.dart';
import 'package:fitsync/features/schedule/domain/calendar.dart';
import 'package:fitsync/features/schedule/presentation/providers.dart';
import 'package:fitsync/features/schedule/presentation/schedule_screen.dart';

import 'helpers/a11y.dart' show contrast;
import 'settings_screen_test.dart'
    show DefaultReminderSettings, FakeProfileNotifier;

const _mobility = Habit(
  habitId: 1,
  title: 'Mobility',
  time: '06:30',
  durationMin: null,
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  done: true,
);

const _walk = Habit(
  habitId: 2,
  title: 'Walk',
  time: null,
  durationMin: null,
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  done: false,
);

const _workout = RoutineWorkout(title: 'Upper Body', done: false);

const _fixtureDay = RoutineDay(
  date: '2026-09-24',
  habits: [_mobility, _walk],
  workout: _workout,
);

/// A `RoutineRepository` double: a chosen day to load (or a load failure),
/// and the ability to fail the next check/uncheck.
class _FakeRoutineRepo implements RoutineRepository {
  _FakeRoutineRepo(this.day);

  RoutineDay day;
  Object? failLoad;
  bool failNextCheck = false;
  String failCode = 'VALIDATION_ERROR';
  int checkCalls = 0;
  int uncheckCalls = 0;

  @override
  Future<RoutineDay> today() async {
    if (failLoad != null) throw failLoad!;
    return day;
  }

  Future<void> _maybeFail() async {
    if (failNextCheck) {
      failNextCheck = false;
      throw ApiException(failCode, 'nope');
    }
  }

  @override
  Future<void> check(int habitId, {String? date}) async {
    checkCalls++;
    await _maybeFail();
  }

  @override
  Future<void> uncheck(int habitId, {String? date}) async {
    uncheckCalls++;
    await _maybeFail();
  }

  @override
  Future<List<Habit>> all() async => const [];
  @override
  Future<Habit> add(HabitDraft draft) async => throw UnimplementedError();
  @override
  Future<Habit> edit(int habitId, HabitDraft draft) async =>
      throw UnimplementedError();
  @override
  Future<void> remove(int habitId) async => throw UnimplementedError();
}

Widget _harness(
  _FakeRoutineRepo repo, {
  VoidCallback? onOpenPlan,
  bool dark = false,
}) => ProviderScope(
  overrides: [routineRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: dark ? fsDarkTheme() : fsLightTheme(),
    home: RoutineScreen(onOpenPlan: onOpenPlan),
  ),
);

/// The drawn 24 dp square inside a tick box.
BoxDecoration _boxOf(WidgetTester tester, Key key) =>
    tester
            .widget<Container>(
              find.descendant(
                of: find.byKey(key),
                matching: find.byWidgetPredicate(
                  (w) => w is Container && w.decoration is BoxDecoration,
                ),
              ),
            )
            .decoration!
        as BoxDecoration;

void main() {
  testWidgets('rows are ordered timed habits, then untimed by title', (
    tester,
  ) async {
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    final mobilityY = tester.getTopLeft(find.text('Mobility')).dy;
    final upperBodyY = tester.getTopLeft(find.text('Upper Body')).dy;
    final walkY = tester.getTopLeft(find.text('Walk')).dy;

    expect(mobilityY, lessThan(upperBodyY));
    expect(upperBodyY, lessThan(walkY));
  });

  testWidgets('the header ring shows the tally and what is left', (
    tester,
  ) async {
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('2 left today'), findsOneWidget);
  });

  testWidgets('the header reads all done when everything is ticked', (
    tester,
  ) async {
    final repo = _FakeRoutineRepo(
      const RoutineDay(
        date: '2026-09-24',
        habits: [
          Habit(
            habitId: 1,
            title: 'Mobility',
            time: '06:30',
            durationMin: null,
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            done: true,
          ),
          Habit(
            habitId: 2,
            title: 'Walk',
            time: null,
            durationMin: null,
            weekdays: [1, 2, 3, 4, 5, 6, 7],
            done: true,
          ),
        ],
        workout: RoutineWorkout(title: 'Upper Body', done: true),
      ),
    );
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('All done for today'), findsOneWidget);
  });

  testWidgets('a ticked row is struck through, its text not faded (PT-5)', (
    tester,
  ) async {
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    // No fade over the text: Opacity took it below AA.
    expect(
      find.ancestor(of: find.text('Mobility'), matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('6:30 AM'), matching: find.byType(Opacity)),
      findsNothing,
    );
    // The icon tile still steps back.
    final tileFade = tester.widget<Opacity>(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Mobility'),
              matching: find.byType(Row),
            ),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(tileFade.opacity, lessThan(1));

    final title = tester.widget<Text>(find.text('Mobility'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
    expect(title.style?.color, FsTokens.light.text2);

    final walkTitle = tester.widget<Text>(find.text('Walk'));
    expect(walkTitle.style?.decoration, TextDecoration.none);
    expect(walkTitle.style?.color, FsTokens.light.text);
  });

  for (final dark in [false, true]) {
    testWidgets('a ticked row reads at 4.5:1 (${dark ? 'dark' : 'light'})', (
      tester,
    ) async {
      final repo = _FakeRoutineRepo(_fixtureDay);
      await tester.pumpWidget(_harness(repo, dark: dark));
      await tester.pumpAndSettle();
      final t = dark ? FsTokens.dark : FsTokens.light;

      for (final text in ['Mobility', '6:30 AM']) {
        final color = tester.widget<Text>(find.text(text)).style!.color!;
        expect(
          contrast(color, t.surface),
          greaterThanOrEqualTo(4.5),
          reason: text,
        );
      }
    });
  }

  testWidgets('tapping a tick box ticks the habit and updates the header', (
    tester,
  ) async {
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routine.tick.2')));
    await tester.pumpAndSettle();

    expect(repo.checkCalls, 1);
    expect(find.text('2/3'), findsOneWidget);
    final walkTitle = tester.widget<Text>(find.text('Walk'));
    expect(walkTitle.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('a failed tick reverts and shows a snackbar', (tester) async {
    final repo = _FakeRoutineRepo(_fixtureDay)..failNextCheck = true;
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routine.tick.2')));
    await tester.pumpAndSettle();

    final walkTitle = tester.widget<Text>(find.text('Walk'));
    expect(walkTitle.style?.decoration, TextDecoration.none);
    expect(find.text("Couldn't save that. Try again."), findsOneWidget);
  });

  testWidgets(
    'a DAY_CHANGED failure shows a refreshed-day snackbar, not the generic one',
    (tester) async {
      final repo = _FakeRoutineRepo(_fixtureDay)
        ..failNextCheck = true
        ..failCode = 'DAY_CHANGED';
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine.tick.2')));
      await tester.pumpAndSettle();

      expect(
        find.text('A new day has started — your routine has refreshed.'),
        findsOneWidget,
      );
      expect(find.text("Couldn't save that. Try again."), findsNothing);
    },
  );

  testWidgets(
    'tapping the workout tick box opens the plan, like the rest of the row',
    (tester) async {
      var opened = false;
      final repo = _FakeRoutineRepo(_fixtureDay);
      await tester.pumpWidget(_harness(repo, onOpenPlan: () => opened = true));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine.workout.tick')));
      await tester.pumpAndSettle();

      expect(opened, isTrue);
      expect(repo.checkCalls, 0);
      expect(repo.uncheckCalls, 0);
    },
  );

  testWidgets('tapping the workout row opens the plan', (tester) async {
    var opened = false;
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(_harness(repo, onOpenPlan: () => opened = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routine.workout')));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets('tapping a habit opens the sheet to edit it', (tester) async {
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routine.habit.2')));
    await tester.pumpAndSettle();

    expect(find.text('Edit habit'), findsOneWidget);
  });

  testWidgets('tapping add opens the sheet for a new habit', (tester) async {
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routine.add')));
    await tester.pumpAndSettle();

    expect(find.text('New habit'), findsOneWidget);
  });

  testWidgets('an empty day invites adding a habit', (tester) async {
    final repo = _FakeRoutineRepo(
      const RoutineDay(date: '2026-09-24', habits: [], workout: null),
    );
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('Nothing on your routine today'), findsOneWidget);
    expect(find.byKey(const Key('routine.empty.add')), findsOneWidget);
  });

  testWidgets('a failed load shows a retry button', (tester) async {
    final repo = _FakeRoutineRepo(_fixtureDay)
      ..failLoad = const ApiException('SERVER_ERROR', 'Something broke.');
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routine.retry')), findsOneWidget);
  });

  testWidgets('the list icon opens every habit', (tester) async {
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routine.all')));
    await tester.pumpAndSettle();

    expect(find.byType(AllHabitsScreen), findsOneWidget);
  });

  testWidgets('the calendar icon opens the Schedule', (tester) async {
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routineRepositoryProvider.overrideWithValue(repo),
          calendarProvider.overrideWith(
            (ref, span) async =>
                const CalendarRange(today: '2026-09-24', days: []),
          ),
          profileProvider.overrideWith(() => FakeProfileNotifier([])),
          reminderSettingsProvider.overrideWith(
            () => DefaultReminderSettings(),
          ),
        ],
        child: const MaterialApp(home: RoutineScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routine.schedule')));
    await tester.pumpAndSettle();

    expect(find.byType(ScheduleScreen), findsOneWidget);
  });

  group('tick box (PT-1)', () {
    testWidgets('a habit tick box is a named checkbox with its state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final repo = _FakeRoutineRepo(_fixtureDay);
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byKey(const Key('routine.tick.2'))),
        isSemantics(
          label: 'Walk',
          hasCheckedState: true,
          isChecked: false,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('routine.tick.1'))),
        isSemantics(label: 'Mobility', hasCheckedState: true, isChecked: true),
      );
      handle.dispose();
    });

    testWidgets('tick boxes are 48 dp targets', (tester) async {
      final repo = _FakeRoutineRepo(_fixtureDay);
      await tester.pumpWidget(_harness(repo, onOpenPlan: () {}));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byKey(const Key('routine.tick.2')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      // The prototype's square is still drawn at 24 dp.
      final drawn = tester.getSize(
        find.descendant(
          of: find.byKey(const Key('routine.tick.2')),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration,
          ),
        ),
      );
      expect(drawn, const Size(24, 24));
    });

    testWidgets('the screen meets the tap-target and label guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final repo = _FakeRoutineRepo(_fixtureDay);
      await tester.pumpWidget(_harness(repo, onOpenPlan: () {}));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    for (final dark in [false, true]) {
      testWidgets('an unticked box outline is at least 3:1 '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        final repo = _FakeRoutineRepo(_fixtureDay);
        await tester.pumpWidget(_harness(repo, dark: dark));
        await tester.pumpAndSettle();

        final t = dark ? FsTokens.dark : FsTokens.light;
        final border = _boxOf(tester, const Key('routine.tick.2')).border!;
        final side = (border as Border).top;
        expect(side.color, t.control);
        expect(contrast(side.color, t.surface), greaterThanOrEqualTo(3));
      });
    }

    testWidgets('the workout box shows its state, not a checkbox', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final repo = _FakeRoutineRepo(_fixtureDay);
      await tester.pumpWidget(_harness(repo, onOpenPlan: () {}));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(
        find.byKey(const Key('routine.workout.tick')),
      );
      expect(node.label, 'Not finished yet');
      expect(
        node.getSemanticsData().flagsCollection.isChecked,
        CheckedState.none,
      );
      handle.dispose();
    });

    testWidgets('a habit row says it edits the habit', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = _FakeRoutineRepo(_fixtureDay);
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byKey(const Key('routine.habit.2'))),
        isSemantics(isButton: true, hint: 'Edit habit'),
      );
      handle.dispose();
    });
  });
}
