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
  String splitStyle = 'upper_lower',
}) =>
    WorkoutPlan(
      planId: 1,
      name: name,
      splitStyle: splitStyle,
      daysPerWeek: 3,
      sessionLengthMin: sessionLengthMin,
      weekNo: 1,
      exercises: [
        for (final (index, item) in equipment.indexed)
          PlanExercise(
            planExerciseId: 500 + index,
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

  testWidgets(
      'the avatar initials do not spill past the circle at 2.0x text scale',
      (tester) async {
    // The avatar Container gives its child a loose max-size constraint via
    // `alignment: Alignment.center` (RenderPositionedBox), which does not
    // clip or complain when the child wants more — a RenderParagraph that
    // needs more room than that simply paints its glyphs past the circle's
    // edge, with no thrown exception and a reported layout size that would
    // look compliant regardless. Neither takeException() nor a plain
    // getSize/getRect comparison on the Text catches this (both stay
    // "clean" whether or not the guard below exists), which is why this
    // checks the content's true intrinsic size and the shrink-to-fit
    // mechanism separately, rather than either alone.
    await tester.pumpWidget(_host(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: Greeting(
        profile: _profile(fullName: 'Maximilian Wolfeschlegel'),
        now: DateTime.utc(2026, 8, 31),
      ),
    )));

    final initials = find.text('MW');

    // Sanity: this name is deliberately chosen so the initials' own natural
    // (unconstrained) width genuinely exceeds the ~38px available inside
    // the 40x40 circle once its 1px border is subtracted — otherwise the
    // assertions below would pass with nothing to guard against.
    final paragraph = tester.renderObject<RenderBox>(
      find.descendant(of: initials, matching: find.byType(RichText)),
    );
    expect(paragraph.getMaxIntrinsicWidth(double.infinity), greaterThan(38),
        reason: 'this test is meaningless if the initials were already '
            'narrow enough to fit unaided');

    // A FittedBox is what actually keeps the paint inside the circle here —
    // maxLines/overflow (which is what stops FsEyebrow and FsTag
    // overflowing) can cut a line short, but it cannot shrink glyphs that
    // are individually too wide.
    final fittedBox =
        find.ancestor(of: initials, matching: find.byType(FittedBox));
    expect(fittedBox, findsOneWidget,
        reason: 'the initials need a shrink-to-fit guard');
    final fittedSize = tester.getSize(fittedBox);
    expect(fittedSize.width, lessThanOrEqualTo(38));
    expect(fittedSize.height, lessThanOrEqualTo(38));
  });

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

  testWidgets('the card renders the plan name and exercise count',
      (tester) async {
    // Spec §6 calls for the plan card's name and exercise count to be
    // asserted; only duration was. equipment carries three entries, so this
    // also happens to guard the plural form against a regression to a fixed
    // ' exercises' suffix.
    await tester.pumpWidget(_host(PlanCard(
      plan: _plan(
        sessionLengthMin: 48,
        name: 'Upper Body · Push',
        equipment: const ['Barbell', 'Dumbbells', 'Bodyweight'],
      ),
      weightKg: 70,
      onStart: () {},
    )));

    expect(find.text('Upper Body · Push'), findsOneWidget);
    expect(find.textContaining('3 exercises'), findsOneWidget);
  });

  testWidgets('a single-exercise plan reads "1 exercise", not "1 exercises"',
      (tester) async {
    // Exactly what the ML plan-generation stub produces for a minimal plan
    // (server/tests/plans-routes.test.js), so this is a real shape, not a
    // contrived edge case.
    await tester.pumpWidget(_host(PlanCard(
      plan: _plan(sessionLengthMin: 30, equipment: const ['Barbell']),
      weightKg: 70,
      onStart: () {},
    )));

    expect(find.textContaining('1 exercise'), findsOneWidget);
    expect(find.textContaining('1 exercises'), findsNothing);
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

  testWidgets(
      'the cover band eyebrow does not silently overflow its 116dp band at '
      '2.0x text scale', (tester) async {
    // The eyebrow sits inside a fixed-height (116dp) Container with
    // `alignment: bottomLeft` (RenderPositionedBox again, like the avatar
    // above), which gives its child a loose max-size constraint rather than
    // clipping or complaining. Before FsEyebrow gained maxLines/overflow
    // (this branch's guard fix), a long split style could report a
    // compliant-looking layout size while painting several unmeasured lines
    // past the band, with no thrown exception — takeException() and a plain
    // getRect comparison both stay clean either way. maxLines: 1 changes
    // what the RenderParagraph itself reports as its own intrinsic height,
    // which is why checking that directly is what actually proves the fix.
    await tester.pumpWidget(_host(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 800),
          textScaler: TextScaler.linear(2.0),
        ),
        child: SizedBox(
          width: 320,
          child: PlanCard(
            plan: _plan(
              sessionLengthMin: 45,
              equipment: const ['Barbell'],
              splitStyle: 'upper_lower_push_pull_legs_and_core_conditioning_'
                  'with_extra_accessory_work_for_the_whole_body',
            ),
            weightKg: 70,
            onStart: () {},
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);

    final eyebrowInBand = find.descendant(
      of: find.byType(Container).first,
      matching: find.byType(FsEyebrow),
    );
    final availableWidth = tester.getRect(eyebrowInBand).width;
    final paragraph = tester.renderObject<RenderBox>(
      find.descendant(of: eyebrowInBand, matching: find.byType(RichText)),
    );

    // Sanity, computed independently of FsEyebrow's own (already guarded)
    // rendering: RenderParagraph.getMaxIntrinsicHeight respects maxLines, so
    // measuring the mounted widget directly would just report the fix's own
    // one-line answer regardless of whether the fix does anything. A fresh
    // TextPainter with the same content, style and scale but no maxLines
    // shows what the eyebrow would need if nothing capped it — deliberately
    // well more than the 86px the band actually has (116dp minus 15px
    // padding on each side), or the assertion below would pass with nothing
    // to guard against.
    final unguardedPainter = TextPainter(
      text: TextSpan(
        text: describeSplit(
          'upper_lower_push_pull_legs_and_core_conditioning_with_extra_'
          'accessory_work_for_the_whole_body',
        ).toUpperCase(),
        style: const TextStyle(
          fontFamily: fsMonoFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.47,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(2.0),
    )..layout(maxWidth: availableWidth);
    expect(unguardedPainter.height, greaterThan(86),
        reason: 'this test is meaningless if the split style already fit '
            'the band unaided');

    // Not paragraph.size.height: the Container's `alignment` gives the
    // paragraph a *loose* max-height constraint, so its reported size
    // saturates at 86 either way, guarded or not — that clamped report is
    // exactly the silent-clipping trap this finding is about. Only the
    // paragraph's own intrinsic height reflects maxLines actually capping
    // it to one line, rather than the ambient constraint merely hiding how
    // much taller the (unpainted-within-bounds) content really wanted.
    expect(paragraph.getMaxIntrinsicHeight(availableWidth), lessThanOrEqualTo(86),
        reason: 'maxLines: 1 must cap the eyebrow to one line, not let it '
            'wrap and silently spill past the 86px available inside the '
            'band');
  });
}
