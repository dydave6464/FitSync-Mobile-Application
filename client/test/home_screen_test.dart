import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/home/presentation/home_screen.dart';
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
  });

  testWidgets('a failed plan load offers a retry', (tester) async {
    await _pumpHome(tester,
        planError: const ApiException('X', 'Server is down'));
    expect(find.text('Retry'), findsOneWidget);
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
