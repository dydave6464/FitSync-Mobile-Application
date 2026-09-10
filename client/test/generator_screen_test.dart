import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/generator_screen.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';

const _pplPlan = WorkoutPlan(
  planId: 7,
  name: 'Week 1 — Push/Pull/Legs',
  splitStyle: 'push_pull_legs',
  daysPerWeek: 4,
  sessionLengthMin: 60,
  weekNo: 1,
  days: [
    PlanDay(dayNo: 1, name: 'Push'),
    PlanDay(dayNo: 2, name: 'Pull'),
    PlanDay(dayNo: 3, name: 'Legs'),
  ],
  exercises: [],
);

class FakePlanRepository implements PlanRepository {
  FakePlanRepository({this.error, this.pending});

  final Object? error;

  /// When set, `regenerate` awaits this instead of resolving immediately --
  /// lets a test hold a request open and control exactly when it completes,
  /// e.g. to pop the screen while the request is still in flight.
  final Future<WorkoutPlan>? pending;

  Map<String, dynamic>? sent;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan> regenerate({
    required String splitStyle,
    required int daysPerWeek,
    required int sessionLengthMin,
  }) async {
    sent = {
      'splitStyle': splitStyle,
      'daysPerWeek': daysPerWeek,
      'sessionLengthMin': sessionLengthMin,
    };
    if (pending != null) return pending!;
    if (error != null) throw error!;
    return _pplPlan;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by these tests');
}

Future<void> _pump(WidgetTester tester, {WorkoutPlan? plan, PlanRepository? repo}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => plan),
        if (repo != null) planRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: const GeneratorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Whether the split chip labelled [label] is rendered selected. FsChip
/// always renders its label regardless of `selected` -- the colour is the
/// only place selection shows -- so a test using find.text alone cannot
/// tell a selected chip from an unselected one.
bool _chipOn(WidgetTester tester, String label) => tester
    .widgetList<FsChip>(find.byType(FsChip))
    .firstWhere((c) => c.label == label)
    .selected;

/// Whether day [d]'s cell is painted in the accent colour, i.e. counted as
/// part of the selected run. Every cell 1-7 always renders its number; fill
/// colour is the only signal that a day is selected.
bool _dayFilled(WidgetTester tester, int d) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byKey(Key('gen.day.$d')),
      matching: find.byType(Container),
    ),
  );
  final accent = fsLightTheme().extension<FsTokens>()!.accent;
  return (container.decoration as BoxDecoration).color == accent;
}

