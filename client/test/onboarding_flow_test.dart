import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/onboarding/presentation/onboarding_flow.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

Profile _emptyProfile() => const Profile(
      userId: 7,
      email: 'juan@example.com',
      fullName: 'Juan Dela Cruz',
      onboardingCompleted: false,
      isPremium: false,
      notificationsEnabled: true,
      equipment: [],
      injuries: [],
    );

const _equipment = [EquipmentOption(equipmentId: 41, name: 'Resistance band')];
const _injuries = [
  InjuryOption(
    injuryId: 1,
    name: 'Shoulder',
    isLateral: true,
    regionGroup: 'upper_body',
  ),
];

class FakeProfileNotifier extends ProfileNotifier {
  FakeProfileNotifier(
    this.patches, {
    this.onPatch,
    this.equipmentWrites,
    this.injuryWrites,
    this.completions,
    this.onComplete,
  });

  final List<Map<String, dynamic>> patches;
  final Future<void> Function()? onPatch;
  final List<List<int>>? equipmentWrites;
  final List<List<SelectedInjury>>? injuryWrites;
  final List<int>? completions;

  /// Called before each completion resolves, so a test can fail the first
  /// attempt and succeed on the retry.
  final Future<void> Function(int attempt)? onComplete;

  @override
  Future<Profile> build() async => _emptyProfile();

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
    patches.add(fields);
    if (onPatch != null) await onPatch!();
  }

  @override
  Future<void> setEquipment(List<int> equipmentIds) async {
    equipmentWrites?.add(equipmentIds);
  }

  @override
  Future<void> setInjuries(List<SelectedInjury> injuries) async {
    injuryWrites?.add(injuries);
  }

  @override
  Future<CompletedOnboarding> completeOnboarding() async {
    final attempt = completions?.length ?? 0;
    completions?.add(attempt);
    if (onComplete != null) await onComplete!(attempt);
    return (profile: _emptyProfile(), plan: const {'planId': 42});
  }
}

/// Records the shell hand-off so a test can prove onboarding actually ends.
class RecordingAuthController extends AuthController {
  RecordingAuthController(this.completed);

  final List<bool> completed;

  @override
  Future<AuthState> build() async => AuthState(
        AuthStatus.onboarding,
        const AuthUser(
          userId: 7,
          email: 'juan@example.com',
          fullName: 'Juan Dela Cruz',
          onboardingCompleted: false,
          isPremium: false,
        ),
      );

  @override
  void onOnboardingCompleted() {
    completed.add(true);
    super.onOnboardingCompleted();
  }
}

/// Both lookup providers are always stubbed, even for tests that never reach
/// steps 3 and 4. Leaving one live means the first `pumpAndSettle` after
/// arriving at that step waits forever on its loading spinner.
Future<void> _pumpFlow(
  WidgetTester tester, {
  required List<Map<String, dynamic>> patches,
  Future<void> Function()? onPatch,
  List<List<int>>? equipmentWrites,
  List<List<SelectedInjury>>? injuryWrites,
  List<int>? completions,
  Future<void> Function(int attempt)? onComplete,
  List<bool>? completed,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => FakeProfileNotifier(
            patches,
            onPatch: onPatch,
            equipmentWrites: equipmentWrites,
            injuryWrites: injuryWrites,
            completions: completions,
            onComplete: onComplete,
          )),
      authControllerProvider
          .overrideWith(() => RecordingAuthController(completed ?? [])),
      equipmentOptionsProvider.overrideWith((ref) async => _equipment),
      injuryOptionsProvider.overrideWith((ref) async => _injuries),
    ],
    child: const MaterialApp(home: OnboardingFlow()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> _skip(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('skip')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts on step 1 of 4', (tester) async {
    await _pumpFlow(tester, patches: []);

    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.byKey(const Key('goal.lose_weight')), findsOneWidget);
  });

  testWidgets('Continue saves the step and advances', (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpFlow(tester, patches: patches);

    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(patches, [
      {'mainGoal': 'build_muscle'}
    ], reason: 'a dropout after step 1 must still have their goal saved');
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('Skip advances without saving', (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpFlow(tester, patches: patches);

    await _skip(tester);

    expect(patches, isEmpty);
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('Continue with nothing chosen saves nothing but still advances',
      (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpFlow(tester, patches: patches);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(patches, isEmpty, reason: 'an empty patch is a pointless round trip');
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('a failed save shows the message and stays on the step',
      (tester) async {
    await _pumpFlow(
      tester,
      patches: [],
      onPatch: () async => throw const ApiException(
          'INVALID_PROFILE_FIELD', 'That goal is not one we recognise.'),
    );

    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(find.text('That goal is not one we recognise.'), findsOneWidget);
    expect(find.text('Step 1 of 4'), findsOneWidget,
        reason: 'advancing past a step whose answer was rejected would lose it');
  });

  testWidgets('step 3 saves the level fields and the equipment set',
      (tester) async {
    final patches = <Map<String, dynamic>>[];
    final equipmentWrites = <List<int>>[];
    await _pumpFlow(tester, patches: patches, equipmentWrites: equipmentWrites);

    await _skip(tester);
    await _skip(tester);
    expect(find.text('Step 3 of 4'), findsOneWidget);

    await _tapKey(tester, const Key('level.beginner'));
    await _tapKey(tester, const Key('equipment.41'));
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(patches.single, {'fitnessLevel': 'beginner'});
    expect(equipmentWrites.single, [41],
        reason: 'equipment is a replace-set write, not part of the patch');
    expect(find.text('Step 4 of 4'), findsOneWidget);
  });

  testWidgets('step 4 saves the injury set, empty included', (tester) async {
    final injuryWrites = <List<SelectedInjury>>[];
    await _pumpFlow(tester, patches: [], injuryWrites: injuryWrites);

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    expect(find.text('Step 4 of 4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    // "Nothing hurts" is the common answer and has to be savable.
    expect(injuryWrites.single, isEmpty);
  });

  testWidgets('the last step offers to generate the plan', (tester) async {
    await _pumpFlow(tester, patches: []);

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);

    expect(find.text('Generate my plan'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('generating the plan completes onboarding and hands off',
      (tester) async {
    final completions = <int>[];
    final completed = <bool>[];
    await _pumpFlow(
      tester,
      patches: [],
      completions: completions,
      completed: completed,
    );

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(completions, hasLength(1));
    expect(completed, [true],
        reason: 'the shell has to be told, or the user stays in onboarding');
  });

  testWidgets('a failed generation can be retried', (tester) async {
    final completions = <int>[];
    await _pumpFlow(
      tester,
      patches: [],
      completions: completions,
      onComplete: (attempt) async {
        // The server leaves onboarding incomplete when generation fails,
        // precisely so this retry is possible.
        if (attempt == 0) {
          throw const ApiException(
              'PLAN_GENERATION_FAILED', 'Could not build a plan right now.');
        }
      },
    );

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(find.text('Could not build a plan right now.'), findsOneWidget);
    expect(find.text('Step 4 of 4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(completions, hasLength(2));
  });

  testWidgets('back returns to the previous step', (tester) async {
    await _pumpFlow(tester, patches: []);

    await _skip(tester);
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 4'), findsOneWidget);
  });
}
