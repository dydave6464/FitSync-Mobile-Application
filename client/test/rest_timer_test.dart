import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/sessions/presentation/widgets/rest_timer.dart';

Widget _host(Widget child) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('counts down and fires onDone exactly once at zero', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(RestTimer(
      duration: const Duration(seconds: 3),
      onDone: () => done++,
    )));

    expect(find.text('0:03'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:02'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0:00'), findsOneWidget);
    expect(done, 1);

    // The timer must stop at zero rather than running negative.
    await tester.pump(const Duration(seconds: 2));
    expect(done, 1);
    expect(find.text('0:00'), findsOneWidget);
  });

  testWidgets('pads seconds under ten', (tester) async {
    await tester.pumpWidget(_host(RestTimer(
      duration: const Duration(seconds: 65),
      onDone: () {},
    )));

    expect(find.text('1:05'), findsOneWidget);
  });

  testWidgets('skip fires the callback', (tester) async {
    var skipped = false;
    await tester.pumpWidget(_host(RestTimer(
      duration: const Duration(seconds: 60),
      onDone: () {},
      onSkip: () => skipped = true,
    )));

    await tester.tap(find.byKey(const Key('rest.skip')));
    expect(skipped, isTrue);
  });

  testWidgets('disposing mid-countdown does not fire onDone', (tester) async {
    var done = 0;
    await tester.pumpWidget(_host(RestTimer(
      duration: const Duration(seconds: 3),
      onDone: () => done++,
    )));

    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump(const Duration(seconds: 5));

    expect(done, 0);
  });

  testWidgets('renders no skip button when onSkip is omitted', (tester) async {
    await tester.pumpWidget(_host(RestTimer(
      duration: const Duration(seconds: 60),
      onDone: () {},
    )));

    expect(find.byKey(const Key('rest.skip')), findsNothing);
  });
}