void main() {
  testWidgets('the four split styles are offered', (tester) async {
    await _pump(tester, plan: _pplPlan);

    expect(find.text('Full body'), findsOneWidget);
    expect(find.text('Push / Pull / Legs'), findsOneWidget);
    expect(find.text('Upper / Lower'), findsOneWidget);
    expect(find.text('Cardio + core'), findsOneWidget);
  });

  testWidgets('the controls open on the current plan', (tester) async {
    // The screen should describe what the user already has, so a generate
    // with no changes is a no-op rather than a silent reset to full body.
    await _pump(tester, plan: _pplPlan);

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugSplitStyle, 'push_pull_legs');
    expect(screen.debugDaysPerWeek, 4);
    expect(screen.debugSessionLengthMin, 60);

    // The debug getters can agree with the plan while the rendered controls
    // still show something else entirely -- these assert what a user would
    // actually see.
    expect(_chipOn(tester, 'Push / Pull / Legs'), isTrue);
    expect(_chipOn(tester, 'Full body'), isFalse);
    for (var d = 1; d <= 4; d += 1) {
      expect(_dayFilled(tester, d), isTrue);
    }
    for (var d = 5; d <= 7; d += 1) {
      expect(_dayFilled(tester, d), isFalse);
    }
    expect(tester.widget<FsSegmented>(find.byType(FsSegmented)).selected, '60');
  });

  testWidgets('with no plan the controls fall back to defaults', (tester) async {
    // /regenerate has no NO_ACTIVE_PLAN check, so this screen works for
    // someone who has none -- it must not render blank.
    await _pump(tester, plan: null);

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugSplitStyle, 'full_body');
    expect(screen.debugDaysPerWeek, 3);
    expect(screen.debugSessionLengthMin, 45);

    expect(find.byType(FsChip), findsNWidgets(4));
    expect(_chipOn(tester, 'Full body'), isTrue);
    expect(_dayFilled(tester, 3), isTrue);
    expect(_dayFilled(tester, 4), isFalse);
    expect(tester.widget<FsSegmented>(find.byType(FsSegmented)).selected, '45');
  });

  testWidgets('tapping a split chip selects it', (tester) async {
    await _pump(tester, plan: _pplPlan);

    await tester.tap(find.text('Upper / Lower'));
    await tester.pump();

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugSplitStyle, 'upper_lower');
    expect(_chipOn(tester, 'Upper / Lower'), isTrue);
    expect(_chipOn(tester, 'Push / Pull / Legs'), isFalse);
  });

  testWidgets('session length offers exactly 45 and 60', (tester) async {
    // EXERCISES_BY_SESSION knows two lengths and _nearest_session_length
    // snaps everything else, so a slider reading 50 would build a 45-minute
    // plan. Two stops is the honest control.
    await _pump(tester, plan: _pplPlan);

    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('60 min'), findsOneWidget);
    expect(find.text('50 min'), findsNothing);
    // A find.text absence check alone would not catch a third valid-looking
    // stop (e.g. "90 min") being added -- assert the option count directly.
    expect(tester.widget<FsSegmented>(find.byType(FsSegmented)).options.length, 2);
  });

  testWidgets('tapping a session length stop selects it', (tester) async {
    // Split chips and days both get a real tap in other tests; this control
    // never did, and its onSelected does an int.parse that would throw if
    // a stop's value and label were ever transposed.
    await _pump(tester, plan: _pplPlan); // opens on 60

    await tester.tap(find.byKey(const Key('segment.45')));
    await tester.pump();

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugSessionLengthMin, 45);
    expect(tester.widget<FsSegmented>(find.byType(FsSegmented)).selected, '45');
  });

  testWidgets('days one through seven are offered', (tester) async {
    await _pump(tester, plan: _pplPlan);

    for (var d = 1; d <= 7; d += 1) {
      expect(find.byKey(Key('gen.day.$d')), findsOneWidget);
    }
    expect(find.byKey(const Key('gen.day.8')), findsNothing);
  });

  testWidgets('tapping a day selects it', (tester) async {
    await _pump(tester, plan: _pplPlan);

    await tester.tap(find.byKey(const Key('gen.day.6')));
    await tester.pump();

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugDaysPerWeek, 6);
    for (var d = 1; d <= 6; d += 1) {
      expect(_dayFilled(tester, d), isTrue);
    }
    expect(_dayFilled(tester, 7), isFalse);
  });

  testWidgets('the screen says generating replaces the current plan',
      (tester) async {
    // savePlan deactivates the previous plan inside its transaction. That is
    // the one destructive thing here and should not be discovered afterwards.
    await _pump(tester, plan: _pplPlan);

    expect(find.textContaining('replace'), findsOneWidget);
  });

  testWidgets('shows a loading indicator while the plan is loading, not the defaults',
      (tester) async {
    // AsyncValue.value reads null for both "loading" and "no plan", so
    // flattening the two would render full_body/3/45 under "Generating
    // replaces your current plan" while the real plan is still in flight.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activePlanProvider.overrideWith((ref) => Completer<WorkoutPlan?>().future),
        ],
        child: MaterialApp(theme: fsLightTheme(), home: const GeneratorScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(FsChip), findsNothing);
    expect(find.text('Generating replaces your current plan.'), findsNothing);
  });

  testWidgets('shows an error and offers a retry rather than the defaults',
      (tester) async {
    // Same flattening risk as loading: a failed fetch must not quietly
    // present full_body/3/45 as if it described a real plan, because
    // generating from there really does replace whatever plan the user has.
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activePlanProvider.overrideWith((ref) async {
            calls += 1;
            // A plain Exception, not ApiException(NETWORK_ERROR) -- the one
            // code apiRetryPolicy treats as transient and would retry on its
            // own, which would hide the very state this test is checking.
            if (calls == 1) throw Exception('boom');
            return _pplPlan;
          }),
        ],
        child: MaterialApp(theme: fsLightTheme(), home: const GeneratorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FsChip), findsNothing);
    expect(find.text('Generating replaces your current plan.'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2, reason: 'retry must actually refetch');
    expect(find.text('Push / Pull / Legs'), findsOneWidget);
  });

  testWidgets('generate sends exactly what the controls show', (tester) async {
    final repo = FakePlanRepository();
    await _pump(tester, plan: _pplPlan, repo: repo);

    await tester.tap(find.text('Upper / Lower'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gen.day.5')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(repo.sent, {
      'splitStyle': 'upper_lower',
      'daysPerWeek': 5,
      'sessionLengthMin': 60,
    });
  });

  testWidgets('a session in progress is refused with a reason', (tester) async {
    // The endpoint refuses so that replacing the plan cannot strand a running
    // logger on exercises that no longer exist.
    final repo = FakePlanRepository(
      error: const ApiException('SESSION_IN_PROGRESS', 'Finish or discard.'),
    );
    await _pump(tester, plan: _pplPlan, repo: repo);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Finish or discard'), findsOneWidget);
  });

  testWidgets('a failed generation leaves the screen open', (tester) async {
    final repo = FakePlanRepository(
      error: const ApiException('PLAN_GENERATION_FAILED', 'Could not build a plan.'),
    );
    await _pump(tester, plan: _pplPlan, repo: repo);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(find.byType(GeneratorScreen), findsOneWidget,
        reason: 'the user must be able to retry or change their choices');
  });

  testWidgets('a successful generation refreshes the active plan', (tester) async {
    // Nothing else in the handler exercises this line -- deleting it left
    // every other assertion in this file green.
    var calls = 0;
    final repo = FakePlanRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activePlanProvider.overrideWith((ref) async {
            calls += 1;
            return _pplPlan;
          }),
          planRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(theme: fsLightTheme(), home: const GeneratorScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(calls, 2,
        reason: 'the plan must be refetched so every screen reading it sees the new one');
    expect(find.byType(GeneratorScreen), findsNothing);
  });

  testWidgets(
    'a slow generation still refreshes the plan after the user backs out',
    (tester) async {
      // The request outlives the screen: regenerate is the slowest call in
      // the app and nothing blocks the user backing out while it runs. A
      // ProviderContainer we hold directly, rather than relying on some
      // other widget happening to stay mounted and watching, lets the test
      // force the read the Plan tab would do next time it's shown -- proving
      // the provider was actually invalidated, not just that nothing crashed.
      final done = Completer<WorkoutPlan>();
      final repo = FakePlanRepository(pending: done.future);
      var calls = 0;
      final container = ProviderContainer(
        overrides: [
          activePlanProvider.overrideWith((ref) async {
            calls += 1;
            return _pplPlan;
          }),
          planRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fsLightTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const GeneratorScreen()),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0, reason: 'activePlanProvider is not read until the generator opens');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(calls, 1);

      await tester.tap(find.byKey(const Key('gen.generate')));
      await tester.pump(); // regenerate is now in flight, awaiting `done`

      await tester.pageBack();
      await tester.pumpAndSettle(); // the screen is gone before the request finishes

      done.complete(_pplPlan);
      await tester.pump();

      // Nothing is watching activePlanProvider once the generator screen is
      // gone, so a bare invalidate leaves it merely marked dirty -- force the
      // read that would otherwise wait for the Plan tab to reappear.
      await container.read(activePlanProvider.future);

      expect(calls, 2,
          reason: 'the refresh must survive the screen being popped mid-request');
    },
  );
}
