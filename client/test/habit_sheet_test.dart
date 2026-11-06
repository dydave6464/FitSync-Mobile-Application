import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';
import 'package:fitsync/features/routine/presentation/widgets/habit_sheet.dart';

import 'helpers/a11y.dart' show contrast;

const _dummyHabit = Habit(
  habitId: 99,
  title: 'placeholder',
  time: null,
  durationMin: null,
  weekdays: [1],
  done: false,
);

const _existing = Habit(
  habitId: 7,
  title: 'Run',
  time: '06:30',
  durationMin: 20,
  weekdays: [1, 3],
  done: false,
);

/// Records `add` / `edit` / `remove` calls, the model for a habit-sheet test's
/// fake per Task 5's `_FakeRepo`. `today()` answers the harness's first load
/// and each write's reload, from [days].
class _FakeRepo implements RoutineRepository {
  bool failNext = false;
  final added = <HabitDraft>[];
  final edited = <(int, HabitDraft)>[];
  final removed = <int>[];
  final restored = <int>[];

  /// The habits `today()` lists. Delete takes one out, restore puts it back,
  /// as the server's soft delete does.
  List<Habit> habits = const [];
  final _deleted = <int, Habit>{};

  /// Thrown by the next `restore` calls, one per call, in order.
  final restoreFailures = <ApiException>[];

  Future<void> _maybeFail() async {
    if (failNext) {
      failNext = false;
      throw const ApiException('NETWORK_ERROR', 'offline');
    }
  }

  /// The day each successive `today()` answers with; the last repeats. More
  /// than one simulates midnight passing while the sheet is open.
  List<String> days = const ['2026-09-21'];
  int _todayCalls = 0;

  @override
  Future<RoutineDay> today() async => RoutineDay(
    date: days[(_todayCalls++).clamp(0, days.length - 1)],
    habits: habits,
    workout: null,
  );

  @override
  Future<void> check(int habitId, {String? date}) => _maybeFail();
  @override
  Future<void> uncheck(int habitId, {String? date}) => _maybeFail();

  /// Echoes the draft back as the saved habit -- what the real server does --
  /// so a test can tell what the sheet was told was saved, weekdays included.
  Habit _fromDraft(int habitId, HabitDraft draft) => Habit(
    habitId: habitId,
    title: draft.title,
    time: draft.time,
    durationMin: draft.durationMin,
    weekdays: draft.weekdays,
    done: false,
  );

  @override
  Future<Habit> add(HabitDraft draft) async {
    await _maybeFail();
    added.add(draft);
    return _fromDraft(_dummyHabit.habitId, draft);
  }

  @override
  Future<Habit> edit(int habitId, HabitDraft draft) async {
    await _maybeFail();
    edited.add((habitId, draft));
    return _fromDraft(habitId, draft);
  }

  @override
  Future<void> remove(int habitId) async {
    await _maybeFail();
    removed.add(habitId);
    for (final h in habits.where((h) => h.habitId == habitId)) {
      _deleted[habitId] = h;
    }
    habits = [...habits.where((h) => h.habitId != habitId)];
  }

  @override
  Future<Habit> restore(int habitId) async {
    restored.add(habitId);
    if (restoreFailures.isNotEmpty) throw restoreFailures.removeAt(0);
    final habit = _deleted.remove(habitId) ?? _existing;
    habits = [...habits, habit];
    return habit;
  }

  @override
  Future<List<Habit>> all() async => const [];
}

