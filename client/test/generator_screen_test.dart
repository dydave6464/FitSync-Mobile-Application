import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/generator_screen.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';

const _pplPlan = WorkoutPlan(
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

Future<void> _pump(WidgetTester tester, {WorkoutPlan? plan}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activePlanProvider.overrideWith((ref) async => plan),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: const GeneratorScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the four split styles are offered', (tester) async {
    await _pump(tester, plan: _pplPlan);

    expect(find.text('Full body'), findsOneWidget);
    expect(find.text('Push / Pull / Legs'), findsOneWidget);
    expect(find.text('Upper / Lower'), findsOneWidget);
    expect(find.text('Cardio + core'), findsOneWidget);
  });

  testWidgets('the controls open on the current plan', (tester) async {
    // The screen should describe what the user already has, so a generate
    // with no changes is a no-op rather than a silent reset to full body.
    await _pump(tester, plan: _pplPlan);

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugSplitStyle, 'push_pull_legs');
    expect(screen.debugDaysPerWeek, 4);
    expect(screen.debugSessionLengthMin, 60);
  });

  testWidgets('with no plan the controls fall back to defaults', (tester) async {
    // /regenerate has no NO_ACTIVE_PLAN check, so this screen works for
    // someone who has none -- it must not render blank.
    await _pump(tester, plan: null);

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugSplitStyle, 'full_body');
    expect(screen.debugDaysPerWeek, 3);
    expect(screen.debugSessionLengthMin, 45);
  });

  testWidgets('tapping a split chip selects it', (tester) async {
    await _pump(tester, plan: _pplPlan);

    await tester.tap(find.text('Upper / Lower'));
    await tester.pump();

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugSplitStyle, 'upper_lower');
  });

  testWidgets('session length offers exactly 45 and 60', (tester) async {
    // EXERCISES_BY_SESSION knows two lengths and _nearest_session_length
    // snaps everything else, so a slider reading 50 would build a 45-minute
    // plan. Two stops is the honest control.
    await _pump(tester, plan: _pplPlan);

    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('60 min'), findsOneWidget);
    expect(find.text('50 min'), findsNothing);
  });

  testWidgets('days one through seven are offered', (tester) async {
    await _pump(tester, plan: _pplPlan);

    for (var d = 1; d <= 7; d += 1) {
      expect(find.byKey(Key('gen.day.$d')), findsOneWidget);
    }
    expect(find.byKey(const Key('gen.day.8')), findsNothing);
  });

  testWidgets('tapping a day selects it', (tester) async {
    await _pump(tester, plan: _pplPlan);

    await tester.tap(find.byKey(const Key('gen.day.6')));
    await tester.pump();

    final screen = tester.state(find.byType(GeneratorScreen)) as dynamic;
    expect(screen.debugDaysPerWeek, 6);
  });

  testWidgets('the screen says generating replaces the current plan',
      (tester) async {
    // savePlan deactivates the previous plan inside its transaction. That is
    // the one destructive thing here and should not be discovered afterwards.
    await _pump(tester, plan: _pplPlan);

    expect(find.textContaining('replace'), findsOneWidget);
  });
}
