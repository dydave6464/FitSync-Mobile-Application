import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/onboarding/presentation/edit_scaffold.dart';
import 'package:fitsync/features/onboarding/presentation/onboarding_scaffold.dart';

void main() {
  group('OnboardingScaffold', () {
    testWidgets('shows progress for the current step', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 2,
            total: 4,
            onContinue: () {},
            child: const Text('content'),
          ),
        ),
      );

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
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 1,
            total: 4,
            onContinue: () => continued++,
            child: const Text('content'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();

      expect(continued, 1);
    });

    testWidgets('Skip calls onSkip when one is given', (tester) async {
      var skipped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 1,
            total: 4,
            onContinue: () {},
            onSkip: () => skipped++,
            child: const Text('content'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('skip')));
      await tester.pumpAndSettle();

      expect(skipped, 1);
    });

    testWidgets('back calls onBack when one is given', (tester) async {
      var went = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 2,
            total: 4,
            onContinue: () {},
            onBack: () => went++,
            child: const Text('content'),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();

      expect(went, 1);
    });

    testWidgets('offers no back control on the first step', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 1,
            total: 4,
            onContinue: () {},
            child: const Text('content'),
          ),
        ),
      );

      expect(find.byKey(const Key('back')), findsNothing);
    });
  });

  group('OnboardingScaffold additions', () {
    testWidgets('names the back chevron "Back" for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 2,
            total: 4,
            onContinue: () {},
            onBack: () {},
            child: const Text('content'),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byKey(const Key('back'))),
        isSemantics(label: 'Back', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('shows the error directly above Continue', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 2,
            total: 4,
            onContinue: () {},
            error: 'That did not save.',
            child: const Text('content'),
          ),
        ),
      );

      final error = tester.getRect(find.byKey(const Key('error')));
      final cont = tester.getRect(find.byKey(const Key('continue')));
      expect(find.text('That did not save.'), findsOneWidget);
      expect(error.bottom, lessThanOrEqualTo(cont.top));
      expect(cont.top - error.bottom, lessThan(24));
    });

    testWidgets('offers Sign out when given one, at least 48dp tall', (
      tester,
    ) async {
      var signedOut = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 1,
            total: 4,
            onContinue: () {},
            onSignOut: () => signedOut++,
            child: const Text('content'),
          ),
        ),
      );

      expect(find.text('Sign out'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('signOut'))).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byKey(const Key('signOut')));
      expect(signedOut, 1);
    });

    // The header's controls were 38dp squares, short of the 48dp a thumb
    // needs. The hit area grows; what is drawn stays where it was.
    testWidgets('Back and Skip take a 48dp tap, Back still drawn at 38dp', (
      tester,
    ) async {
      var went = 0;
      var skipped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 2,
            total: 4,
            onContinue: () {},
            onBack: () => went++,
            onSkip: () => skipped++,
            child: const Text('content'),
          ),
        ),
      );

      final back = tester.getRect(find.byKey(const Key('back')));
      final skip = tester.getRect(find.byKey(const Key('skip')));
      for (final target in [back, skip]) {
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
      }

      // The bordered square keeps its size and its 20dp inset from the edge.
      final square = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('back')),
          matching: find.byType(Material),
        ),
      );
      expect(square.size, const Size(38, 38));
      expect(square.left, 20);

      // A tap in the slack around the square still goes back.
      await tester.tapAt(back.topLeft + const Offset(1, 1));
      await tester.tapAt(skip.bottomRight - const Offset(1, 1));
      expect(went, 1);
      expect(skipped, 1);
    });

    testWidgets('shows the hint directly above Continue', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 5,
            total: 6,
            onContinue: null,
            hint: 'Answer every question to continue',
            child: const SizedBox(height: 2000),
          ),
        ),
      );

      // Beside the greyed button it explains, however long the step is,
      // rather than at the end of the content where it can be scrolled away.
      final hint = tester.getRect(
        find.text('Answer every question to continue'),
      );
      final cont = tester.getRect(find.byKey(const Key('continue')));
      expect(hint.bottom, lessThanOrEqualTo(cont.top));
      expect(cont.top - hint.bottom, lessThan(24));
    });

    testWidgets('the hint is readable text, not the faint tertiary grey', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 5,
            total: 6,
            onContinue: null,
            hint: 'Answer every question to continue',
            child: const Text('content'),
          ),
        ),
      );

      final finder = find.text('Answer every question to continue');
      final context = tester.element(finder);
      expect(tester.widget<Text>(finder).style?.color, context.fs.text2);
    });

    testWidgets('shows no hint when none is given', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScaffold(
            step: 5,
            total: 6,
            onContinue: () {},
            child: const Text('content'),
          ),
        ),
      );

      expect(find.byKey(const Key('hint')), findsNothing);
    });

    testWidgets('fits a 320dp screen at 2x text with an error and Sign out', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: 2,
            maxScaleFactor: 2,
            child: OnboardingScaffold(
              step: 1,
              total: 6,
              onContinue: () {},
              onSkip: () {},
              onSignOut: () {},
              error:
                  "Couldn't reach FitSync. Check your connection and try "
                  'again.',
              child: const Text('content'),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    // The health step is the one that shows a hint: it has a back control
    // and no Skip or Sign out, and a failed save can leave an error up too.
    testWidgets('fits a 320dp screen at 2x text with an error and a hint', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: 2,
            maxScaleFactor: 2,
            child: OnboardingScaffold(
              step: 5,
              total: 6,
              onContinue: null,
              onBack: () {},
              hint: 'Answer every question to continue',
              error:
                  "Couldn't reach FitSync. Check your connection and try "
                  'again.',
              child: const Text('content'),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('EditScaffold', () {
    testWidgets('shows its title and saves', (tester) async {
      var saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: EditScaffold(
            title: 'Your goal',
            onSave: () => saved++,
            child: const Text('content'),
          ),
        ),
      );

      expect(find.text('Your goal'), findsOneWidget);
      expect(find.text('content'), findsOneWidget);

      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      expect(saved, 1);
    });

    testWidgets('shows the hint directly above Save', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditScaffold(
            title: 'Health',
            onSave: null,
            hint: 'Answer every question to save',
            child: const SizedBox(height: 2000),
          ),
        ),
      );

      final hint = tester.getRect(find.text('Answer every question to save'));
      final save = tester.getRect(find.byKey(const Key('save')));
      expect(hint.bottom, lessThanOrEqualTo(save.top));
      expect(save.top - hint.bottom, lessThan(24));
    });

    testWidgets('shows no wizard chrome', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditScaffold(
            title: 'Your goal',
            onSave: () {},
            child: const Text('content'),
          ),
        ),
      );

      // This is what makes it a different wrapper rather than the same one
      // with different labels: editing one answer from Settings is not a
      // position in a sequence, and there is nothing to skip.
      expect(find.byType(FsStepBars), findsNothing);
      expect(find.byKey(const Key('skip')), findsNothing);
      expect(find.byKey(const Key('continue')), findsNothing);
    });
  });
}
