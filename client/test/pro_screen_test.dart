import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/pro/presentation/pro_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: fsLightTheme(), home: const ProScreen()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it names the price of both plans', (tester) async {
    await _pump(tester);

    // Straight from the prototype, and the figures the subscriptions table's
    // price_php column is waiting for.
    expect(find.textContaining('249'), findsOneWidget);
    expect(find.textContaining('149'), findsOneWidget);
  });

  testWidgets('what Pro unlocks today is what Pro actually gates', (
    tester,
  ) async {
    await _pump(tester);

    final today = find.byKey(const Key('pro.today'));
    expect(today, findsOneWidget);

    // Volume by muscle is the only paid feature in the app, gated twice:
    // the Progress card and the muscle section of a shared report.
    expect(
      find.descendant(of: today, matching: find.textContaining('muscle')),
      findsNWidgets(2),
    );
  });

  testWidgets('everything not built is under a heading that says so', (
    tester,
  ) async {
    await _pump(tester);

    final planned = find.byKey(const Key('pro.planned'));
    expect(planned, findsOneWidget);

    // The prototype sells food photo recognition and Filipino meal planning.
    // Neither exists -- there is no nutrition feature at all -- so they may
    // appear only as things that are coming, never as things you get.
    expect(
      find.descendant(of: planned, matching: find.textContaining('Food photo')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('pro.today')),
        matching: find.textContaining('Food photo'),
      ),
      findsNothing,
    );
  });

  testWidgets('there is nothing to buy and the screen says why', (
    tester,
  ) async {
    await _pump(tester);

    // The prototype's footer offers a 7-day trial and a Restore link. Neither
    // can work: nothing reads or writes the subscriptions table, and
    // is_premium is deliberately outside the profile PATCH allowlist, so the
    // app cannot grant itself Pro. A button that cannot do its job is worse
    // than a sentence explaining there isn't one.
    expect(find.textContaining('free trial'), findsNothing);
    expect(find.text('Restore'), findsNothing);

    // Scrolled to, because the note sits below the fold on a test viewport
    // and a ListView does not build what it has not reached.
    await tester.scrollUntilVisible(find.byKey(const Key('pro.notYet')), 200);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pro.notYet')), findsOneWidget);
  });

  testWidgets('it can be closed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ProScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('pro.close')));
    await tester.pumpAndSettle();

    expect(find.byType(ProScreen), findsNothing);
  });
}
