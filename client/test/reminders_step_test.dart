import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/onboarding/presentation/steps/reminders_step.dart';

Future<void> _pump(WidgetTester tester, {MediaQueryData? media}) async {
  const step = Scaffold(body: SingleChildScrollView(child: RemindersStep()));
  await tester.pumpWidget(
    MaterialApp(
      home: media == null ? step : MediaQuery(data: media, child: step),
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

  testWidgets('fits a 320dp screen at 2x text', (tester) async {
    await _pump(
      tester,
      media: const MediaQueryData(
        size: Size(320, 800),
        textScaler: TextScaler.linear(2.0),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
