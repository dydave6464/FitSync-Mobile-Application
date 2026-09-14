import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/onboarding/presentation/generating_view.dart';
import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/generator_screen.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/plans/presentation/widgets/training_days_row.dart';
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

/// The server's refusal message, shared by [FakePlanRepository] and the tests
/// that check the dialog states it verbatim -- so the two never drift apart.
const _customPlanMessage = 'Generating a new plan replaces "My Push / Pull / '
    'Legs" and the 2 days you built in it.';

class FakePlanRepository implements PlanRepository {
  FakePlanRepository({this.error, this.pending, this.refuseCustomPlan = false});

  final Object? error;

  /// When set, `regenerate` awaits this instead of resolving immediately --
  /// lets a test hold a request open and control exactly when it completes,
  /// e.g. to pop the screen while the request is still in flight.
  final Future<WorkoutPlan>? pending;

  /// Refuses every call that does not carry `replaceCustomPlan: true`, the
  /// way the server does when a custom plan is in the way, then accepts the
  /// one that does. Independent of [error]: this is the one refusal the
  /// screen is supposed to catch and turn into a question rather than just
  /// report.
  final bool refuseCustomPlan;

  Map<String, dynamic>? sent;

  /// The days-per-week value the last `regenerate` call carried, read out of
  /// [sent] so a test does not have to know its key.
  int? get lastDaysPerWeek => sent?['daysPerWeek'] as int?;

  int regenerateCalls = 0;

  /// The `replaceCustomPlan` the last `regenerate` call carried. Kept apart
  /// from [sent], whose exact-map assertions predate this flag.
  bool? lastReplaceCustomPlan;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<WorkoutPlan> regenerate({
    required String splitStyle,
    required int daysPerWeek,
    required int sessionLengthMin,
    bool replaceCustomPlan = false,
  }) async {
    regenerateCalls += 1;
    lastReplaceCustomPlan = replaceCustomPlan;
    sent = {
      'splitStyle': splitStyle,
      'daysPerWeek': daysPerWeek,
      'sessionLengthMin': sessionLengthMin,
    };
    if (refuseCustomPlan && !replaceCustomPlan) {
      throw const ApiException('CUSTOM_PLAN_WOULD_BE_LOST', _customPlanMessage);
    }
    if (pending != null) return pending!;
    if (error != null) throw error!;
    return _pplPlan;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used by these tests');
}

/// How far the profile fetch got. The screen has to tell all three apart:
/// only [loaded] means the blank cells on screen are the user's real answer.
enum _ProfileLoad { loaded, pending, failed }

/// A profile carrying exactly the injuries a test wants the card to render.
/// Everything else is a fixed stand-in -- the card only ever reads
/// `.injuries`.
class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(
    this.injuries, {
    this.goal,
    this.trainingDays = const [],
    this.failTrainingDays = false,
    this.load = _ProfileLoad.loaded,
  });

  final List<SelectedInjury> injuries;
  final String? goal;
  final List<int> trainingDays;

  /// When set, `setTrainingDays` throws instead of writing -- lets a test
  /// prove a failed write leaves the tapped day exactly as it was.
  final bool failTrainingDays;

  final _ProfileLoad load;

  /// The weekdays the screen last asked to save, recorded whether or not the
  /// write went on to succeed.
  List<int>? lastTrainingDays;

  @override
  Future<Profile> build() async => switch (load) {
        _ProfileLoad.loaded =>
          _profileWith(injuries, goal, trainingDays: trainingDays),
        _ProfileLoad.pending => Completer<Profile>().future,
        // A plain Exception, not ApiException(NETWORK_ERROR): that is the one
        // code apiRetryPolicy retries on its own, which would leave the
        // provider looping rather than settling into the error state.
        _ProfileLoad.failed => throw Exception('profile down'),
      };

  @override
  Future<void> setTrainingDays(List<int> weekdays) async {
    lastTrainingDays = weekdays;
    if (failTrainingDays) {
      throw Exception('could not save training days');
    }
    state = AsyncData(_profileWith(injuries, goal, trainingDays: weekdays));
  }
}

