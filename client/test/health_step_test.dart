import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/health/domain/health_answers.dart';
import 'package:fitsync/features/onboarding/presentation/steps/health_step.dart';

import 'helpers/onboarding_screen.dart';

/// Holds the answers between taps, the way onboarding and Settings do.
Future<HealthAnswers Function()> _pumpLive(
  WidgetTester tester, {
  HealthAnswers initial = const HealthAnswers(),
  bool allowOptOut = true,
}) async {
  var current = initial;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => HealthStep(
              value: current,
              allowOptOut: allowOptOut,
              onChanged: (v) => setState(() => current = v),
            ),
          ),
        ),
      ),
    ),
  );
  return () => current;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _answerAllNo(WidgetTester tester) async {
  for (final q in healthQuestions) {
    await _tap(tester, 'health.${q.field}.no');
  }
}

void main() {
  testWidgets('shows the title, every condition and every question', (
    tester,
  ) async {
    await _pumpLive(tester);

    expect(find.text('Your health'), findsOneWidget);
    expect(find.text('This helps us keep your plan safe.'), findsOneWidget);
    for (final c in healthConditions) {
      expect(find.byKey(Key('health.${c.value}')), findsOneWidget);
      expect(find.text(c.label), findsOneWidget);
    }
    expect(find.byKey(const Key('health.none')), findsOneWidget);
    for (final q in healthQuestions) {
      expect(find.text(q.label), findsOneWidget);
      expect(find.byKey(Key('health.${q.field}.yes')), findsOneWidget);
      expect(find.byKey(Key('health.${q.field}.no')), findsOneWidget);
    }
  });

  testWidgets('a clear answer shows no notice and no boxes', (tester) async {
    final read = await _pumpLive(tester);

    await _tap(tester, 'health.none');
    await _answerAllNo(tester);

    expect(read().isValid, isTrue);
    expect(find.byKey(const Key('health.notice.condition')), findsNothing);
    expect(find.byKey(const Key('health.notice.warning')), findsNothing);
    expect(find.byKey(const Key('health.ack')), findsNothing);
    expect(find.byKey(const Key('health.consent')), findsNothing);
    expect(find.byKey(const Key('health.optOut')), findsNothing);
  });

  testWidgets('None of these clears a ticked condition', (tester) async {
    final read = await _pumpLive(tester);

    await _tap(tester, 'health.asthma');
    await _tap(tester, 'health.none');

    expect(read().conditions, isEmpty);
    expect(read().noneOfThese, isTrue);
  });

  testWidgets('None of these answers the questions No, keeping a Yes', (
    tester,
  ) async {
    final read = await _pumpLive(tester);

    await _tap(tester, 'health.chestPain.yes');
    await _tap(tester, 'health.none');

    expect(read().chestPain, isTrue, reason: 'a reported Yes stays');
    expect(read().dizziness, isFalse);
    expect(read().supervisedOnly, isFalse);
    expect(
      find.byKey(const Key('health.notice.warning')),
      findsOneWidget,
      reason: 'the clearance card still shows for the kept Yes',
    );
  });

  testWidgets('a condition shows its line and tip under a doctor notice', (
    tester,
  ) async {
    await _pumpLive(tester);

    await _tap(tester, 'health.high_blood_pressure');
    await _tap(tester, 'health.asthma');

    final notice = find.byKey(const Key('health.notice.condition'));
    expect(notice, findsOneWidget);
    Finder inNotice(String text) =>
        find.descendant(of: notice, matching: find.text(text));
    expect(inNotice('Check with your doctor first'), findsOneWidget);
    expect(
      inNotice('You told us about: High blood pressure, Asthma.'),
      findsOneWidget,
    );
    expect(
      inNotice(
        "We'll keep your plan gentle: 2 sets per exercise, shorter sessions.",
      ),
      findsOneWidget,
    );
    expect(inNotice(healthConditions[0].line), findsOneWidget);
    expect(inNotice(healthConditions[0].tip), findsOneWidget);
    expect(inNotice(healthConditions[3].tip), findsOneWidget);
    expect(
      inNotice(healthConditions[2].tip),
      findsNothing,
      reason: 'diabetes not ticked',
    );
    expect(
      inNotice('This is general safety guidance, not medical advice.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('health.notice.warning')), findsNothing);
  });

  testWidgets('any Yes shows the medical clearance card', (tester) async {
    await _pumpLive(tester);

    await _tap(tester, 'health.none');
    await _tap(tester, 'health.dizziness.yes');

    final warning = find.byKey(const Key('health.notice.warning'));
    expect(warning, findsOneWidget);
    expect(
      find.descendant(
        of: warning,
        matching: find.text(
          'Please get medical clearance before you start training',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Stop and get help if you have chest pain, fainting or severe '
        'breathlessness.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('health.notice.condition')), findsNothing);
  });

  testWidgets('the warning card sits above the condition card', (tester) async {
    await _pumpLive(tester);

    await _tap(tester, 'health.asthma');
    await _tap(tester, 'health.chestPain.yes');

    final warningTop = tester
        .getTopLeft(find.byKey(const Key('health.notice.warning')))
        .dy;
    final conditionTop = tester
        .getTopLeft(find.byKey(const Key('health.notice.condition')))
        .dy;
    expect(warningTop, lessThan(conditionTop));
  });

  testWidgets('a positive answer is valid only with both boxes ticked', (
    tester,
  ) async {
    final read = await _pumpLive(tester);

    await _tap(tester, 'health.asthma');
    await _answerAllNo(tester);
    expect(read().isValid, isFalse);

    await _tap(tester, 'health.ack');
    expect(read().acknowledged, isTrue);
    expect(read().isValid, isFalse);

    await _tap(tester, 'health.consent');
    expect(read().consent, isTrue);
    expect(read().isValid, isTrue);
  });

  testWidgets(
    "Don't save my answers is valid without the boxes, and undoable",
    (tester) async {
      final read = await _pumpLive(tester);

      await _tap(tester, 'health.asthma');
      await _answerAllNo(tester);
      expect(find.text("Don't save my answers"), findsOneWidget);

      await _tap(tester, 'health.optOut');
      expect(read().optedOut, isTrue);
      expect(read().isValid, isTrue);
      expect(find.byKey(const Key('health.ack')), findsNothing);
      expect(find.byKey(const Key('health.consent')), findsNothing);

      await _tap(tester, 'health.optOut');
      expect(read().optedOut, isFalse);
      expect(find.byKey(const Key('health.ack')), findsOneWidget);
    },
  );

  testWidgets('the opt-out is hidden when not allowed', (tester) async {
    await _pumpLive(tester, allowOptOut: false);

    await _tap(tester, 'health.asthma');

    expect(find.byKey(const Key('health.ack')), findsOneWidget);
    expect(find.byKey(const Key('health.optOut')), findsNothing);
  });

  group('the hint above Continue', () {
    const unanswered = 'Answer every question to continue';
    const unticked = 'Tick both boxes to continue';

    testWidgets('names what is missing while the answer is not valid', (
      tester,
    ) async {
      final read = await _pumpLive(tester);
      expect(read().isValid, isFalse);
      expect(find.text(unanswered), findsOneWidget);

      // Every question answered but the checklist left blank.
      await _answerAllNo(tester);
      expect(find.text(unanswered), findsOneWidget);

      await _tap(tester, 'health.none');
      expect(read().isValid, isTrue);
      expect(find.text(unanswered), findsNothing);
      expect(find.text(unticked), findsNothing);
    });

    testWidgets('asks for the boxes once every question is answered', (
      tester,
    ) async {
      final read = await _pumpLive(tester);

      await _tap(tester, 'health.asthma');
      await _answerAllNo(tester);
      expect(find.text(unanswered), findsNothing);
      expect(find.text(unticked), findsOneWidget);

      await _tap(tester, 'health.ack');
      await _tap(tester, 'health.consent');
      expect(read().isValid, isTrue);
      expect(find.text(unticked), findsNothing);
    });

    testWidgets('goes away when the answers are not saved', (tester) async {
      await _pumpLive(tester);

      await _tap(tester, 'health.asthma');
      await _answerAllNo(tester);
      await _tap(tester, 'health.optOut');

      expect(find.text(unticked), findsNothing);
      expect(find.text(unanswered), findsNothing);
    });

    testWidgets('says save, not continue, in Settings', (tester) async {
      await _pumpLive(tester, allowOptOut: false);

      expect(find.text('Answer every question to save'), findsOneWidget);
      expect(find.text(unanswered), findsNothing);

      await _tap(tester, 'health.asthma');
      await _answerAllNo(tester);
      expect(find.text('Tick both boxes to save'), findsOneWidget);
    });

    testWidgets('is readable text, not the faint tertiary grey', (
      tester,
    ) async {
      await _pumpLive(tester);

      final hint = tester.widget<Text>(find.text(unanswered));
      final context = tester.element(find.text(unanswered));
      expect(hint.style?.color, context.fs.text2);
    });
  });

  testWidgets('opting out in onboarding promises no plan that is not there', (
    tester,
  ) async {
    await _pumpLive(tester);

    await _tap(tester, 'health.asthma');
    await _answerAllNo(tester);
    await _tap(tester, 'health.optOut');

    expect(
      find.text(
        "We won't save these answers. You can change this later in Settings.",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('plan stays'), findsNothing);
  });

  testWidgets('an opted-out answer in Settings keeps the plan as it is', (
    tester,
  ) async {
    // Settings offers no opt-out button, but the copy has to stay right for a
    // value that arrives opted out: there, a plan does exist, and the user is
    // already in Settings.
    await _pumpLive(
      tester,
      allowOptOut: false,
      initial: const HealthAnswers(
        conditions: ['asthma'],
        chestPain: false,
        dizziness: false,
        supervisedOnly: false,
        optedOut: true,
      ),
    );

    expect(
      find.text("We won't save these answers, and your plan stays as it is."),
      findsOneWidget,
    );
    expect(find.textContaining('later in Settings'), findsNothing);
  });

  for (final screenWidth in phoneWidths) {
    testWidgets(
      'fits a ${screenWidth.toInt()}dp phone at 2x text with the notices open',
      (tester) async {
        await pumpOnPhone(
          tester,
          HealthStep(
            value: const HealthAnswers(
              conditions: ['asthma', 'heart_condition'],
              chestPain: true,
            ),
            onChanged: (_) {},
          ),
          screenWidth: screenWidth,
        );

        // Proves the step really was laid out at the phone's width.
        expect(tester.getSize(find.byType(HealthStep)).width, screenWidth - 40);
        expect(tester.takeException(), isNull);
        expect(find.text('Answer every question to continue'), findsOneWidget);
      },
    );
  }
}
