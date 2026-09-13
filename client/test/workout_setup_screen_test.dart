import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/exercises/presentation/exercise_list_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/training_day.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/workout_setup_screen.dart';

/// A 60-minute plan: the length readout and the target count both read it,
/// and 60 is the half of `EXERCISES_BY_SESSION` that is not the fallback, so
/// a screen that quietly ignored the plan would still look right on 45.
const _plan = WorkoutPlan(
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

WorkoutPlan _planOfLength(int minutes) => WorkoutPlan(
      planId: 7,
      name: 'Week 1',
      splitStyle: 'full_body',
      daysPerWeek: 3,
      sessionLengthMin: minutes,
      weekNo: 1,
      days: const [PlanDay(dayNo: 1, name: 'Full body')],
      exercises: const [],
    );

/// A profile carrying exactly the injuries a test wants the card to render.
/// Everything else is a fixed stand-in -- this screen only reads `.injuries`.
class _FakeProfileNotifier extends ProfileNotifier {
  _FakeProfileNotifier(this.injuries);

  final List<SelectedInjury> injuries;

  @override
  Future<Profile> build() async => Profile(
        userId: 1,
        email: 'test@example.com',
        fullName: 'Test User',
        onboardingCompleted: true,
        isPremium: false,
        notificationsEnabled: true,
        equipment: const [],
        injuries: injuries,
      );
}

Future<void> _pump(
  WidgetTester tester, {
  WorkoutPlan? plan,
  List<SelectedInjury> injuries = const [],
  List<InjuryOption> injuryOptions = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => plan),
        profileProvider.overrideWith(() => _FakeProfileNotifier(injuries)),
        injuryOptionsProvider.overrideWith((ref) async => injuryOptions),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: const WorkoutSetupScreen(),
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

/// What the catalogue is currently narrowed to. Read from the live tree
/// rather than a captured container, because the setup screen sets it around
/// the push and clears it on the way back.
List<String> _constraintIn(WidgetTester tester) => ProviderScope.containerOf(
      // skipOffstage: false -- once the library is pushed the setup screen is
      // still mounted behind an opaque route, which find hides by default.
      tester.element(find.byType(WorkoutSetupScreen, skipOffstage: false)),
    ).read(catalogueConstraintProvider);

void main() {
  testWidgets('every training day is offered', (tester) async {
    // Days, not splits. A split is a rotation of days, and filtering by a
    // whole one barely filters: push_pull_legs covered 997 of 1,203 live
    // exercises and upper_lower covered the identical set.
    await _pump(tester, plan: _plan);

    for (final day in trainingDays) {
      expect(find.text(day.label), findsOneWidget);
    }
  });

  testWidgets('full body is the day the screen opens on', (tester) async {
    // Deliberately not derived from the plan: this screen starts one workout
    // rather than describing the week the plan already holds, so nothing
    // about the plan says what today should be.
    await _pump(tester, plan: _plan);

    expect(_chipOn(tester, 'Full body'), isTrue);
    expect(_chipOn(tester, 'Push'), isFalse);
  });

  testWidgets('tapping a day selects it', (tester) async {
    await _pump(tester, plan: _plan);

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();

    expect(_chipOn(tester, 'Push'), isTrue);
    expect(_chipOn(tester, 'Full body'), isFalse);
  });

  testWidgets('the session length readout follows the active plan',
      (tester) async {
    await _pump(tester, plan: _plan);

    expect(
      tester.widget<Text>(find.byKey(const Key('setup.length.value'))).data,
      '60 min',
    );
  });

  testWidgets('with no plan the session length falls back to 45',
      (tester) async {
    // The service's own default for a session it was given no override for,
    // so a plan-less user is shown the length they would actually get.
    await _pump(tester, plan: null);

    expect(
      tester.widget<Text>(find.byKey(const Key('setup.length.value'))).data,
      '45 min',
    );
  });

  testWidgets('the session length is a readout, not a control', (tester) async {
    // The service derives length from goal and fitness level; this screen
    // cannot change it and must not look like it can. Asserted on the
    // gesture widgets rather than by tapping, because a tap that changes
    // nothing passes whether or not the row invites one.
    await _pump(tester, plan: _plan);

    final value = find.byKey(const Key('setup.length.value'));
    // Without this the two findsNothing below hold for a screen that has no
    // length row at all.
    expect(value, findsOneWidget);
    expect(find.ancestor(of: value, matching: find.byType(InkWell)), findsNothing);
    expect(
      find.ancestor(of: value, matching: find.byType(GestureDetector)),
      findsNothing,
    );
  });

  /// What the target row says, for the lengths the ML service's
  /// `EXERCISES_BY_SESSION` is keyed on and the ones it is not.
  Future<String?> targetFor(WidgetTester tester, int minutes) async {
    await _pump(tester, plan: _planOfLength(minutes));
    return tester.widget<Text>(find.byKey(const Key('setup.target.value'))).data;
  }

  testWidgets('a 45-minute session aims for 6 exercises', (tester) async {
    expect(await targetFor(tester, 45), '6');
  });

  testWidgets('a 60-minute session aims for 8 exercises', (tester) async {
    expect(await targetFor(tester, 60), '8');
  });

  // The table has two entries and a plan's length is not required to be one
  // of them, so the count is snapped the way `_snap` in
  // ml/app/rules/parameters.py snaps it rather than left blank. One pump per
  // length: re-pumping inside a single test leaves activePlanProvider on the
  // value the first override produced.
  for (final (minutes, target) in const [(30, '6'), (52, '6'), (53, '8'), (90, '8')]) {
    testWidgets('a $minutes-minute session snaps to $target exercises',
        (tester) async {
      expect(await targetFor(tester, minutes), target);
    });
  }

  testWidgets('the avoiding card names the profile injuries', (tester) async {
    // Displayed, not sent: the library filters server-side from the profile,
    // which is what stops a client picking around someone else's injuries.
    await _pump(
      tester,
      plan: _plan,
      injuries: const [SelectedInjury(injuryId: 3, side: 'right')],
      injuryOptions: const [
        InjuryOption(injuryId: 3, name: 'Knee', isLateral: true, regionGroup: 'leg'),
        InjuryOption(injuryId: 9, name: 'Lower back', isLateral: false, regionGroup: 'back'),
      ],
    );

    // The whole join, so an unselected option leaking in or a hard-coded side
    // fails rather than passing on a substring.
    expect(find.text('Avoiding: Knee (right)'), findsOneWidget);
  });

  testWidgets('with no injuries the card is absent', (tester) async {
    // An "Avoiding: nothing" card is noise on a screen whose job is to get
    // the user into the library.
    await _pump(tester, plan: _plan, injuries: const []);

    expect(find.byKey(const Key('setup.avoiding')), findsNothing);
  });

  testWidgets('Select Exercise opens the library to pick from', (tester) async {
    await _pump(tester, plan: _plan);

    expect(find.text('Select Exercise'), findsOneWidget);

    await tester.tap(find.byKey(const Key('setup.select')));
    // Pumped rather than settled: the pushed list shows a progress indicator
    // while it fetches, and that animates forever, so pumpAndSettle would
    // wait out the timeout instead of the route transition.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final picker = tester.widget<ExerciseListScreen>(find.byType(ExerciseListScreen));
    expect(picker.selecting, isTrue,
        reason: 'the same list, but picking rather than browsing');
    expect(_constraintIn(tester), isEmpty,
        reason: 'full body filters nothing, as splits.py defines it');
  });

  testWidgets('the chosen day is what the library gets filtered by',
      (tester) async {
    await _pump(tester, plan: _plan);

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setup.select')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ExerciseListScreen), findsOneWidget);
    expect(_constraintIn(tester),
        ['pectorals', 'delts', 'triceps']);
  });

  testWidgets('the setup screen stays behind the picker', (tester) async {
    // Pushed, not replaced: coming back from the library must land on the
    // setup screen the user came from rather than dumping them wherever the
    // "+" sheet was opened.
    await _pump(tester, plan: _plan);

    await tester.tap(find.byKey(const Key('setup.select')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Log a workout'), findsOneWidget);
  });

  testWidgets('a failed plan fetch is not reported as a 45-minute session',
      (tester) async {
    // Flattening loading and failure into "no plan" costs a flash while the
    // fetch is in flight and a permanent falsehood when it fails: the screen
    // states a length and a target it never read, about a plan the user does
    // have. Saying nothing is the honest answer.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => throw Exception('boom')),
        profileProvider.overrideWith(() => _FakeProfileNotifier(const [])),
        injuryOptionsProvider.overrideWith((ref) async => const <InjuryOption>[]),
      ],
      child: MaterialApp(theme: fsLightTheme(), home: const WorkoutSetupScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('45 min'), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('setup.length.value'))).data, '—');
    expect(tester.widget<Text>(find.byKey(const Key('setup.target.value'))).data, '—');
  });
}
