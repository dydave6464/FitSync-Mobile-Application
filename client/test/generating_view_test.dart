import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/onboarding/presentation/generating_view.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool saved = false,
  bool planReady = false,
  List<String> avoiding = const [],
}) =>
    tester.pumpWidget(MaterialApp(
      home: GeneratingView(
        saved: saved,
        planReady: planReady,
        avoiding: avoiding,
      ),
    ));

/// Tears the view down so its reveal timers are cancelled. A widget test fails
/// if a timer is still pending when it ends.
Future<void> _close(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

/// Just past the slot each row is allowed to tick in.
Duration _justAfter(int row) =>
    GeneratingView.revealAt[row] + const Duration(milliseconds: 100);

void main() {
  testWidgets('says what it is doing', (tester) async {
    await _pump(tester);

    expect(find.text('Building your plan…'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('names the injuries it is working around', (tester) async {
    await _pump(tester, saved: true, avoiding: ['Lower back', 'Right knee']);

    // The mockup hardcodes "Avoiding lower-back load". Reading the user's own
    // reported injuries back to them is the whole point of the row — a
    // regression to fixed copy would pass a findsOneWidget on any text.
    expect(find.text('Avoiding Lower back, Right knee'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('still has an injury row to tick when nothing was reported',
      (tester) async {
    await _pump(tester, saved: true);

    // A healthy user watched a two-row list where everyone else saw three.
    // The row says what is true for them instead of being dropped.
    expect(find.text('No injuries to work around'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('ticks its rows one at a time, not all at once', (tester) async {
    await _pump(tester, saved: true, planReady: true, avoiding: ['Lower back']);

    // Everything this screen reports is already done — but firing three ticks
    // in the same frame reads as a flicker, not as progress.
    expect(find.byKey(const Key('gen.saved.done')), findsNothing);

    await tester.pump(_justAfter(0));
    expect(find.byKey(const Key('gen.saved.done')), findsOneWidget);
    expect(find.byKey(const Key('gen.avoiding.done')), findsNothing);

    await tester.pump(_justAfter(1) - _justAfter(0));
    expect(find.byKey(const Key('gen.avoiding.done')), findsOneWidget);
    expect(find.byKey(const Key('gen.exercises.done')), findsNothing);

    await tester.pump(_justAfter(2) - _justAfter(1));
    expect(find.byKey(const Key('gen.exercises.done')), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a row still waits for its work, however long its slot has passed',
      (tester) async {
    await _pump(tester, saved: false, planReady: false, avoiding: ['Lower back']);

    await tester.pump(GeneratingView.minimumRun * 2);

    // The pacing decides how early a tick may appear, never whether it is
    // earned. Ticking on a timer alone would be the prototype's fiction.
    expect(find.byKey(const Key('gen.saved.done')), findsNothing);
    expect(find.byKey(const Key('gen.avoiding.done')), findsNothing);
    expect(find.byKey(const Key('gen.exercises.done')), findsNothing);
    await _close(tester);
  });

  testWidgets('the exercises row waits for the plan, not just for its slot',
      (tester) async {
    await _pump(tester, saved: true, planReady: false);

    await tester.pump(_justAfter(2));

    expect(find.byKey(const Key('gen.saved.done')), findsOneWidget);
    expect(find.byKey(const Key('gen.exercises.done')), findsNothing,
        reason: 'this row is the work still running; ticking it would be a lie');
    await _close(tester);
  });

  testWidgets('refuses to pop, so back cannot abandon a half-written profile',
      (tester) async {
    await _pump(tester, saved: true);

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    await _close(tester);
  });

  testWidgets('stays up long enough to be read', (tester) async {
    // The whole round trip can finish in under a second. Six to seven seconds
    // is the floor the screen is built around: the last row cannot tick before
    // 5.5s, and it is held afterwards so its tick is seen.
    expect(GeneratingView.minimumRun.inMilliseconds, greaterThanOrEqualTo(6000));
    expect(GeneratingView.minimumRun,
        GeneratingView.revealAt.last + GeneratingView.tail);
  });
}
