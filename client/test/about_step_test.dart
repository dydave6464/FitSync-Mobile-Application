import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/onboarding/presentation/steps/about_step.dart';

import 'helpers/onboarding_screen.dart';

/// Pinned as literals for the same reason as the goal step's: these are the
/// server's ENUM values, not display text.
const _sexValues = ['male', 'female'];

/// Everything the estimate needs, so a test can withhold exactly one of them.
const _complete = AboutAnswers(
  sex: 'male',
  dateOfBirth: '1998-03-14',
  heightCm: 175,
  weightKg: 72,
  activityLevel: 'light',
);
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
  WeightUnit unit = WeightUnit.kg,
}) async {
  AboutAnswers? emitted;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AboutStep(
            value: value,
            unit: unit,
            onChanged: (v) => emitted = v,
          ),
        ),
      ),
    ),
  );
  await interact(tester);
  await tester.pumpAndSettle();
  return emitted;
}

void main() {
  testWidgets('offers the two sexes the design shows', (tester) async {
    await _pumpAndEdit(tester, (_) async {});

    for (final value in _sexValues) {
      expect(find.byKey(Key('segment.$value')), findsOneWidget);
    }
    expect(find.text('Prefer not to say'), findsNothing);
  });

  testWidgets('a sex saved before that option was withdrawn is left alone', (
    tester,
  ) async {
    // `prefer_not_to_say` is still a valid ENUM value on the server and still
    // sits in profiles answered under the old three-chip control. Reopening
    // this step from settings must neither throw nor quietly rewrite that
    // answer to something the user did not choose.
    final emitted = await _pumpAndEdit(
      tester,
      (_) async {},
      value: const AboutAnswers(sex: 'prefer_not_to_say'),
    );

    expect(tester.takeException(), isNull);
    expect(emitted, isNull, reason: 'rendering is not an edit');
  });

  testWidgets('offers all five activity levels, including active', (
    tester,
  ) async {
    await _pumpAndEdit(tester, (_) async {});

    // The design draws four chips and no "Active"; leaving it out would push
    // those users onto a neighbouring multiplier and skew their targets.
    expect(find.text('DAILY ACTIVITY LEVEL'), findsOneWidget);
    for (final value in _activityValues) {
      expect(find.byKey(Key('activity.$value')), findsOneWidget);
    }
  });

  testWidgets('renders a date of birth control and the three measurements', (
    tester,
  ) async {
    await _pumpAndEdit(tester, (_) async {});

    expect(find.byKey(const Key('dateOfBirth')), findsOneWidget);
    expect(find.byKey(const Key('heightCm')), findsOneWidget);
    expect(find.byKey(const Key('weightKg')), findsOneWidget);
    expect(find.byKey(const Key('goalWeightKg')), findsOneWidget);
  });

  testWidgets(
    'reads the date of birth back as a date, with the age it implies',
    (tester) async {
      await _pumpAndEdit(
        tester,
        (_) async {},
        value: const AboutAnswers(dateOfBirth: '1998-03-14'),
      );

      expect(
        find.text('14 March 1998'),
        findsOneWidget,
        reason: 'the raw 1998-03-14 is wire format, not something to read',
      );
      expect(find.textContaining('yrs'), findsOneWidget);
    },
  );

  testWidgets('the estimate waits until every input it needs is there', (
    tester,
  ) async {
    await _pumpAndEdit(
      tester,
      (_) async {},
      value: const AboutAnswers(
        sex: 'male',
        dateOfBirth: '1998-03-14',
        heightCm: 175,
      ),
    );

    expect(
      find.textContaining('kcal'),
      findsNothing,
      reason: 'a target computed without a body weight describes nobody',
    );
  });

  testWidgets('the estimate appears once the last number is typed', (
    tester,
  ) async {
    await _pumpAndEdit(
      tester,
      (t) async {
        expect(find.textContaining('kcal'), findsNothing);
        await t.enterText(find.byKey(const Key('weightKg')), '72');
      },
      value: const AboutAnswers(
        sex: 'male',
        dateOfBirth: '1998-03-14',
        heightCm: 175,
        activityLevel: 'light',
      ),
    );

    expect(
      find.textContaining('kcal'),
      findsOneWidget,
      reason: 'the card has to recompute as the measurements are typed',
    );
    expect(find.textContaining('protein'), findsOneWidget);
  });

  testWidgets('the estimate reports what the formula returns', (tester) async {
    await _pumpAndEdit(tester, (_) async {}, value: _complete);

    // Mirrors daily_targets_test.dart's worked example, so a change to the
    // equation cannot pass by quietly rewording this card.
    expect(find.textContaining('2,300 kcal'), findsOneWidget);
    expect(find.textContaining('115g protein'), findsOneWidget);
  });

  testWidgets('emits the sex enum value the server accepts', (tester) async {
    final emitted = await _pumpAndEdit(
      tester,
      (t) => _tapKey(t, const Key('segment.female')),
    );

    expect(emitted!.sex, 'female');
  });

  testWidgets('emits the activity enum value the server accepts', (
    tester,
  ) async {
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

  testWidgets('a measurement that is not a number emits null, not a crash', (
    tester,
  ) async {
    final emitted = await _pumpAndEdit(
      tester,
      (t) => t.enterText(find.byKey(const Key('weightKg')), 'abc'),
    );

    expect(emitted!.weightKg, isNull);
  });

  testWidgets('does not read providers or save anything', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AboutStep(value: const AboutAnswers(), onChanged: (_) {}),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  // Height and Weight sit side by side in a Row, which is the context
  // overflow_guard_test.dart documents as the one this kit keeps losing to.
  // Each card holds its own Row (a flexible number, the unit and, on Weight,
  // the kg/lb toggle), so doubled text on a narrow phone squeezes both axes.
  for (final screenWidth in phoneWidths) {
    for (final unit in WeightUnit.values) {
      testWidgets(
        'the measurement cards fit a ${screenWidth.toInt()}dp phone at 2x '
        'text, in ${unit.api}',
        (tester) async {
          await pumpOnPhone(
            tester,
            AboutStep(value: _complete, unit: unit, onChanged: _ignore),
            screenWidth: screenWidth,
          );

          // Proves the step really was laid out at the phone's width.
          expect(
            tester.getSize(find.byType(AboutStep)).width,
            screenWidth - 40,
          );
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('weightKg.hint')), findsOneWidget);
          expect(
            find.textContaining('to maintain your weight'),
            findsOneWidget,
          );
        },
      );
    }
  }

  testWidgets('Height and Weight stay side by side at normal text size', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      const AboutStep(value: _complete, onChanged: _ignore),
      screenWidth: 360,
      textScale: 1.0,
    );

    expect(
      tester.getTopLeft(find.byKey(const Key('weightKg'))).dy,
      tester.getTopLeft(find.byKey(const Key('heightCm'))).dy,
    );
  });

  testWidgets('Weight moves under Height when 2x text would squeeze them', (
    tester,
  ) async {
    await pumpOnPhone(
      tester,
      const AboutStep(value: _complete, onChanged: _ignore),
      screenWidth: 360,
    );

    expect(
      tester.getTopLeft(find.byKey(const Key('weightKg'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('heightCm.hint'))).dy,
      ),
    );
  });

  // The first weight the app ever asks for, and the one the plan generator is
  // fed. Someone thinking in pounds who typed 150 into a field labelled kg
  // would hand the ML service a body weight out by a factor of 2.2.
  testWidgets('a weight typed in pounds is reported in kilograms', (
    tester,
  ) async {
    final emitted = await _pumpAndEdit(
      tester,
      (t) async => t.enterText(find.byKey(const Key('weightKg')), '150'),
      unit: WeightUnit.lb,
    );

    // 150 lb is 68.0388555 kg exactly.
    expect(emitted!.weightKg, closeTo(68.0388555, 1e-7));
  });

  testWidgets(
    'the weight card shows the stored kilograms in the unit in force',
    (tester) async {
      await _pumpAndEdit(
        tester,
        (t) async {},
        value: _complete,
        unit: WeightUnit.lb,
      );

      // The fixture's 72 kg is 158.7... lb.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('weightKg')))
            .controller!
            .text,
        '158.7',
      );
    },
  );

  testWidgets('the estimate says it is for keeping the weight, not the goal', (
    tester,
  ) async {
    // The figure ignores the goal; Nutrition applies it. Unlabelled, 2,300
    // here and 1,800 there read as the app contradicting itself.
    await _pumpAndEdit(tester, (_) async {}, value: _complete);

    expect(
      find.text(
        'Estimated 2,300 kcal a day to maintain your weight · '
        '115g protein',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('daily target'), findsNothing);
  });

  group('range hints', () {
    // The bounds the server already enforces: weightKg's [MIN_KG, MAX_KG] in
    // server/src/db/body-weight.js, and the shared NUMERIC check (above 0,
    // below 1000) in server/src/routes/profile.js that is all heightCm has.
    testWidgets('match the bounds the server accepts, in kilograms', (
      tester,
    ) async {
      await _pumpAndEdit(tester, (_) async {});

      expect(find.byKey(const Key('heightCm.hint')), findsOneWidget);
      expect(find.text('Under 1,000 cm'), findsOneWidget);
      expect(find.byKey(const Key('weightKg.hint')), findsOneWidget);
      expect(find.text('20–500 kg'), findsOneWidget);
    });

    testWidgets('follow the weight unit in force', (tester) async {
      await _pumpAndEdit(tester, (_) async {}, unit: WeightUnit.lb);

      expect(
        find.text(
          '${formatWeight(20, WeightUnit.lb)}–'
          '${formatWeight(500, WeightUnit.lb)} lb',
        ),
        findsOneWidget,
      );
      expect(find.text('20–500 kg'), findsNothing);
    });

    testWidgets('are readable text, not the faint tertiary grey', (
      tester,
    ) async {
      await _pumpAndEdit(tester, (_) async {});

      for (final key in ['heightCm.hint', 'weightKg.hint']) {
        final hint = tester.widget<Text>(find.byKey(Key(key)));
        final context = tester.element(find.byKey(Key(key)));
        expect(hint.style?.color, context.fs.text2, reason: key);
      }
    });
  });
}

void _ignore(AboutAnswers _) {}