Future<_FakeRepo> _open(
  WidgetTester tester, {
  Habit? existing,
  bool failNext = false,
  List<String>? days,
  bool announceRepeats = true,
  bool dark = false,
  List<Habit> habits = const [],
}) async {
  final repo = _FakeRepo()
    ..failNext = failNext
    ..habits = habits;
  if (days != null) repo.days = days;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [routineRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : fsLightTheme(),
        // Watches the day, as the routine screen and Home's card do: the
        // sheet is only ever opened over a routine that has loaded.
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(routineTodayProvider);
            return Scaffold(
              body: TextButton(
                onPressed: () => showHabitSheet(
                  context,
                  existing: existing,
                  announceRepeats: announceRepeats,
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

String _errorText(WidgetTester tester) =>
    tester.widget<FsErrorLine>(find.byKey(const Key('habit.error'))).message;

void main() {
  testWidgets('an empty title is rejected, shows why, and saves nothing', (
    tester,
  ) async {
    final repo = await _open(tester);

    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(_errorText(tester), 'Give the habit a name.');
    expect(repo.added, isEmpty);
  });

  testWidgets('a title over 60 characters is rejected', (tester) async {
    final repo = await _open(tester);

    await tester.enterText(find.byKey(const Key('habit.title')), 'a' * 61);
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(_errorText(tester), 'Keep the name to 60 characters.');
    expect(repo.added, isEmpty);
  });

  testWidgets('a duration outside 1-600 minutes is rejected', (tester) async {
    final repo = await _open(tester);

    await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
    await tester.enterText(find.byKey(const Key('habit.duration')), '0');
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(_errorText(tester), 'Duration is 1 to 600 minutes.');
    expect(repo.added, isEmpty);
  });

  testWidgets('unticking every day is rejected', (tester) async {
    final repo = await _open(tester);
    await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');

    for (var weekday = 1; weekday <= 7; weekday += 1) {
      await tester.tap(find.byKey(Key('weekday.$weekday')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(_errorText(tester), 'Pick at least one day.');
    expect(repo.added, isEmpty);
  });

  testWidgets(
    'a valid new habit is added trimmed, with no time or duration, on every '
    'day, and the sheet closes',
    (tester) async {
      final repo = await _open(tester);

      await tester.enterText(
        find.byKey(const Key('habit.title')),
        '  Stretch  ',
      );
      await tester.tap(find.byKey(const Key('habit.save')));
      await tester.pumpAndSettle();

      final draft = repo.added.single;
      expect(draft.title, 'Stretch');
      expect(draft.time, isNull);
      expect(draft.durationMin, isNull);
      expect(draft.weekdays, [1, 2, 3, 4, 5, 6, 7]);
      expect(find.byKey(const Key('habit.save')), findsNothing);
    },
  );

  testWidgets(
    'saving a habit that does not repeat today says what days it repeats on',
    (tester) async {
      await _open(tester);

      await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
      // The fixture day (2026-09-21) is a Monday: weekday 1. Leave only
      // Tuesday (2) and Thursday (4) selected, so today is excluded.
      for (final weekday in [1, 3, 5, 6, 7]) {
        await tester.tap(find.byKey(Key('weekday.$weekday')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('habit.save')));
      await tester.pumpAndSettle();

      expect(find.text('Saved — repeats Tue, Thu'), findsOneWidget);
    },
  );

  testWidgets(
    'a save that lands after midnight still compares against the day it opened on',
    (tester) async {
      // Opened on Monday 2026-09-21; the save's own reload comes back on
      // Tuesday. A Tuesday-only habit does not repeat on the day the person
      // was looking at, so they are told when it does.
      await _open(tester, days: ['2026-09-21', '2026-09-22']);

      await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
      for (final weekday in [1, 3, 4, 5, 6, 7]) {
        await tester.tap(find.byKey(Key('weekday.$weekday')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('habit.save')));
      await tester.pumpAndSettle();

      expect(find.text('Saved — repeats Tue'), findsOneWidget);
    },
  );

  testWidgets(
    'saving a habit that does repeat today shows no repeats snackbar',
    (tester) async {
      await _open(tester);

      await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
      await tester.tap(find.byKey(const Key('habit.save')));
      await tester.pumpAndSettle();

      expect(find.textContaining('repeats'), findsNothing);
    },
  );

  testWidgets('a sheet told not to announce repeats saves without saying so', (
    tester,
  ) async {
    await _open(tester, announceRepeats: false);

    await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
    // Monday's fixture day, Tuesday and Thursday only: this WOULD announce.
    for (final weekday in [1, 3, 5, 6, 7]) {
      await tester.tap(find.byKey(Key('weekday.$weekday')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('habit.save')),
      findsNothing,
      reason: 'saved, closed',
    );
    expect(find.textContaining('repeats'), findsNothing);
  });

  testWidgets('editing opens prefilled from the existing habit', (
    tester,
  ) async {
    await _open(tester, existing: _existing);

    expect(find.text('Run'), findsOneWidget);
    expect(find.text('6:30 AM'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.byKey(const Key('habit.delete')), findsOneWidget);
  });

  testWidgets('saving an edited habit calls edit with that habitId', (
    tester,
  ) async {
    final repo = await _open(tester, existing: _existing);

    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(repo.edited.single.$1, 7);
    expect(repo.edited.single.$2.title, 'Run');
    expect(find.byKey(const Key('habit.save')), findsNothing);
  });

  testWidgets('deleting calls remove with the habitId and closes the sheet', (
    tester,
  ) async {
    final repo = await _open(tester, existing: _existing);

    await tester.tap(find.byKey(const Key('habit.delete')));
    await tester.pumpAndSettle();

    expect(repo.removed, [7]);
    expect(find.byKey(const Key('habit.delete')), findsNothing);
  });

  testWidgets('a failed save keeps the sheet open and shows the error', (
    tester,
  ) async {
    await _open(tester, failNext: true);

    await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
    await tester.tap(find.byKey(const Key('habit.save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('habit.save')), findsOneWidget);
    expect(
      _errorText(tester),
      "Couldn't reach FitSync. Check your connection and try again.",
    );
  });

  group('time button (PT-3)', () {
    testWidgets('is the kit secondary button, small', (tester) async {
      await _open(tester);

      final button = tester.widget<FsButton>(
        find.byKey(const Key('habit.time')),
      );
      expect(button.kind, FsButtonKind.secondary);
      expect(button.small, isTrue);
      expect(button.label, 'Any time');
      expect(find.byType(OutlinedButton), findsNothing);
    });

    for (final dark in [false, true]) {
      testWidgets('its label reads at 4.5:1 (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        await _open(tester, dark: dark);
        final t = dark ? FsTokens.dark : FsTokens.light;

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byKey(const Key('habit.time')),
            matching: find.text('Any time'),
          ),
        );
        final color = paragraph.text.style!.color!;
        expect(contrast(color, t.surface), greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('still opens the time picker', (tester) async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('habit.time')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });
  });

  group('field labels (PT-10)', () {
    testWidgets('the name and duration fields keep their names once filled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _open(tester, existing: _existing);

      expect(
        tester.getSemantics(find.byKey(const Key('habit.title'))),
        isSemantics(isTextField: true, label: 'Name', value: 'Run'),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('habit.duration'))),
        isSemantics(isTextField: true, label: 'Duration', value: '20'),
      );
      // Visible too, not only spoken: the placeholder is gone once filled.
      expect(find.text('NAME'), findsOneWidget);
      expect(find.text('DURATION'), findsOneWidget);
      expect(find.text('min'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the sheet fits a small phone at 2x text', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [routineRepositoryProvider.overrideWithValue(repo)],
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 640),
              textScaler: TextScaler.linear(2.0),
            ),
            child: MaterialApp(
              theme: fsLightTheme(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        showHabitSheet(context, existing: _existing),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('DURATION'), findsOneWidget);
    });
  });

  group('delete with Undo (PT-11)', () {
    List<int> listed(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.text('open')))
            .read(routineTodayProvider)
            .value!
            .habits
            .map((h) => h.habitId)
            .toList();

    testWidgets('deletes at once, with no dialog, and offers Undo', (
      tester,
    ) async {
      final repo = await _open(
        tester,
        existing: _existing,
        habits: const [_existing],
      );

      await tester.tap(find.byKey(const Key('habit.delete')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.removed, [7]);
      expect(find.byKey(const Key('habit.save')), findsNothing);
      expect(find.text('Habit deleted'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);
      expect(listed(tester), isEmpty);
    });

    testWidgets('Undo restores the habit and it is back in the list', (
      tester,
    ) async {
      final repo = await _open(
        tester,
        existing: _existing,
        habits: const [_existing],
      );
      await tester.tap(find.byKey(const Key('habit.delete')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();

      expect(repo.restored, [7]);
      expect(listed(tester), [7]);
      // The habit reappearing is the feedback; nothing more is said.
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the Undo goes away on its own after about 5 seconds', (
      tester,
    ) async {
      await _open(tester, existing: _existing, habits: const [_existing]);
      await tester.tap(find.byKey(const Key('habit.delete')));
      await tester.pumpAndSettle();

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Habit deleted'), findsNothing);
    });

    testWidgets('a restore that fails says why, with Try again when a retry '
        'can fix it', (tester) async {
      final repo = await _open(
        tester,
        existing: _existing,
        habits: const [_existing],
      );
      repo.restoreFailures.add(const ApiException('NETWORK_ERROR', 'offline'));
      await tester.tap(find.byKey(const Key('habit.delete')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't bring the habit back. Couldn't reach FitSync. "
          'Check your connection and try again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(SnackBarAction, 'Try again'));
      await tester.pumpAndSettle();
      expect(repo.restored, [7, 7]);
      expect(listed(tester), [7]);
    });

    testWidgets('a restore that cannot be retried has no Try again', (
      tester,
    ) async {
      final repo = await _open(
        tester,
        existing: _existing,
        habits: const [_existing],
      );
      repo.restoreFailures.add(
        const ApiException('HABIT_NOT_FOUND', 'No such habit.'),
      );
      await tester.tap(find.byKey(const Key('habit.delete')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't bring the habit back. No such habit."),
        findsOneWidget,
      );
      expect(find.widgetWithText(SnackBarAction, 'Try again'), findsNothing);
    });

    testWidgets('with a screen reader the Undo stays up', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _open(tester, existing: _existing, habits: const [_existing]);
      await tester.tap(find.byKey(const Key('habit.delete')));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Habit deleted'), findsOneWidget);
    });

    testWidgets('a failed delete keeps the sheet open with the error, and '
        'offers no Undo', (tester) async {
      final repo = await _open(
        tester,
        existing: _existing,
        habits: const [_existing],
        failNext: true,
      );

      await tester.tap(find.byKey(const Key('habit.delete')));
      await tester.pumpAndSettle();

      expect(repo.removed, isEmpty);
      expect(find.byKey(const Key('habit.error')), findsOneWidget);
      expect(find.text('Habit deleted'), findsNothing);
    });
  });

  group('closing with changes (PT-24)', () {
    testWidgets('back with nothing typed closes without asking', (
      tester,
    ) async {
      await _open(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('New habit'), findsNothing);
    });

    testWidgets('an edit left as it was closes without asking', (tester) async {
      await _open(tester, existing: _existing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('Edit habit'), findsNothing);
    });

    testWidgets('back asks first, and Keep editing keeps what was typed', (
      tester,
    ) async {
      await _open(tester);
      await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('discard.keep')));
      await tester.pumpAndSettle();
      expect(find.text('New habit'), findsOneWidget);
      expect(find.text('Stretch'), findsOneWidget);
    });

    testWidgets('Discard closes the sheet and saves nothing', (tester) async {
      final repo = await _open(tester, existing: _existing);
      await tester.tap(find.byKey(const Key('weekday.2')));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discard.confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Edit habit'), findsNothing);
      expect(repo.edited, isEmpty);
    });

    testWidgets('a tap on the scrim asks first', (tester) async {
      await _open(tester);
      await tester.enterText(find.byKey(const Key('habit.duration')), '15');
      await tester.pump();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsOneWidget);
    });

    testWidgets('a swipe down asks first rather than closing', (tester) async {
      await _open(tester);
      await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
      await tester.pump();

      await tester.fling(find.text('New habit'), const Offset(0, 300), 1500);
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard.keep')));
      await tester.pumpAndSettle();
      expect(find.text('Stretch'), findsOneWidget);
    });

    // PT-22: the kit's handle, drawn inside the guard. Material's own sits
    // outside the sheet's child, where a drag on it closes the sheet without
    // asking.
    testWidgets('one handle, inside the guard: a swipe on it asks first', (
      tester,
    ) async {
      await _open(tester);
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse,
      );
      expect(find.byType(FsSheetHandle), findsOneWidget);
      // P-19: the kit's drag claim, shared with the check-in sheet.
      expect(find.byType(FsSheetDiscardGuard), findsOneWidget);
      await tester.enterText(find.byKey(const Key('habit.title')), 'Stretch');
      await tester.pump();

      await tester.fling(
        find.byType(FsSheetHandle),
        const Offset(0, 300),
        1500,
      );
      await tester.pumpAndSettle();

      expect(find.text('Discard your changes?'), findsOneWidget);
    });
  });
}
