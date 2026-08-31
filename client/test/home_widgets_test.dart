import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/home/presentation/widgets/greeting.dart';
import 'package:fitsync/features/home/presentation/widgets/plan_card.dart';
import 'package:fitsync/features/home/presentation/widgets/profile_nudge.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/profile/domain/profile.dart';

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

WorkoutPlan _plan({
  required int sessionLengthMin,
  required List<String?> equipment,
  String name = 'Upper Body · Push',
}) =>
    WorkoutPlan(
      planId: 1,
      name: name,
      splitStyle: 'upper_lower',
      daysPerWeek: 3,
      sessionLengthMin: sessionLengthMin,
      weekNo: 1,
      exercises: [
        for (final (index, item) in equipment.indexed)
          PlanExercise(
            exerciseId: index + 1,
            name: 'Exercise ${index + 1}',
            muscleGroup: 'chest',
            orderNo: index + 1,
            targetSets: 3,
            targetReps: '8-12',
            equipment: item,
          ),
      ],
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

/// A UTC instant whose local calendar date differs from its own UTC
/// calendar date — or null if the host's timezone offset is exactly zero,
/// in which case no such instant can exist.
///
/// Two fixed candidates cover every real timezone regardless of its
/// offset's sign or magnitude: 23:59 UTC rolls forward onto the next local
/// day under any positive offset of at least a minute, and 00:00 UTC rolls
/// back onto the previous local day under any negative offset of at least a
/// minute. Verified against Asia/Manila (+8), UTC (0), America/Los_Angeles
/// (-7), Asia/Kolkata (+5:30), Pacific/Niue (-11) and Pacific/Kiritimati
/// (+14) — the widest real-world offsets — before relying on it here.
DateTime? _mismatchedZoneJoin() {
  final day = DateTime.utc(2026, 8, 31);
  final rollsForward = day.add(const Duration(hours: 23, minutes: 59));
  final rollsBack = day;

  bool diverges(DateTime utcInstant) {
    final local = utcInstant.toLocal();
    return local.year != utcInstant.year ||
        local.month != utcInstant.month ||
        local.day != utcInstant.day;
  }

  if (diverges(rollsForward)) return rollsForward;
  if (diverges(rollsBack)) return rollsBack;
  return null;
}

void main() {
  final mismatchedZoneJoin = _mismatchedZoneJoin();

  testWidgets('the greeting shows initials, first name and the day count',
      (tester) async {
    // joinedAt is a genuine UTC instant, as production always sends it. now
    // is derived from its *local* calendar date, 30 days later, rather than
    // hardcoded as a second independent UTC instant — so the elapsed-day
    // arithmetic is exactly 30 days regardless of the host machine's own
    // timezone.
    final joinedAt = DateTime.utc(2026, 8, 1, 12);
    final joinedLocalDate = joinedAt.toLocal();
    final now = DateTime(
        joinedLocalDate.year, joinedLocalDate.month, joinedLocalDate.day + 30);

    await tester.pumpWidget(_host(Greeting(
      profile: _profile(fullName: 'Juan Dela Cruz', joinedAt: joinedAt),
      now: now,
    )));

    expect(find.text('JC'), findsOneWidget, reason: 'first and last initials');
    expect(find.text('Kumusta, Juan'), findsOneWidget);
    expect(find.textContaining('Day 31'), findsOneWidget,
        reason: '30 whole days elapsed, plus one so the join date is Day 1');
  });

  testWidgets('a single-word name yields one initial', (tester) async {
    // now falls on the same local calendar day as the join, derived the
    // same way, so this must read Day 1 regardless of the host's timezone.
    final joinedAt = DateTime.utc(2026, 8, 31, 12);
    final joinedLocalDate = joinedAt.toLocal();
    final now = DateTime(
        joinedLocalDate.year, joinedLocalDate.month, joinedLocalDate.day);

    await tester.pumpWidget(_host(Greeting(
      profile: _profile(fullName: 'Juan', joinedAt: joinedAt),
      now: now,
    )));
    expect(find.text('J'), findsOneWidget);
    expect(find.textContaining('Day 1'), findsOneWidget,
        reason: 'the join date itself is Day 1, never Day 0');
  });

  testWidgets(
    'the day count follows the local calendar date, not the UTC one, when '
    'the two differ',
    (tester) async {
      final joinedAt = mismatchedZoneJoin!;
      final joinedLocalDate = joinedAt.toLocal();
      final now = DateTime(
          joinedLocalDate.year, joinedLocalDate.month, joinedLocalDate.day);

      await tester.pumpWidget(_host(Greeting(
        profile: _profile(joinedAt: joinedAt),
        now: now,
      )));

      expect(find.textContaining('Day 1'), findsOneWidget,
          reason:
              'now falls on the same local calendar day as the join — this '
              'must read Day 1 by the local calendar even though the '
              'fixture is deliberately chosen so the UTC calendar date of '
              'the join differs from its local one');
    },
    skip: mismatchedZoneJoin == null,
  );

  testWidgets('the greeting shows only the weekday when there is no join date',
      (tester) async {
    await tester.pumpWidget(_host(Greeting(
      profile: _profile(fullName: 'Juan Dela Cruz'), // joinedAt defaults null
      now: DateTime.utc(2026, 8, 31), // a Monday
    )));

    expect(find.text('Monday'), findsOneWidget);
    expect(find.textContaining('Day'), findsNothing,
        reason: 'no join date recorded (server predates the field) means no '
            'day count to show');
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

  testWidgets('the card hides the kcal chip without a body weight',
      (tester) async {
    await tester.pumpWidget(_host(PlanCard(
      plan: _plan(sessionLengthMin: 48, equipment: const ['Barbell']),
      weightKg: null,
      onStart: () {},
    )));
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.textContaining('48 min'), findsOneWidget,
        reason: 'the rest of the meta row still renders');
  });

  testWidgets(
      'the plan card does not overflow on a narrow phone at 2.0x text scale',
      (tester) async {
    // The eyebrow sits in the fixed-height 116dp gradient band, and the
    // exercise/duration/kcal figures sit in a joined meta row below the
    // name — either could, in principle, be pushed past its bounds by a
    // long plan name or a long equipment mix at accessibility text scales.
    // 320dp mirrors a small phone; 2.0x mirrors Android 14's maximum scale.
    // A SingleChildScrollView stands in for the scrollable dashboard body
    // Task 7 embeds this card in, so the card is free to grow taller under
    // the doubled text rather than being squeezed against a fixed test
    // viewport height that no real screen here would impose on it.
    await tester.pumpWidget(_host(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 800),
          textScaler: TextScaler.linear(2.0),
        ),
        child: SingleChildScrollView(
          child: SizedBox(
            width: 320,
            child: PlanCard(
              plan: _plan(
                sessionLengthMin: 48,
                name: 'Upper Body · Push, Pull and Legs',
                equipment: const [
                  'Barbell', 'Dumbbells', 'Bodyweight', 'Bands', 'Machines',
                ],
              ),
              weightKg: 70,
              onStart: () {},
            ),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}
