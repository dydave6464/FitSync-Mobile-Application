import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/onboarding/presentation/edit_scaffold.dart';
import 'package:fitsync/features/onboarding/presentation/onboarding_scaffold.dart';
import 'package:fitsync/features/onboarding/presentation/steps/about_step.dart';
import 'package:fitsync/features/onboarding/presentation/steps/goal_step.dart';
import 'package:fitsync/features/onboarding/presentation/steps/injuries_step.dart';
import 'package:fitsync/features/onboarding/presentation/steps/level_step.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/settings/presentation/settings_screen.dart';

const _profile = Profile(
  userId: 7,
  email: 'juan@example.com',
  fullName: 'Juan Dela Cruz',
  onboardingCompleted: true,
  isPremium: false,
  notificationsEnabled: true,
  equipment: [],
  injuries: [],
  city: 'Cebu City',
  mainGoal: 'lose_weight',
);

const _equipment = [EquipmentOption(equipmentId: 41, name: 'Resistance band')];
const _injuryOptions = [
  InjuryOption(
    injuryId: 1,
    name: 'Shoulder',
    isLateral: true,
    regionGroup: 'upper_body',
  ),
];

class FakeProfileNotifier extends ProfileNotifier {
  FakeProfileNotifier(this.patches);

  final List<Map<String, dynamic>> patches;

  @override
  Future<Profile> build() async => _profile;

  @override
  Future<void> patch(Map<String, dynamic> fields) async => patches.add(fields);

  @override
  Future<void> setEquipment(List<int> equipmentIds) async {}

  @override
  Future<void> setInjuries(List<SelectedInjury> injuries) async {}
}

class RecordingAuthController extends AuthController {
  RecordingAuthController(this.signOuts);

  final List<bool> signOuts;

  @override
  Future<AuthState> build() async => AuthState(
        AuthStatus.ready,
        const AuthUser(
          userId: 7,
          email: 'juan@example.com',
          fullName: 'Juan Dela Cruz',
          onboardingCompleted: true,
          isPremium: false,
        ),
      );

  @override
  Future<void> signOut() async {
    signOuts.add(true);
    state = const AsyncData(AuthState.signedOut);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> patches,
  List<bool>? signOuts,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => FakeProfileNotifier(patches)),
      authControllerProvider
          .overrideWith(() => RecordingAuthController(signOuts ?? [])),
      equipmentOptionsProvider.overrideWith((ref) async => _equipment),
      injuryOptionsProvider.overrideWith((ref) async => _injuryOptions),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openRow(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows who is signed in', (tester) async {
    await _pump(tester, patches: []);

    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.textContaining('Cebu City'), findsOneWidget);
  });

  testWidgets('offers no language row', (tester) async {
    await _pump(tester, patches: []);

    // English only, per the spec. A row that does nothing is worse than none.
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('each row opens its step inside the edit scaffold',
      (tester) async {
    await _pump(tester, patches: []);

    for (final row in [
      (key: const Key('edit.goal'), type: GoalStep),
      (key: const Key('edit.about'), type: AboutStep),
      (key: const Key('edit.level'), type: LevelStep),
      (key: const Key('edit.injuries'), type: InjuriesStep),
    ]) {
      await _openRow(tester, row.key);

      expect(find.byType(EditScaffold), findsOneWidget,
          reason: '${row.key} must open an editor, not a wizard step');
      expect(find.byType(row.type), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('saving an edited goal patches it and returns', (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pump(tester, patches: patches);

    await _openRow(tester, const Key('edit.goal'));
    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    expect(patches.single, {'mainGoal': 'build_muscle'});
    expect(find.byType(EditScaffold), findsNothing,
        reason: 'a successful save should return to Settings');
  });

  testWidgets('the notifications toggle writes the new value', (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pump(tester, patches: patches);

    await tester.ensureVisible(find.byKey(const Key('notifications')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notifications')));
    await tester.pumpAndSettle();

    expect(patches.single, {'notificationsEnabled': false});
  });

  testWidgets('sign out clears the session', (tester) async {
    final signOuts = <bool>[];
    await _pump(tester, patches: [], signOuts: signOuts);

    await tester.ensureVisible(find.byKey(const Key('signOut')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signOut')));
    await tester.pumpAndSettle();

    expect(signOuts, [true]);
  });

  testWidgets('the same step widget renders under both scaffolds',
      (tester) async {
    // The point of the two-scaffold design. If this ever needs a flag on the
    // step to pass, the boundary has leaked and Task 10 stops being wiring.
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScaffold(
        step: 1,
        total: 4,
        onContinue: () {},
        child: GoalStep(value: null, onChanged: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal.lose_weight')), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: EditScaffold(
        title: 'Goal',
        onSave: () {},
        child: GoalStep(value: null, onChanged: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal.lose_weight')), findsOneWidget);
  });
}
