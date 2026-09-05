import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/onboarding/presentation/generating_view.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool saved = false,
  List<String> avoiding = const [],
}) =>
    tester.pumpWidget(MaterialApp(
      home: GeneratingView(saved: saved, avoiding: avoiding),
    ));

void main() {
  testWidgets('says what it is doing', (tester) async {
    await _pump(tester);

    expect(find.text('Building your plan…'), findsOneWidget);
  });

  testWidgets('names the injuries it is working around', (tester) async {
    await _pump(tester, saved: true, avoiding: ['Lower back', 'Right knee']);

    // The mockup hardcodes "Avoiding lower-back load". Reading the user's own
    // reported injuries back to them is the whole point of the row — a
    // regression to fixed copy would pass a findsOneWidget on any text.
    expect(find.text('Avoiding Lower back, Right knee'), findsOneWidget);
  });

  testWidgets('omits the avoiding row when nothing was reported',
      (tester) async {
    await _pump(tester, saved: true);

    expect(find.textContaining('Avoiding'), findsNothing,
        reason: 'inventing an injury row for a healthy user would be fiction');
  });

  testWidgets('does not tick the save row until the write has finished',
      (tester) async {
    await _pump(tester, saved: false);

    expect(find.byKey(const Key('gen.saved.done')), findsNothing);
  });

  testWidgets('ticks the save row once the write has finished', (tester) async {
    await _pump(tester, saved: true);

    expect(find.byKey(const Key('gen.saved.done')), findsOneWidget);
  });

  testWidgets('refuses to pop, so back cannot abandon a half-written profile',
      (tester) async {
    await _pump(tester, saved: true);

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
  });

  testWidgets('never ticks the exercise row, which is still in flight',
      (tester) async {
    await _pump(tester, saved: true, avoiding: ['Lower back']);

    expect(find.text('Choosing your exercises'), findsOneWidget);
    expect(find.byKey(const Key('gen.exercises.done')), findsNothing,
        reason: 'this row is the work still running; ticking it would be a lie');
  });
}
