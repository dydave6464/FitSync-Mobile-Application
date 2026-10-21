import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/onboarding/presentation/steps/reminders_step.dart';

import 'helpers/onboarding_screen.dart';

RemindersStep _step({
  bool habits = true,
  bool checkin = true,
  ValueChanged<bool>? onHabits,
  ValueChanged<bool>? onCheckin,
}) => RemindersStep(
  habits: habits,
  checkin: checkin,
  onHabitsChanged: onHabits ?? (_) {},
  onCheckinChanged: onCheckin ?? (_) {},
);

Future<void> _pump(WidgetTester tester, [RemindersStep? step]) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: step ?? _step())),
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

  testWidgets('lists habits and the morning check-in, with what each does', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.text(
        'Pick what to be reminded about. You can change these any time in '
        'Settings.',
      ),
      findsOneWidget,
    );
    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('15 minutes before each timed habit'), findsOneWidget);
    expect(find.text('Morning check-in'), findsOneWidget);
    expect(find.text('7:00 AM · four quick questions'), findsOneWidget);
  });

  testWidgets('each switch shows the value it is given', (tester) async {
    await _pump(tester, _step(habits: true, checkin: false));

    Switch at(String key) => tester.widget<Switch>(find.byKey(Key(key)));
    expect(at('onboarding.remind.habits.switch').value, isTrue);
    expect(at('onboarding.remind.checkin.switch').value, isFalse);
  });

  testWidgets('a tap on a row or its switch reports the flipped value', (
    tester,
  ) async {
    final habits = <bool>[];
    final checkin = <bool>[];
    await _pump(tester, _step(onHabits: habits.add, onCheckin: checkin.add));

    await tester.tap(find.text('Morning check-in'));
    await tester.tap(find.byKey(const Key('onboarding.remind.habits.switch')));
    await tester.pump();

    expect(checkin, [false]);
    expect(habits, [false]);
  });

  testWidgets('each row is a full-size tap target', (tester) async {
    await _pump(tester);

    for (final key in [
      'onboarding.remind.habits',
      'onboarding.remind.checkin',
    ]) {
      expect(
        tester.getSize(find.byKey(Key(key))).height,
        greaterThanOrEqualTo(48),
        reason: key,
      );
    }
  });

  testWidgets('a screen reader hears each row with its on/off state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _step(habits: false, checkin: true));

    expect(
      tester.getSemantics(find.byKey(const Key('onboarding.remind.checkin'))),
      isSemantics(
        label: 'Morning check-in, 7:00 AM · four quick questions',
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('onboarding.remind.habits'))),
      isSemantics(
        label: 'Habits, 15 minutes before each timed habit',
        hasToggledState: true,
        isToggled: false,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  for (final screenWidth in phoneWidths) {
    testWidgets('fits a ${screenWidth.toInt()}dp phone at 2x text', (
      tester,
    ) async {
      await pumpOnPhone(tester, _step(), screenWidth: screenWidth);

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
