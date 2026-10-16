import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/onboarding/presentation/steps/reminders_step.dart';

import 'helpers/onboarding_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: RemindersStep())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('says the plan is built next, whichever button is pressed', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Stay on track'), findsOneWidget);
    expect(find.text("Next, we'll build your plan."), findsOneWidget);
  });

  testWidgets('the next-step line is readable text', (tester) async {
    await _pump(tester);

    final finder = find.text("Next, we'll build your plan.");
    final line = tester.widget<Text>(finder);
    expect(line.style?.color, tester.element(finder).fs.text2);
  });

  for (final screenWidth in phoneWidths) {
    testWidgets('fits a ${screenWidth.toInt()}dp phone at 2x text', (
      tester,
    ) async {
      await pumpOnPhone(
        tester,
        const RemindersStep(),
        screenWidth: screenWidth,
      );

      // Proves the step really was laid out at the phone's width.
      expect(
        tester.getSize(find.byType(RemindersStep)).width,
        screenWidth - 40,
      );
      expect(tester.takeException(), isNull);
      expect(find.text("Next, we'll build your plan."), findsOneWidget);
    });
  }
}
