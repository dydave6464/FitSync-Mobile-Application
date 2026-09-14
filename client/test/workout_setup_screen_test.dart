import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/exercises/presentation/exercise_list_screen.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/plans/domain/split_style.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/workout_setup_screen.dart';

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
/// rather than a captured container, because a screen that narrowed it would
/// do so around the push.
List<String> _constraintIn(WidgetTester tester) => ProviderScope.containerOf(
      // skipOffstage: false -- once the library is pushed the setup screen is
      // still mounted behind an opaque route, which find hides by default.
      tester.element(find.byType(WorkoutSetupScreen, skipOffstage: false)),
    ).read(catalogueConstraintProvider);

Future<void> _openLibrary(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('setup.select')));
  // Pumped rather than settled: the pushed list shows a progress indicator
  // while it fetches, and that animates forever, so pumpAndSettle would
  // wait out the timeout instead of the route transition.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('every split style is offered', (tester) async {
    // The same four the generator offers, from the same list, so a rename
    // cannot land on one screen and not the other.
    await _pump(tester, plan: _plan);

    for (final style in splitStyles) {
      expect(find.text(style.label), findsOneWidget);
    }
  });

  testWidgets('Push / Pull / Legs is one chip, not three', (tester) async {
    // A split is named as the rotation it is. Three separate chips read as
    // three choices when they are one.
    await _pump(tester, plan: _plan);

    expect(find.text('Push / Pull / Legs'), findsOneWidget);
    expect(find.text('Push'), findsNothing);
    expect(find.text('Pull'), findsNothing);
    expect(find.text('Legs'), findsNothing);
  });

  testWidgets('full body is the split the screen opens on', (tester) async {
    // Deliberately not derived from the plan: this screen starts one workout
    // rather than describing the week the plan already holds, so nothing
    // about the plan says what today should be.
    await _pump(tester, plan: _plan);

    expect(_chipOn(tester, 'Full body'), isTrue);
    expect(_chipOn(tester, 'Push / Pull / Legs'), isFalse);
  });

  testWidgets('tapping a split selects it', (tester) async {
    await _pump(tester, plan: _plan);

    await tester.tap(find.text('Push / Pull / Legs'));
    await tester.pumpAndSettle();

    expect(_chipOn(tester, 'Push / Pull / Legs'), isTrue);
    expect(_chipOn(tester, 'Full body'), isFalse);
  });

  testWidgets('the screen does not state a session length', (tester) async {
    // It drove nothing once the target count went: the service derives length
    // from goal and fitness level, and this screen neither sends it nor lets
    // it be changed. A number on screen that nothing here reads or writes is
    // furniture the user has to rule out.
    await _pump(tester, plan: _plan);

    expect(find.byKey(const Key('setup.length.value')), findsNothing);
    expect(find.text('60 min'), findsNothing);
    expect(find.textContaining('Session length'), findsNothing);
  });

  testWidgets('the screen does not state a target exercise count',
      (tester) async {
    await _pump(tester, plan: _plan);

    expect(find.byKey(const Key('setup.target.value')), findsNothing);
    expect(find.textContaining('Target exercises'), findsNothing);
  });

  testWidgets('a failed plan fetch leaves the screen usable', (tester) async {
    // Nothing on this screen reads the plan any more, so a plan that will not
    // load must not cost the user the library. This is the regression guard
    // for re-introducing a plan read without an error branch under it.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => throw Exception('boom')),
        profileProvider.overrideWith(() => _FakeProfileNotifier(const [])),
        injuryOptionsProvider.overrideWith((ref) async => const <InjuryOption>[]),
      ],
      child: MaterialApp(theme: fsLightTheme(), home: const WorkoutSetupScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Full body'), findsOneWidget);
    expect(find.byKey(const Key('setup.select')), findsOneWidget);
  });

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
    await _openLibrary(tester);

    final picker = tester.widget<ExerciseListScreen>(find.byType(ExerciseListScreen));
    expect(picker.selecting, isTrue,
        reason: 'the same list, but picking rather than browsing');
  });

  testWidgets('the library opens on the whole catalogue whatever the split',
      (tester) async {
    // A split is a rotation of days, and constraining the catalogue to the
    // whole of one barely constrains it: push_pull_legs left 997 of 1,203
    // live exercises and upper_lower left the identical set. So the chip
    // describes the workout and the library stays wide, to be narrowed by the
    // filter chips and the search box instead.
    await _pump(tester, plan: _plan);

    await tester.tap(find.text('Push / Pull / Legs'));
    await tester.pumpAndSettle();
    await _openLibrary(tester);

    expect(find.byType(ExerciseListScreen), findsOneWidget);
    expect(_constraintIn(tester), isEmpty);
  });

  testWidgets('the setup screen stays behind the picker', (tester) async {
    // Pushed, not replaced: coming back from the library must land on the
    // setup screen the user came from rather than dumping them wherever the
    // "+" sheet was opened.
    await _pump(tester, plan: _plan);

    await _openLibrary(tester);

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Log a workout'), findsOneWidget);
  });
}
