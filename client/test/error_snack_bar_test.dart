import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/nutrition/presentation/error_snack_bar.dart';

/// Runs [saveOrOfferRetry] with a save that throws each of [errors] in turn
/// (then succeeds), and returns how many times it ran.
Future<int Function()> _run(WidgetTester tester, List<Object> errors) async {
  var calls = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => saveOrOfferRetry<int>(
              ScaffoldMessenger.of(context),
              save: () async {
                final i = calls++;
                if (i < errors.length) throw errors[i];
                return i;
              },
              failure: "Couldn't save Turon.",
              persist: false,
            ),
            child: const Text('save'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('save'));
  await tester.pumpAndSettle();
  return () => calls;
}

// L-61: the snack bar said only "Couldn't save …" -- not why -- and offered
// Try again even when sending the same thing again could only fail again.
void main() {
  testWidgets('a lost connection says why, and Try again sends it again', (
    tester,
  ) async {
    final calls = await _run(tester, [
      const ApiException('NETWORK_ERROR', 'Is adb reverse set up?'),
    ]);
    expect(
      find.text(
        "Couldn't save Turon. Couldn't reach FitSync. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(calls(), 2);
  });

  testWidgets('a server fault offers Try again too', (tester) async {
    await _run(tester, [
      const ApiException('INTERNAL_ERROR', 'An unexpected error occurred.'),
    ]);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets(
    "a refusal the same request can't get past says why, with no Try again",
    (tester) async {
      final calls = await _run(tester, [
        const ApiException('ENTRY_NOT_FOUND', 'No such entry.'),
      ]);
      expect(find.text("Couldn't save Turon. No such entry."), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(calls(), 1);
    },
  );
}
