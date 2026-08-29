import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/onboarding/presentation/steps/about_step.dart';

/// Pinned as literals for the same reason as the goal step's: these are the
/// server's ENUM values, not display text.
const _sexValues = ['male', 'female', 'prefer_not_to_say'];
const _activityValues = [
  'sedentary',
  'light',
  'moderate',
  'active',
  'very_active',
];

/// Scrolls to the target before tapping. The step is taller than the test
/// viewport, so a bare `tap` on a control near the bottom lands on empty space
/// and silently does nothing.
Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
}

Future<AboutAnswers?> _pumpAndEdit(
  WidgetTester tester,
  Future<void> Function(WidgetTester) interact, {
  AboutAnswers value = const AboutAnswers(),
}) async {
  AboutAnswers? emitted;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AboutStep(value: value, onChanged: (v) => emitted = v),
      ),
    ),
  ));
  await interact(tester);
  await tester.pumpAndSettle();
  return emitted;
}

void main() {
  testWidgets('offers prefer_not_to_say, which the mockup omits',
      (tester) async {
    await _pumpAndEdit(tester, (_) async {});

    for (final value in _sexValues) {
      expect(find.byKey(Key('sex.$value')), findsOneWidget);
    }
  });

  testWidgets('offers all five activity levels, including active',
      (tester) async {
    await _pumpAndEdit(tester, (_) async {});

    for (final value in _activityValues) {
      expect(find.byKey(Key('activity.$value')), findsOneWidget);
    }
  });

  testWidgets('renders a date of birth control and the three measurements',
      (tester) async {
    await _pumpAndEdit(tester, (_) async {});

    expect(find.byKey(const Key('dateOfBirth')), findsOneWidget);
    expect(find.byKey(const Key('heightCm')), findsOneWidget);
    expect(find.byKey(const Key('weightKg')), findsOneWidget);
    expect(find.byKey(const Key('goalWeightKg')), findsOneWidget);
  });

  testWidgets('emits the sex enum value the server accepts', (tester) async {
    final emitted = await _pumpAndEdit(
      tester,
      (t) => _tapKey(t, const Key('sex.prefer_not_to_say')),
    );

    expect(emitted!.sex, 'prefer_not_to_say');
  });

  testWidgets('emits the activity enum value the server accepts',
      (tester) async {
    final emitted = await _pumpAndEdit(
      tester,
      (t) => _tapKey(t, const Key('activity.active')),
    );

    expect(emitted!.activityLevel, 'active');
  });

  testWidgets('emits measurements as numbers', (tester) async {
    final emitted = await _pumpAndEdit(
      tester,
      (t) => t.enterText(find.byKey(const Key('heightCm')), '172.5'),
    );

    expect(emitted!.heightCm, 172.5);
  });

  testWidgets('a measurement that is not a number emits null, not a crash',
      (tester) async {
    final emitted = await _pumpAndEdit(
      tester,
      (t) => t.enterText(find.byKey(const Key('weightKg')), 'abc'),
    );

    expect(emitted!.weightKg, isNull);
  });

  testWidgets('does not read providers or save anything', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AboutStep(value: const AboutAnswers(), onChanged: (_) {}),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}
