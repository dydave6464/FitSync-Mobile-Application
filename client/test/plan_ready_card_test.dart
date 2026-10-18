import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/home/presentation/widgets/plan_ready_card.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

const _plan = WorkoutPlan(
  planId: 1,
  name: 'My Push / Pull / Legs',
  splitStyle: 'ppl',
  daysPerWeek: 3,
  sessionLengthMin: 45,
  weekNo: 1,
  exercises: [],
);

Future<void> _pump(
  WidgetTester tester, {
  WorkoutPlan plan = _plan,
  String? fitnessLevel = 'beginner',
  VoidCallback? onSeePlan,
  VoidCallback? onDismiss,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? fsLightTheme(),
      home: Scaffold(
        // Scrollable, as Home is: at large text the card grows, and only a
        // list lets it.
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            PlanReadyCard(
              plan: plan,
              fitnessLevel: fitnessLevel,
              onSeePlan: onSeePlan ?? () {},
              onDismiss: onDismiss ?? () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('says the plan is ready and names it', (tester) async {
    await _pump(tester);

    expect(find.text('YOUR PLAN IS READY'), findsOneWidget);
    expect(find.text('My Push / Pull / Legs'), findsOneWidget);
  });

  testWidgets('lists the days a week, the minutes and the level', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('3 days a week'), findsOneWidget);
    expect(find.text('~45 min'), findsOneWidget);
    expect(find.text('Beginner'), findsOneWidget);
  });

  testWidgets('a one-day plan says one day, not one days', (tester) async {
    await _pump(
      tester,
      plan: const WorkoutPlan(
        planId: 2,
        name: 'Full Body',
        splitStyle: 'full_body',
        daysPerWeek: 1,
        sessionLengthMin: 30,
        weekNo: 1,
        exercises: [],
      ),
    );

    expect(find.text('1 day a week'), findsOneWidget);
  });

  testWidgets('names New to training as the level step does', (tester) async {
    await _pump(tester, fitnessLevel: 'new');

    expect(find.text('New to training'), findsOneWidget);
  });

  testWidgets('leaves the level out when it was never answered', (
    tester,
  ) async {
    await _pump(tester, fitnessLevel: null);

    // The other two facts stay; only the unknown one goes, rather than a
    // guess or an empty chip.
    expect(find.text('3 days a week'), findsOneWidget);
    expect(find.text('Beginner'), findsNothing);
  });

  testWidgets('See plan and the close button each do their own thing', (
    tester,
  ) async {
    final taps = <String>[];
    await _pump(
      tester,
      onSeePlan: () => taps.add('see'),
      onDismiss: () => taps.add('dismiss'),
    );

    await tester.tap(find.text('See plan'));
    await tester.tap(find.byKey(const Key('home.planReady.dismiss')));

    expect(taps, ['see', 'dismiss']);
  });

  testWidgets('the close button takes a 48 dp tap and says what it does', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    final close = find.byKey(const Key('home.planReady.dismiss'));
    final size = tester.getSize(close);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    // A bare ✕ is unlabelled to anyone not looking at it. The tooltip is
    // what TalkBack and VoiceOver read for it.
    expect(
      tester.getSemantics(close),
      matchesSemantics(
        tooltip: 'Dismiss',
        isButton: true,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('the heading reads in the text green', (tester) async {
    await _pump(tester);

    final heading = tester.widget<Text>(find.text('YOUR PLAN IS READY'));
    expect(
      heading.style?.color,
      tester.element(find.text('YOUR PLAN IS READY')).fs.accentText,
    );
  });

  // The card is drawn on the accent card's gradient, whose top corner is the
  // green at 16% over the page -- a deeper tint than the 13% accentDim the
  // theme's own contrast test measures, so it is measured here.
  for (final (name, t) in [
    ('light', FsTokens.light),
    ('dark', FsTokens.dark),
  ]) {
    test('the green words read at 4.5:1 on the card in the $name theme', () {
      final corner = Color.alphaBlend(t.accent.withValues(alpha: 0.16), t.bg);
      expect(_contrast(t.accentText, corner), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('fits a 320 dp phone at 2.0x text in both themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final theme in [fsLightTheme(), fsDarkTheme()]) {
      await _pump(tester, theme: theme);
      expect(tester.takeException(), isNull);
      expect(find.text('See plan'), findsOneWidget);
    }
  });
}
