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
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

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

/// A profile carrying exactly the injuries a test wants the card to render.
/// Everything else is a fixed stand-in -- the card only ever reads
/// `.injuries`.
class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(this.injuries, {this.goal});

  final List<SelectedInjury> injuries;
  final String? goal;

  @override
  Future<Profile> build() async => _profileWith(injuries, goal);
}

Profile _profileWith(List<SelectedInjury> injuries, String? goal) => Profile(
      userId: 1,
      email: 'test@example.com',
      fullName: 'Test User',
      onboardingCompleted: true,
      isPremium: false,
      notificationsEnabled: true,
      equipment: const [],
      injuries: injuries,
      mainGoal: goal,
    );

/// Records what the screen asks the profile to store. Only setInjuries is
/// implemented -- the generator writes nothing else to the profile, and a
/// fake that answers more than that hides the day it starts to.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.error, this.goal});

  final Object? error;
  final String? goal;

  List<SelectedInjury>? sent;

  @override
  Future<Profile> setInjuries(List<SelectedInjury> injuries) async {
    sent = injuries;
    if (error != null) throw error!;
    return _profileWith(injuries, goal);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by these tests');
}

Future<void> _pump(
  WidgetTester tester, {
  WorkoutPlan? plan,
  PlanRepository? repo,
  ProfileRepository? profileRepo,
  List<SelectedInjury> injuries = const [],
  List<InjuryOption> injuryOptions = const [],
  bool injuryOptionsFail = false,
  String? goal,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => plan),
        if (repo != null) planRepositoryProvider.overrideWithValue(repo),
        if (profileRepo != null)
          profileRepositoryProvider.overrideWithValue(profileRepo),
        profileProvider
            .overrideWith(() => _FakeProfileNotifier(injuries, goal: goal)),
        injuryOptionsProvider.overrideWith((ref) async {
          if (injuryOptionsFail) throw Exception('catalogue down');
          return injuryOptions;
        }),
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

/// What the screen says on the way out. Spelled once here so the assertion
/// and the widget cannot drift apart while both still pass.
const _generatedMessage = 'New plan generated';

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
    expect(
      tester.widget<Text>(find.byKey(const Key('gen.length.value'))).data,
      '60 min',
    );
  });

  testWidgets('with no plan the controls fall back to defaults', (tester) async {
    // /regenerate has no NO_ACTIVE_PLAN check, so this screen works for
    // someone who has none -- it must not render blank.
    await _pump(tester, plan: null);

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugSplitStyle, 'full_body');
    expect(screen.debugDaysPerWeek, 3);
    expect(screen.debugSessionLengthMin, 45);

    expect(
      find.descendant(
        of: find.byKey(const Key('gen.splits')),
        matching: find.byType(FsChip),
      ),
      findsNWidgets(4),
    );
    expect(_chipOn(tester, 'Full body'), isTrue);
    expect(_dayFilled(tester, 3), isTrue);
    expect(_dayFilled(tester, 4), isFalse);
    expect(
      tester.widget<Text>(find.byKey(const Key('gen.length.value'))).data,
      '45 min',
    );
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

  testWidgets('the session length is a readout, not something to tap',
      (tester) async {
    // Length is derived, not chosen: the service reads it from goal and
    // fitness level (LONG_SESSION_GOALS, BEGINNER_SESSION_CAP) and the
    // override exists only so the prototype's slider would not lie. Offering
    // two stops invited a choice the generator may not honour.
    await _pump(tester, plan: _pplPlan); // a 60-minute plan

    expect(find.byType(FsSegmented), findsNothing);

    final readout = find.byKey(const Key('gen.length.value'));
    expect(readout, findsOneWidget);
    expect(tester.widget<Text>(readout).data, '60 min');
    expect(
      find.ancestor(of: readout, matching: find.byType(InkWell)),
      findsNothing,
      reason: 'a readout that takes taps but changes nothing is worse than none',
    );
  });

  testWidgets('the session length readout follows the plan', (tester) async {
    // "It adjusts" means it tracks the plan the service built, so a plan
    // whose length differs must read differently without anything on this
    // screen being touched.
    await _pump(tester, plan: null); // falls back to the 45-minute default

    expect(
      tester.widget<Text>(find.byKey(const Key('gen.length.value'))).data,
      '45 min',
    );
  });

  testWidgets('days one through seven are offered', (tester) async {
    await _pump(tester, plan: _pplPlan);

    for (var d = 1; d <= 7; d += 1) {
      expect(find.byKey(Key('gen.day.$d')), findsOneWidget);
    }
    expect(find.byKey(const Key('gen.day.8')), findsNothing);
  });

  testWidgets('the days label carries the number chosen', (tester) async {
    // The mockup pairs the label with the count -- seven identical cells
    // filled up to a boundary is a bar chart, not a readout, and counting
    // the filled ones is work the screen can do for the user.
    await _pump(tester, plan: _pplPlan); // opens on 4

    final readout = find.byKey(const Key('gen.days.value'));
    expect(readout, findsOneWidget);
    expect(tester.widget<Text>(readout).data, '4');

    await tester.tap(find.byKey(const Key('gen.day.6')));
    await tester.pump();

    expect(tester.widget<Text>(readout).data, '6',
        reason: 'a readout that does not follow the control is worse than none');
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

  testWidgets('tapping the day count that is already chosen gives a day back',
      (tester) async {
    // The row fills 1..N, so tapping the lit top cell used to do nothing at
    // all and only tapping a LOWER number appeared to deselect -- tap 3 when
    // 3 is chosen and the control just sat there.
    await _pump(tester, plan: _pplPlan); // opens on 4

    await tester.tap(find.byKey(const Key('gen.day.4')));
    await tester.pump();

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugDaysPerWeek, 3);
    expect(_dayFilled(tester, 3), isTrue);
    expect(_dayFilled(tester, 4), isFalse);
  });

  testWidgets('a day below the count still selects rather than steps down',
      (tester) async {
    // Step-down applies only to the cell that IS the count. Tapping 2 when 4
    // is chosen must land on 2, not 1.
    await _pump(tester, plan: _pplPlan); // opens on 4

    await tester.tap(find.byKey(const Key('gen.day.2')));
    await tester.pump();

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugDaysPerWeek, 2);
  });

  testWidgets('the day count floors at one', (tester) async {
    // A plan with no days is not a plan, and parameters.derive clamps to
    // MIN_DAYS_PER_WEEK regardless -- offering zero would lie about what the
    // generator is going to build.
    await _pump(tester, plan: _pplPlan);

    await tester.tap(find.byKey(const Key('gen.day.1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('gen.day.1')));
    await tester.pump();

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugDaysPerWeek, 1);
    expect(_dayFilled(tester, 1), isTrue);
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
    expect(find.text(_generatedMessage), findsNothing,
        reason: 'nothing was generated, so nothing should say it was');
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

  testWidgets('a successful generation says so on the way out', (tester) async {
    // The "+" is in the bottom bar, so this screen is reachable from Home,
    // Browse and Profile as well as Train, and popping returns to whichever
    // one the user came from. Without a word from the app, the one
    // irreversible thing on this screen -- it replaces the current plan --
    // completes with nothing on screen changing at all.
    final repo = FakePlanRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activePlanProvider.overrideWith((ref) async => _pplPlan),
          planRepositoryProvider.overrideWithValue(repo),
        ],
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
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(find.byType(GeneratorScreen), findsNothing);
    // On the screen behind, not the one that just left: the messenger is
    // captured before the await precisely so the message outlives the pop.
    expect(find.text('open'), findsOneWidget);
    expect(find.text(_generatedMessage), findsOneWidget);
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

  group('describe your week', () {
    const knee =
        InjuryOption(injuryId: 3, name: 'Knee', isLateral: true, regionGroup: 'leg');
    const back = InjuryOption(
        injuryId: 9, name: 'Lower back', isLateral: false, regionGroup: 'back');

    /// The editable inside the card. The key sits on the FsField wrapper, so
    /// both reading and typing have to reach through it.
    Finder field() => find.descendant(
          of: find.byKey(const Key('gen.describe.field')),
          matching: find.byType(TextField),
        );

    String fieldText(WidgetTester tester) =>
        tester.widget<TextField>(field()).controller!.text;

    Future<void> write(WidgetTester tester, String text) async {
      await tester.enterText(field(), text);
      await tester.pump();
    }

    Future<void> apply(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('gen.describe.apply')));
      await tester.pumpAndSettle();
    }

    testWidgets('opens with a sentence composed from the profile and plan',
        (tester) async {
      await _pump(tester, plan: _pplPlan, goal: 'build_muscle');

      final text = fieldText(tester);
      expect(text, contains('build muscle'));
      expect(text, contains('4 days'));
      expect(text, contains('push / pull / legs'));
    });

    testWidgets('an edited sentence is not overwritten when the profile arrives',
        (tester) async {
      // The box follows the profile and plan only until the user takes it
      // over. Re-composing over their words would delete what they typed.
      await _pump(tester, plan: _pplPlan, goal: 'build_muscle');

      await write(tester, 'my own words');
      await tester.pumpAndSettle();

      expect(fieldText(tester), 'my own words');
    });

    testWidgets('applying the sentence moves the split and the day count',
        (tester) async {
      await _pump(tester, plan: _pplPlan); // opens on push/pull/legs, 4 days

      await write(tester, 'full body, 2 days a week');
      await apply(tester);

      final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
      expect(screen.debugSplitStyle, 'full_body');
      expect(screen.debugDaysPerWeek, 2);
      expect(_chipOn(tester, 'Full body'), isTrue);
      expect(_dayFilled(tester, 2), isTrue);
      expect(_dayFilled(tester, 3), isFalse);
    });

    testWidgets('a sentence it cannot read leaves the controls alone',
        (tester) async {
      // Resolving nothing must not read as "full body, 3 days" -- that is
      // the flattening this screen already refuses for its loading state.
      await _pump(tester, plan: _pplPlan);

      await write(tester, 'asdf qwer zxcv');
      await apply(tester);

      final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
      expect(screen.debugSplitStyle, 'push_pull_legs');
      expect(screen.debugDaysPerWeek, 4);
    });

    testWidgets('from profile rewrites the sentence after an edit',
        (tester) async {
      await _pump(tester, plan: _pplPlan, goal: 'build_muscle');

      await write(tester, 'nonsense');
      await tester.tap(find.byKey(const Key('gen.describe.fromProfile')));
      await tester.pumpAndSettle();

      expect(fieldText(tester), contains('push / pull / legs'));
    });

    testWidgets('a region the profile lacks is offered, not applied',
        (tester) async {
      // The generator reads injuries from the profile server-side. Treating a
      // typed region as already honoured would promise protection the plan
      // does not have.
      await _pump(tester, plan: _pplPlan, injuryOptions: const [knee, back]);

      await write(tester, 'protect my right knee');
      await apply(tester);

      expect(find.byKey(const Key('gen.describe.add.3')), findsOneWidget);
      expect(find.byKey(const Key('gen.avoiding')), findsNothing,
          reason: 'nothing is being avoided until the profile says so');
    });

    testWidgets('the offer says what adding the region will do', (tester) async {
      // "Not in your injuries yet" states a fact about a database. What the
      // user is deciding is whether their plan avoids the movement, and the
      // offer should say so -- 608 exercises are contraindicated for the
      // lower back alone, and none of them are skipped until this is tapped.
      await _pump(tester, plan: _pplPlan, injuryOptions: const [knee, back]);

      await write(tester, 'protect my right knee');
      await apply(tester);

      expect(find.textContaining('skip the exercises that load it'),
          findsOneWidget);
    });

    testWidgets('adding an offered region sends it to the profile',
        (tester) async {
      final profileRepo = FakeProfileRepository();
      await _pump(
        tester,
        plan: _pplPlan,
        profileRepo: profileRepo,
        injuryOptions: const [knee, back],
      );

      await write(tester, 'protect my right knee');
      await apply(tester);
      await tester.tap(find.byKey(const Key('gen.describe.add.3')));
      await tester.pumpAndSettle();

      expect(profileRepo.sent, hasLength(1));
      expect(profileRepo.sent!.single.injuryId, 3);
      expect(profileRepo.sent!.single.side, 'right');
    });

    testWidgets('adding keeps the injuries the profile already had',
        (tester) async {
      // PUT /profile/injuries replaces the whole set, so an add that sends
      // only the new region silently deletes every other injury the user has.
      final profileRepo = FakeProfileRepository();
      await _pump(
        tester,
        plan: _pplPlan,
        profileRepo: profileRepo,
        injuries: const [SelectedInjury(injuryId: 9)],
        injuryOptions: const [knee, back],
      );

      await write(tester, 'protect my right knee');
      await apply(tester);
      await tester.tap(find.byKey(const Key('gen.describe.add.3')));
      await tester.pumpAndSettle();

      expect(profileRepo.sent!.map((i) => i.injuryId), containsAll(<int>[9, 3]));
    });

    testWidgets('a region already in the profile is not offered again',
        (tester) async {
      await _pump(
        tester,
        plan: _pplPlan,
        injuries: const [SelectedInjury(injuryId: 3, side: 'right')],
        injuryOptions: const [knee, back],
      );

      await write(tester, 'protect my right knee');
      await apply(tester);

      expect(find.byKey(const Key('gen.describe.add.3')), findsNothing);
    });

    testWidgets('a failed add says so and keeps the offer', (tester) async {
      final profileRepo = FakeProfileRepository(
        error: const ApiException('VALIDATION_ERROR', 'Could not save that.'),
      );
      await _pump(
        tester,
        plan: _pplPlan,
        profileRepo: profileRepo,
        injuryOptions: const [knee, back],
      );

      await write(tester, 'protect my right knee');
      await apply(tester);
      await tester.tap(find.byKey(const Key('gen.describe.add.3')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not save that'), findsOneWidget);
      expect(find.byKey(const Key('gen.describe.add.3')), findsOneWidget,
          reason: 'nothing was saved, so the offer must still stand');
    });

    testWidgets('a catalogue that failed to load does not claim nothing matched',
        (tester) async {
      // value ?? const [] reads the same for "still loading", "failed" and
      // "no regions exist". With a card that reports what it recognised, that
      // silence becomes a false statement about the user's injuries.
      await _pump(tester, plan: _pplPlan, injuryOptionsFail: true);

      await write(tester, 'protect my right knee');
      await apply(tester);

      expect(find.byKey(const Key('gen.describe.catalogueError')), findsOneWidget);
      expect(find.byKey(const Key('gen.describe.add.3')), findsNothing);
    });

    testWidgets('a topic this screen does not own is named, not dropped',
        (tester) async {
      await _pump(tester, plan: _pplPlan);

      await write(tester, 'about 50 min a session');
      await apply(tester);

      expect(find.byKey(const Key('gen.describe.elsewhere')), findsOneWidget);
      expect(find.textContaining('Session length'), findsOneWidget);
    });
  });

  testWidgets('the avoiding card names the profile injuries', (tester) async {
    // The card displays state and sends nothing: /regenerate reads the
    // profile server-side, which is what stops a client generating against
    // someone else's.
    await _pump(
      tester,
      plan: _pplPlan,
      injuries: const [SelectedInjury(injuryId: 3, side: 'right')],
      injuryOptions: const [
        InjuryOption(injuryId: 3, name: 'Knee', isLateral: true, regionGroup: 'leg'),
        InjuryOption(injuryId: 9, name: 'Lower back', isLateral: false, regionGroup: 'back'),
      ],
    );

    expect(find.text('Avoiding: Knee (right)'), findsOneWidget);
  });

  testWidgets('a non-lateral injury carries no side', (tester) async {
    await _pump(
      tester,
      plan: _pplPlan,
      injuries: const [SelectedInjury(injuryId: 9)],
      injuryOptions: const [
        InjuryOption(injuryId: 9, name: 'Lower back', isLateral: false, regionGroup: 'back'),
      ],
    );

    // Scoped to the avoiding card: the describe box composes a sentence from
    // the same profile, so an unscoped finder now matches both.
    expect(
      find.descendant(
        of: find.byKey(const Key('gen.avoiding')),
        matching: find.textContaining('Lower back'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Right'), findsNothing);
  });

  testWidgets('with no injuries the card is absent', (tester) async {
    // An "Avoiding: nothing" card is noise on a screen that already has
    // three controls competing for attention.
    await _pump(tester, plan: _pplPlan, injuries: const []);

    expect(find.byKey(const Key('gen.avoiding')), findsNothing);
  });

  testWidgets(
    'the avoiding text is the exact join for a region whose group disagrees with its laterality',
    (tester) async {
      // regionGroup is 'back' -- normally non-lateral -- but this option is
      // marked isLateral: true, so laterality must come from that flag, not
      // a region guess. The unselected Lower back option must not leak into
      // the join, and the side must render as given, not a hard-coded one.
      await _pump(
        tester,
        plan: _pplPlan,
        injuries: const [SelectedInjury(injuryId: 12, side: 'left')],
        injuryOptions: const [
          InjuryOption(injuryId: 12, name: 'SI joint', isLateral: true, regionGroup: 'back'),
          InjuryOption(injuryId: 9, name: 'Lower back', isLateral: false, regionGroup: 'back'),
        ],
      );

      // The complete string, not a substring -- the unselected entry's
      // absence is part of what this asserts. The name keeps the case the
      // catalogue gave it: lowercasing it renders "si joint" beside a
      // non-lateral "Lower back" that kept its own capital, inconsistent
      // inside a single sentence.
      expect(find.text('Avoiding: SI joint (left)'), findsOneWidget);
    },
  );

  testWidgets('an injury on both sides says so', (tester) async {
    // "Both shoulder" is not English. The parenthetical is the one form
    // that reads for every side the catalogue can send.
    await _pump(
      tester,
      plan: _pplPlan,
      injuries: const [SelectedInjury(injuryId: 4, side: 'both')],
      injuryOptions: const [
        InjuryOption(injuryId: 4, name: 'Shoulder', isLateral: true, regionGroup: 'arm'),
      ],
    );

    expect(find.text('Avoiding: Shoulder (both sides)'), findsOneWidget);
  });

  testWidgets('an unrecognised side degrades to the bare name', (tester) async {
    // The old form tested for 'both', then 'left', and called everything
    // else 'Right' -- so a value this client does not know about named the
    // wrong side of the user's body with total confidence, on the one
    // screen whose job is saying what is being protected. Saying less is
    // the only honest answer.
    await _pump(
      tester,
      plan: _pplPlan,
      injuries: const [SelectedInjury(injuryId: 4, side: 'bilateral')],
      injuryOptions: const [
        InjuryOption(injuryId: 4, name: 'Shoulder', isLateral: true, regionGroup: 'arm'),
      ],
    );

    expect(find.text('Avoiding: Shoulder'), findsOneWidget);
  });
}
