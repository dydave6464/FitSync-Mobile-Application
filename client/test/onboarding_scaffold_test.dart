import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/onboarding/presentation/edit_scaffold.dart';
import 'package:fitsync/features/onboarding/presentation/onboarding_scaffold.dart';

void main() {
  group('OnboardingScaffold', () {
    testWidgets('shows progress for the current step', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScaffold(
          step: 2,
          total: 4,
          onContinue: () {},
          child: const Text('content'),
        ),
      ));

      // The design uses one bar per step rather than a continuous track, so
      // progress is "how many bars are filled", not a fraction.
      final bars = tester.widget<FsStepBars>(find.byType(FsStepBars));
      expect(bars.step, 2);
      expect(bars.total, 4);
      expect(find.text('STEP 2 / 4'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('Continue calls onContinue', (tester) async {
      var continued = 0;
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScaffold(
          step: 1,
          total: 4,
          onContinue: () => continued++,
          child: const Text('content'),
        ),
      ));

      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();

      expect(continued, 1);
    });

    testWidgets('Skip calls onSkip when one is given', (tester) async {
      var skipped = 0;
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScaffold(
          step: 1,
          total: 4,
          onContinue: () {},
          onSkip: () => skipped++,
          child: const Text('content'),
        ),
      ));

      await tester.tap(find.byKey(const Key('skip')));
      await tester.pumpAndSettle();

      expect(skipped, 1);
    });

    testWidgets('back calls onBack when one is given', (tester) async {
      var went = 0;
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScaffold(
          step: 2,
          total: 4,
          onContinue: () {},
          onBack: () => went++,
          child: const Text('content'),
        ),
      ));

      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();

      expect(went, 1);
    });

    testWidgets('offers no back control on the first step', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScaffold(
          step: 1,
          total: 4,
          onContinue: () {},
          child: const Text('content'),
        ),
      ));

      expect(find.byKey(const Key('back')), findsNothing);
    });
  });

  group('EditScaffold', () {
    testWidgets('shows its title and saves', (tester) async {
      var saved = 0;
      await tester.pumpWidget(MaterialApp(
        home: EditScaffold(
          title: 'Your goal',
          onSave: () => saved++,
          child: const Text('content'),
        ),
      ));

      expect(find.text('Your goal'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);

      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      expect(saved, 1);
    });

    testWidgets('shows no wizard chrome', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: EditScaffold(
          title: 'Your goal',
          onSave: () {},
          child: const Text('content'),
        ),
      ));

      // This is what makes it a different wrapper rather than the same one
      // with different labels: editing one answer from Settings is not a
      // position in a sequence, and there is nothing to skip.
      expect(find.byType(FsStepBars), findsNothing);
      expect(find.byKey(const Key('skip')), findsNothing);
      expect(find.byKey(const Key('continue')), findsNothing);
    });
  });
}
