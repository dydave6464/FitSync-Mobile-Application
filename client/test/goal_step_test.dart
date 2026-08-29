import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/onboarding/presentation/steps/goal_step.dart';

/// The wire values the server's `main_goal` ENUM accepts. Pinned as literals
/// on purpose: if a label is reworded to "Improve endurance" and someone
/// "fixes" the value to match, the server starts rejecting the request with a
/// 400 and this test is what catches it.
const _wireValues = [
  'lose_weight',
  'build_muscle',
  'improve_endurance',
  'general_fitness',
];

void main() {
  testWidgets('renders exactly the four goals', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GoalStep(value: null, onChanged: (_) {})),
    ));

    for (final value in _wireValues) {
      expect(find.byKey(Key('goal.$value')), findsOneWidget);
    }
    expect(find.byType(ListTile), findsNWidgets(4));
  });

  testWidgets('emits the server enum value, not the label', (tester) async {
    final emitted = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GoalStep(value: null, onChanged: emitted.add)),
    ));

    for (final value in _wireValues) {
      await tester.tap(find.byKey(Key('goal.$value')));
      await tester.pumpAndSettle();
    }

    expect(emitted, _wireValues);
  });

  testWidgets('marks the selected goal', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GoalStep(value: 'build_muscle', onChanged: (_) {}),
      ),
    ));

    expect(
      tester.widget<ListTile>(find.byKey(const Key('goal.build_muscle'))).selected,
      isTrue,
    );
    expect(
      tester.widget<ListTile>(find.byKey(const Key('goal.lose_weight'))).selected,
      isFalse,
    );
  });

  testWidgets('does not read providers or save anything', (tester) async {
    // Pumped with no ProviderScope at all. If this ever throws, the step has
    // started reaching for state it should have been handed, and Task 10's
    // reuse from Settings is broken.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GoalStep(value: 'lose_weight', onChanged: (_) {})),
    ));

    expect(tester.takeException(), isNull);
  });
}
