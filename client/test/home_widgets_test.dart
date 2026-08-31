import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/home/presentation/widgets/greeting.dart';
import 'package:fitsync/features/home/presentation/widgets/profile_nudge.dart';
import 'package:fitsync/features/profile/domain/profile.dart';

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

const _someEquipment = [EquipmentOption(equipmentId: 1, name: 'Dumbbells')];

Profile _profile({
  String fullName = 'Juan Dela Cruz',
  DateTime? joinedAt,
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
      joinedAt: joinedAt,
    );

void main() {
  testWidgets('the greeting shows initials, first name and the day count',
      (tester) async {
    await tester.pumpWidget(_host(Greeting(
      profile: _profile(fullName: 'Juan Dela Cruz',
          joinedAt: DateTime.utc(2026, 8, 1)),
      now: DateTime.utc(2026, 8, 31),
    )));

    expect(find.text('JC'), findsOneWidget, reason: 'first and last initials');
    expect(find.text('Kumusta, Juan'), findsOneWidget);
    expect(find.textContaining('Day 31'), findsOneWidget,
        reason: '30 whole days elapsed, plus one so the join date is Day 1');
  });

  testWidgets('a single-word name yields one initial', (tester) async {
    await tester.pumpWidget(_host(Greeting(
      profile: _profile(fullName: 'Juan', joinedAt: DateTime.utc(2026, 8, 31)),
      now: DateTime.utc(2026, 8, 31),
    )));
    expect(find.text('J'), findsOneWidget);
    expect(find.textContaining('Day 1'), findsOneWidget,
        reason: 'the join date itself is Day 1, never Day 0');
  });

  testWidgets('the nudge fires on each missing field independently',
      (tester) async {
    for (final profile in [
      _profile(mainGoal: null, fitnessLevel: 'beginner', equipment: _someEquipment),
      _profile(mainGoal: 'build_muscle', fitnessLevel: null, equipment: _someEquipment),
      _profile(mainGoal: 'build_muscle', fitnessLevel: 'beginner', equipment: const []),
    ]) {
      await tester.pumpWidget(_host(ProfileNudge(profile: profile, onTap: () {})));
      expect(find.text('Finish your profile'), findsOneWidget);
    }
  });

  testWidgets('the nudge renders nothing when the profile is complete',
      (tester) async {
    await tester.pumpWidget(_host(ProfileNudge(
      profile: _profile(mainGoal: 'build_muscle', fitnessLevel: 'beginner',
          equipment: _someEquipment),
      onTap: () {},
    )));
    expect(find.text('Finish your profile'), findsNothing);
    expect(find.byType(FsCard), findsNothing,
        reason: 'nothing, not an empty card');
  });
}