Profile _profileWith(
  List<SelectedInjury> injuries,
  String? goal, {
  List<int> trainingDays = const [],
}) =>
    Profile(
      userId: 1,
      email: 'test@example.com',
      fullName: 'Test User',
      onboardingCompleted: true,
      isPremium: false,
      notificationsEnabled: true,
      equipment: const [],
      injuries: injuries,
      trainingDays: trainingDays,
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

/// The profile notifier fake the running test's `_pump` installed. Set fresh
/// on every call so a test can assert what it recorded -- `_profile.
/// lastTrainingDays` -- without threading the fake through by hand.
late _FakeProfileNotifier _profile;

/// The plan repository fake the running test's `_pump` installed, whether or
/// not the test supplied its own.
late FakePlanRepository _plans;

Future<void> _pump(
  WidgetTester tester, {
  WorkoutPlan? plan,
  PlanRepository? repo,
  ProfileRepository? profileRepo,
  List<SelectedInjury> injuries = const [],
  List<InjuryOption> injuryOptions = const [],
  bool injuryOptionsFail = false,
  String? goal,
  List<int> trainingDays = const [],
  bool failTrainingDays = false,
  _ProfileLoad profileLoad = _ProfileLoad.loaded,
}) async {
  _profile = _FakeProfileNotifier(
    injuries,
    goal: goal,
    trainingDays: trainingDays,
    failTrainingDays: failTrainingDays,
    load: profileLoad,
  );
  // Installed even when the test supplies nothing of its own -- ticking a
  // weekday and hitting Generate with no repo passed in must still have
  // somewhere real to land rather than reaching the network.
  _plans = repo is FakePlanRepository ? repo : FakePlanRepository();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => plan),
        planRepositoryProvider.overrideWithValue(_plans),
        if (profileRepo != null)
          profileRepositoryProvider.overrideWithValue(profileRepo),
        profileProvider.overrideWith(() => _profile),
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

/// How many weekday cells are rendered ticked. The sentence above the row
/// and the row itself have to agree, and only a count read off the cells can
/// say whether they do.
int _ticked(WidgetTester tester) => tester
    .widgetList<TrainingDayCell>(find.byType(TrainingDayCell))
    .where((cell) => cell.selected)
    .length;

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

  testWidgets('with no plan the derived session length still reaches the payload',
      (tester) async {
    // Length is no longer shown, so the only place it can be observed is the
    // request. It still has to be RESOLVED and SENT: omitting sessionLengthMin
    // hands the service's own `overrides.sessionLengthMin || 45` whatever it
    // likes, and a 60-minute plan would come back silently shortened.
    final repo = FakePlanRepository();
    await _pump(tester, plan: null, repo: repo);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(repo.sent!['sessionLengthMin'], 45);
  });

  testWidgets('ticking a weekday adds just that day', (tester) async {
    // The behaviour fill-to-N could not express: days are chosen
    // individually, so a rest day in the middle of the week is expressible.
    await _pump(tester, plan: _pplPlan, trainingDays: const [1, 3]);

    await tester.tap(find.byKey(const Key('weekday.5')));
    await tester.pumpAndSettle();

    expect(_profile.lastTrainingDays, [1, 3, 5]);
  });

  testWidgets('ticking a chosen weekday removes it', (tester) async {
    await _pump(tester, plan: _pplPlan, trainingDays: const [1, 3, 5]);

    await tester.tap(find.byKey(const Key('weekday.3')));
    await tester.pumpAndSettle();

    expect(_profile.lastTrainingDays, [1, 5]);
  });

  testWidgets('a failed write leaves the day as it was and says so',
      (tester) async {
    // Nothing may look saved that is not.
    await _pump(tester, plan: _pplPlan, trainingDays: const [1],
        failTrainingDays: true);

    await tester.tap(find.byKey(const Key('weekday.5')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not'), findsOneWidget);
    final failedCell = tester.widget<TrainingDayCell>(
        find.byKey(const Key('weekday.5')));
    expect(failedCell.selected, isFalse);
    // The day that WAS stored must still render selected -- proves the row
    // reflects what is saved, not just that a failed tap stays untied.
    final storedCell = tester.widget<TrainingDayCell>(
        find.byKey(const Key('weekday.1')));
    expect(storedCell.selected, isTrue);
  });

  testWidgets('a set that changed nothing is not a crash', (tester) async {
    // The screen works out which day was tapped from the symmetric
    // difference of the two sets and takes `.first`. The row toggles exactly
    // one day, so today there is always exactly one -- but an empty
    // difference makes `.first` throw a StateError, and taking the whole
    // generator down over two sets that merely matched is not a trade worth
    // leaving open. Driven through the callback rather than a tap, because
    // no tap can currently produce it.
    await _pump(tester, plan: _pplPlan, trainingDays: const [1, 3]);

    tester
        .widget<TrainingDaysRow>(find.byType(TrainingDaysRow))
        .onChanged(const [1, 3]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_profile.lastTrainingDays, isNull,
        reason: 'nothing changed, so there is nothing to save');
  });

  testWidgets('a tap does nothing while the profile is still loading',
      (tester) async {
    // PUT /profile/training-days replaces the whole set. The plan can resolve
    // while the profile has not, and the row then renders seven blank cells
    // that say "none chosen" when the truth is "not known yet" -- one tap
    // would send a single day and destroy whatever the user really had.
    await _pump(tester, plan: _pplPlan, profileLoad: _ProfileLoad.pending);

    await tester.tap(find.byKey(const Key('weekday.5')));
    await tester.pump();

    expect(_profile.lastTrainingDays, isNull,
        reason: 'a blank row that is only blank because nothing arrived '
            'must not be able to write');
    expect(find.byKey(const Key('gen.trainingDays.unavailable')), findsOneWidget,
        reason: 'a row that silently ignores taps reads as broken');
  });

  testWidgets('a failed profile leaves the row unusable and says why',
      (tester) async {
    // Same destructive tap, and the one state that never resolves on its own.
    await _pump(tester, plan: _pplPlan, profileLoad: _ProfileLoad.failed);

    await tester.tap(find.byKey(const Key('weekday.5')));
    await tester.pump();

    expect(_profile.lastTrainingDays, isNull);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('gen.trainingDays.unavailable')))
          .data,
      contains("Couldn't load"),
    );
    expect(
      tester.widget<TrainingDaysRow>(find.byType(TrainingDaysRow)).enabled,
      isFalse,
    );
  });

  testWidgets('a loaded profile with no days chosen still takes taps',
      (tester) async {
    // Empty is a real answer, and the whole point of separating it from "not
    // known": disabling on emptiness would make the first day unpickable.
    await _pump(tester, plan: _pplPlan, trainingDays: const []);

    await tester.tap(find.byKey(const Key('weekday.5')));
    await tester.pumpAndSettle();

    expect(_profile.lastTrainingDays, [5]);
    expect(find.byKey(const Key('gen.trainingDays.unavailable')), findsNothing);
  });

  testWidgets('generate sends the number of chosen days', (tester) async {
    await _pump(tester, plan: _pplPlan, trainingDays: const [1, 3, 5]);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(_plans.lastDaysPerWeek, 3);
  });

  testWidgets('with no days chosen generate falls back to the plan count',
      (tester) async {
    // The payload is never sent an empty schedule.
    await _pump(tester, plan: _pplPlan, trainingDays: const []);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(_plans.lastDaysPerWeek, _pplPlan.daysPerWeek);
  });

  testWidgets('generating shows the building screen, not just a busy button',
      (tester) async {
    await _pump(tester, plan: _pplPlan, trainingDays: const [1, 3, 5]);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pump();

    expect(find.text('Rebuilding your plan…'), findsOneWidget);
    expect(find.textContaining('Mon · Wed · Fri'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('with no days chosen the lead row counts them instead',
      (tester) async {
    // The lead row has one job -- say what is being applied -- and the plan's
    // own count is what is being applied when no weekday is ticked.
    await _pump(tester, plan: _pplPlan, trainingDays: const []);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pump();

    expect(find.text('Push / Pull / Legs, 4 days a week'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('the building screen names the injuries it is working around',
      (tester) async {
    // Row two is the injury row in both of its states, whether or not the
    // user has chosen weekdays.
    await _pump(
      tester,
      plan: _pplPlan,
      trainingDays: const [2, 4],
      injuries: const [SelectedInjury(injuryId: 3, side: 'right')],
      injuryOptions: const [
        InjuryOption(
            injuryId: 3, name: 'Knee', isLateral: true, regionGroup: 'leg'),
      ],
    );

    // The avoiding card pushes the button below the fold, and a ListView does
    // not build what it is not showing.
    // The list's own Scrollable, not the describe field's: `.first` is the
    // outermost in tree order.
    await tester.scrollUntilVisible(
      find.byKey(const Key('gen.generate')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible stops as soon as the ListView BUILDS the button,
    // which can still leave it below the fold; ensureVisible finishes the job
    // rather than relying on the page's exact height.
    await tester.ensureVisible(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pump();

    expect(find.text('Full body, Tue · Thu'), findsNothing,
        reason: 'the split is the plan\'s, not a default');
    expect(find.text('Push / Pull / Legs, Tue · Thu'), findsOneWidget);
    expect(find.text('Avoiding Knee (right)'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('the building screen is held so a fast rebuild cannot flash past',
      (tester) async {
    await _pump(tester, plan: _pplPlan, trainingDays: const [1, 3, 5]);

    await tester.tap(find.byKey(const Key('gen.generate')));
    // Nothing is gated: regenerate resolves on the next microtask, which is
    // the case the hold exists for.
    await tester.pump();
    await tester.pump(GeneratingPace.regenerate.revealAt.last +
        const Duration(milliseconds: 100));

    for (final row in ['lead', 'avoiding', 'exercises']) {
      expect(find.byKey(Key('gen.$row.done')), findsOneWidget,
          reason: 'row $row should have ticked by the last slot');
    }
    expect(find.byType(GeneratorScreen), findsOneWidget,
        reason: 'a hold shorter than the schedule would hand off mid-sequence '
            'and the last tick would never be seen');

    await tester.pumpAndSettle();
    expect(find.byType(GeneratorScreen), findsNothing,
        reason: 'the hold delays the hand-off, never skips it');
  });

  testWidgets('the exercises row waits for the plan, not just for its slot',
      (tester) async {
    // Pacing, never progress. The request is held open past every slot; the
    // row that describes it must not tick until it answers.
    final done = Completer<WorkoutPlan>();
    await _pump(
      tester,
      plan: _pplPlan,
      repo: FakePlanRepository(pending: done.future),
      trainingDays: const [1, 3, 5],
    );

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pump();
    await tester.pump(GeneratingPace.regenerate.minimumRun * 2);

    expect(find.byKey(const Key('gen.lead.done')), findsOneWidget);
    expect(find.byKey(const Key('gen.exercises.done')), findsNothing,
        reason: 'this row is the work still running; ticking it would be a lie');

    done.complete(_pplPlan);
    await tester.pumpAndSettle();
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
    await _pump(tester, plan: _pplPlan, repo: repo,
        trainingDays: const [1, 2, 3, 4, 5]);

    await tester.tap(find.text('Upper / Lower'));
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

  testWidgets('generating over your own plan asks first', (tester) async {
    final repo = FakePlanRepository(refuseCustomPlan: true);
    await _pump(tester, plan: _pplPlan, repo: repo);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    // The exact sentence the server sent, not a generic phrasing composed
    // here -- the static "Generating replaces your current plan." disclaimer
    // elsewhere on this screen also contains the word "replaces", so only the
    // full sentence tells the two apart.
    expect(find.text(_customPlanMessage), findsOneWidget);
    expect(repo.regenerateCalls, 1, reason: 'the refusal is what raised it');
  });

  testWidgets('backing out of the warning keeps your plan', (tester) async {
    final repo = FakePlanRepository(refuseCustomPlan: true);
    await _pump(tester, plan: _pplPlan, repo: repo);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep my plan'));
    await tester.pumpAndSettle();

    expect(repo.regenerateCalls, 1, reason: 'no second attempt was made');
    expect(repo.lastReplaceCustomPlan, isFalse);
  });

  testWidgets('confirming regenerates and says so explicitly', (tester) async {
    final repo = FakePlanRepository(refuseCustomPlan: true);
    await _pump(tester, plan: _pplPlan, repo: repo);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace it'));
    await tester.pumpAndSettle();

    expect(repo.regenerateCalls, 2);
    expect(repo.lastReplaceCustomPlan, isTrue);
  });

  testWidgets('a generated plan is replaced without a question', (tester) async {
    // A regression guard on today's behaviour: a plan the screen itself
    // generated must never be second-guessed.
    final repo = FakePlanRepository();
    await _pump(tester, plan: _pplPlan, repo: repo);

    await tester.tap(find.byKey(const Key('gen.generate')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.regenerateCalls, 1);
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
          // These three tests are about generate, refresh and pop, not about
          // the profile -- but without an override it reaches for the network,
          // fails, and the screen honestly grows a note saying the training
          // days could not be loaded, which pushes Generate off a 600px
          // viewport.
          profileProvider.overrideWith(() => _FakeProfileNotifier(const [])),
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
          // These three tests are about generate, refresh and pop, not about
          // the profile -- but without an override it reaches for the network,
          // fails, and the screen honestly grows a note saying the training
          // days could not be loaded, which pushes Generate off a 600px
          // viewport.
          profileProvider.overrideWith(() => _FakeProfileNotifier(const [])),
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
          // These three tests are about generate, refresh and pop, not about
          // the profile -- but without an override it reaches for the network,
          // fails, and the screen honestly grows a note saying the training
          // days could not be loaded, which pushes Generate off a 600px
          // viewport.
          profileProvider.overrideWith(() => _FakeProfileNotifier(const [])),
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

    testWidgets('the sentence counts the days the picker shows', (tester) async {
      // The plan's stored label still says four; the user has ticked three.
      // The card sits directly above the picker, so composing from the plan
      // puts "train 4 days a week" over three ticked cells -- a contradiction
      // on one screen, not the stale label section 4 of the design allows
      // for. Generate would meanwhile send 3.
      await _pump(tester, plan: _pplPlan, trainingDays: const [1, 3, 5]);

      expect(fieldText(tester), contains('train 3 days a week'));
      expect(_ticked(tester), 3,
          reason: 'the sentence and the cells must describe one schedule');
    });

    testWidgets('a day count the picker overrules is reported, not swallowed',
        (tester) async {
      // _resolve takes the count from the chosen days, so the applied number
      // has nowhere to land. It cannot simply be dropped: parsed.isEmpty is
      // false -- the split did land -- so "Nothing in that changed your plan"
      // never prints either, and Apply looks like it did nothing at all.
      await _pump(tester, plan: _pplPlan, trainingDays: const [1, 3, 5]);

      await write(tester, 'full body, 5 days a week');
      await apply(tester);

      expect(find.byKey(const Key('gen.describe.elsewhere')), findsOneWidget);
      expect(find.textContaining('weekdays you have chosen'), findsOneWidget);

      final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
      expect(screen.debugDaysPerWeek, 3,
          reason: 'the picker sets the count while any day is chosen');
    });

    testWidgets('with no days chosen the count lands and nothing is reported',
        (tester) async {
      // The other half of the pair: with nothing ticked the sentence's count
      // IS what the controls take, so saying it went nowhere would be false.
      await _pump(tester, plan: _pplPlan, trainingDays: const []);

      await write(tester, 'full body, 5 days a week');
      await apply(tester);

      expect(find.byKey(const Key('gen.describe.elsewhere')), findsNothing);
      final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
      expect(screen.debugDaysPerWeek, 5);
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

  testWidgets('the screen does not state a session length', (tester) async {
    // The service derives length from goal and fitness level; this screen
    // cannot change it and showing it only invited the question. It is still
    // resolved and still sent -- dropping it from the payload would hand the
    // service's own 45-minute default a 60-minute plan and shorten it.
    await _pump(tester, plan: _pplPlan);

    expect(find.byKey(const Key('gen.length.value')), findsNothing);
    expect(find.textContaining('Session length'), findsNothing);
    expect(find.text('60 min'), findsNothing);
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
