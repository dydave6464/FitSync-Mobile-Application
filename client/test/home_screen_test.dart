import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/home/presentation/home_screen.dart';
import 'package:fitsync/features/home/presentation/widgets/greeting.dart';
import 'package:fitsync/features/home/presentation/widgets/plan_card.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

const _someEquipment = [EquipmentOption(equipmentId: 1, name: 'Dumbbells')];

Profile _profile({
  String fullName = 'Juan Dela Cruz',
  String? mainGoal = 'build_muscle',
  String? fitnessLevel = 'beginner',
  List<EquipmentOption> equipment = _someEquipment,
}) =>
    Profile(
      userId: 1,
      email: 'juan@example.com',
      fullName: fullName,
      onboardingCompleted: true,
      isPremium: false,
      notificationsEnabled: true,
      equipment: equipment,
      injuries: const [],
      mainGoal: mainGoal,
      fitnessLevel: fitnessLevel,
    );

const _defaultPlan = WorkoutPlan(
  planId: 1,
  name: 'Upper Body · Push',
  splitStyle: 'upper_lower',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [
    PlanExercise(
      planExerciseId: 301,
      exerciseId: 1,
      name: 'Bench press',
      muscleGroup: 'chest',
      orderNo: 1,
      targetSets: 3,
      targetReps: '8-12',
    ),
  ],
);

/// A fixed answer instead of a repository round trip — same shape as
/// FakeProfileNotifier in onboarding_flow_test.dart.
class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier(this.profile);

  final Profile profile;

  @override
  Future<Profile> build() async => profile;
}

Future<void> _pumpHome(
  WidgetTester tester, {
  VoidCallback? onGoToTrain,
  VoidCallback? onGoToProfile,
  Profile? profile,
  WorkoutPlan? plan = _defaultPlan,
  ApiException? planError,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider
            .overrideWith(() => _StubProfileNotifier(profile ?? _profile())),
        activePlanProvider.overrideWith((ref) async {
          if (planError != null) throw planError;
          return plan;
        }),
      ],
      child: MaterialApp(
        home: HomeScreen(
          onGoToTrain: onGoToTrain,
          onGoToProfile: onGoToProfile,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('start workout and the nudge each select their tab',
      (tester) async {
    final selected = <String>[];
    await _pumpHome(tester,
        onGoToTrain: () => selected.add('train'),
        onGoToProfile: () => selected.add('profile'),
        profile: _profile(mainGoal: null));

    await tester.tap(find.text('Finish your profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();

    expect(selected, ['profile', 'train'],
        reason: 'Home selects tabs; it never pushes a second PlanScreen');
  });

  testWidgets('a null plan explains itself and offers no generate action',
      (tester) async {
    await _pumpHome(tester, plan: null);
    expect(find.text('Start workout'), findsNothing);
    expect(find.textContaining('no active plan'), findsOneWidget);
    expect(find.byKey(const Key('home.noPlan')), findsOneWidget,
        reason: 'the descendant check below is vacuous if this key does not '
            'resolve to the no-plan card');
    // Absence of the one specific label is not enough — a relabelled
    // "Generate plan" button would satisfy both assertions above. The
    // no-plan state must offer no action at all, so nothing tappable may
    // exist inside it: there is no on-demand generate endpoint, so a
    // button here would call nothing. Scoped to the home.noPlan-keyed
    // subtree, not the whole screen, so this can't be satisfied or defeated
    // by an unrelated FsButton elsewhere (e.g. a retry button in another
    // state). This key is distinct from PlanScreen's own 'noPlan' key —
    // both tabs build eagerly once visited, and with no active plan both
    // no-plan states can exist in the tree at once, so a shared key would
    // leave any finder using it ambiguous.
    expect(
      find.descendant(
        of: find.byKey(const Key('home.noPlan')),
        matching: find.byType(FsButton),
      ),
      findsNothing,
      reason: 'the no-plan state must offer no action; a "Generate plan" '
          'button would call an endpoint that does not exist',
    );
  });

  testWidgets('a failed plan load offers a retry', (tester) async {
    await _pumpHome(tester,
        planError: const ApiException('X', 'Server is down'));
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets(
      'a complete profile leaves no gap where the nudge would have been',
      (tester) async {
    // Both the nudge and its trailing SizedBox(height: 14) live inside the
    // same `if (profileNeedsFinishing(p))` block in home_screen.dart. If
    // that SizedBox ever escaped the conditional (e.g. moved below the
    // closing bracket), the nudge would still correctly disappear for a
    // complete profile, but a 14px gap would remain — invisible to a test
    // that only checks the nudge is absent. Measuring the actual on-screen
    // distance between Greeting and the plan card is what catches that:
    // with the nudge suppressed, only the fixed SizedBox(height: 20) after
    // Greeting should separate them.
    await _pumpHome(tester); // default profile is complete; default plan renders

    expect(find.text('Finish your profile'), findsNothing);

    final greetingBottom = tester.getBottomLeft(find.byType(Greeting)).dy;
    final planCardTop = tester.getTopLeft(find.byType(PlanCard)).dy;

    expect(planCardTop - greetingBottom, moreOrLessEquals(20),
        reason: 'only the base 20px gap after Greeting should separate it '
            'from the plan card when the nudge does not render; a leftover '
            '14px would mean the nudge\'s SizedBox escaped its conditional');
  });

  testWidgets(
      'the assembled screen does not overflow at 2.0x text scale on a '
      'narrow phone', (tester) async {
    // 320dp mirrors a small phone; 2.0x mirrors Android 14's maximum text
    // scale. Greeting's name text carries no maxLines/Flexible guard of its
    // own — it is safe only because the ListView here leaves it
    // unconstrained the way Greeting's own widget test does. This kit has
    // shipped four text-scale overflow defects already, so the assembled
    // screen gets its own guard rather than trusting each widget's
    // isolated test to cover the composition. mainGoal: null also mounts
    // the nudge, so all three stacked sections are exercised together.
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpHome(tester, profile: _profile(mainGoal: null));

    expect(tester.takeException(), isNull);
  });
}
