import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/onboarding/presentation/onboarding_flow.dart';
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

class FakeProfileNotifier extends ProfileNotifier {
  FakeProfileNotifier(this.patches, {this.onPatch, this.equipmentWrites});

  final List<Map<String, dynamic>> patches;
  final Future<void> Function()? onPatch;
  final List<List<int>>? equipmentWrites;

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
}

Future<List<Map<String, dynamic>>> _pumpFlow(
  WidgetTester tester, {
  Future<void> Function()? onPatch,
}) async {
  final patches = <Map<String, dynamic>>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileProvider.overrideWith(() => FakeProfileNotifier(patches, onPatch: onPatch)),
    ],
    child: const MaterialApp(home: OnboardingFlow()),
  ));
  await tester.pumpAndSettle();
  return patches;
}

void main() {
  testWidgets('starts on step 1 of 4', (tester) async {
    await _pumpFlow(tester);

    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.byKey(const Key('goal.lose_weight')), findsOneWidget);
  });

  testWidgets('Continue saves the step and advances', (tester) async {
    final patches = await _pumpFlow(tester);

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
    final patches = await _pumpFlow(tester);

    await tester.tap(find.byKey(const Key('skip')));
    await tester.pumpAndSettle();

    expect(patches, isEmpty);
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('Continue with nothing chosen saves nothing but still advances',
      (tester) async {
    final patches = await _pumpFlow(tester);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(patches, isEmpty, reason: 'an empty patch is a pointless round trip');
    expect(find.text('Step 2 of 4'), findsOneWidget);
  });

  testWidgets('a failed save shows the message and stays on the step',
      (tester) async {
    await _pumpFlow(
      tester,
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
    await tester.pumpWidget(ProviderScope(
      overrides: [
        profileProvider.overrideWith(() => FakeProfileNotifier(
              patches,
              equipmentWrites: equipmentWrites,
            )),
        equipmentOptionsProvider.overrideWith((ref) async => const [
              EquipmentOption(equipmentId: 41, name: 'Resistance band'),
            ]),
      ],
      child: const MaterialApp(home: OnboardingFlow()),
    ));
    await tester.pumpAndSettle();

    // Skip to step 3.
    await tester.tap(find.byKey(const Key('skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skip')));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('level.beginner')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('equipment.41')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('equipment.41')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(patches.single, {'fitnessLevel': 'beginner'});
    expect(equipmentWrites.single, [41],
        reason: 'equipment is a replace-set write, not part of the patch');
    expect(find.text('Step 4 of 4'), findsOneWidget);
  });

  testWidgets('back returns to the previous step', (tester) async {
    await _pumpFlow(tester);

    await tester.tap(find.byKey(const Key('skip')));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 4'), findsOneWidget);
  });
}
