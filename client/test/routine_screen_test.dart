import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';
import 'package:fitsync/features/routine/presentation/routine_screen.dart';

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
  Future<Habit> add(HabitDraft draft) async => throw UnimplementedError();
  @override
  Future<Habit> edit(int habitId, HabitDraft draft) async =>
      throw UnimplementedError();
  @override
  Future<void> remove(int habitId) async => throw UnimplementedError();
}

Widget _harness(_FakeRoutineRepo repo, {VoidCallback? onOpenPlan}) =>
    ProviderScope(
      overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: RoutineScreen(onOpenPlan: onOpenPlan)),
    );

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

  testWidgets('a ticked row is dimmed and struck through', (tester) async {
    final repo = _FakeRoutineRepo(_fixtureDay);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('Mobility'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 0.55);

    final title = tester.widget<Text>(find.text('Mobility'));
    expect(title.style?.decoration, TextDecoration.lineThrough);

    final walkTitle = tester.widget<Text>(find.text('Walk'));
    expect(walkTitle.style?.decoration, TextDecoration.none);
  });

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
}
