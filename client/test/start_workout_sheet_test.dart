import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/presentation/start_workout_sheet.dart';

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showStartWorkoutSheet(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sheet offers both rows from the design', (tester) async {
    await _open(tester);

    expect(find.text('Start a workout'), findsOneWidget);
    expect(find.text('AI Workout Generator'), findsOneWidget);
    expect(find.text('Log manually'), findsOneWidget);
  });

  testWidgets('log manually is disabled and says so', (tester) async {
    // Slice 3 builds the exercise library. Until then the row is present and
    // inert, so the capability reads as planned rather than missing --
    // the same voice training_shell.dart's _ComingSoon already uses.
    await _open(tester);

    expect(find.text('Coming soon'), findsOneWidget);

    final row = tester.widget<InkWell>(
      find.byKey(const Key('start.manual')),
    );
    expect(row.onTap, isNull, reason: 'a disabled row must not be tappable');
  });

  testWidgets('the generator row is tappable', (tester) async {
    await _open(tester);

    final row = tester.widget<InkWell>(
      find.byKey(const Key('start.generator')),
    );
    expect(row.onTap, isNotNull);
  });

  testWidgets('the close button dismisses the sheet', (tester) async {
    await _open(tester);

    await tester.tap(find.byKey(const Key('start.close')));
    await tester.pumpAndSettle();
    expect(find.text('Start a workout'), findsNothing);
  });
}
