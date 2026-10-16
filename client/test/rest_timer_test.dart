import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/sessions/presentation/widgets/rest_sheet.dart';
import 'package:fitsync/features/sessions/presentation/widgets/rest_timer.dart';

Widget _host(Widget child) => MaterialApp(
  theme: fsLightTheme(),
  home: Scaffold(body: Center(child: child)),
);

ValueNotifier<RestReading?> _reading(int seconds) =>
    ValueNotifier((secondsLeft: seconds, fractionLeft: 1.0));

void main() {
  testWidgets('shows the time left from the reading, and follows it', (
    tester,
  ) async {
    final reading = _reading(90);
    await tester.pumpWidget(_host(RestTimer(reading: reading)));

    expect(find.text('REST'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);

    reading.value = (secondsLeft: 65, fractionLeft: 0.7);
    await tester.pump();
    expect(find.text('1:05'), findsOneWidget);
  });

  // Amber text on the light theme measured 2.58:1; the numbers are what is
  // read across a gym, so they take the text colour and amber stays on the
  // tint and outline.
  testWidgets('reads in the text colour, at 12', (tester) async {
    await tester.pumpWidget(_host(RestTimer(reading: _reading(90))));

    final style = tester
        .widget<Text>(find.byKey(const Key('rest.remaining')))
        .style!;
    expect(style.color, FsTokens.light.text);
    expect(style.fontSize, 12);
  });

  testWidgets('"Rest over" in place of the countdown, and not tappable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(RestTimer(reading: _reading(0), over: true, onOpen: () {})),
    );

    expect(find.byKey(const Key('rest.over')), findsOneWidget);
    expect(find.text('Rest over'), findsOneWidget);
    expect(find.byKey(const Key('rest.remaining')), findsNothing);
    expect(find.byKey(const Key('rest.open')), findsNothing);
  });

  testWidgets('has no tap target without onOpen', (tester) async {
    await tester.pumpWidget(_host(RestTimer(reading: _reading(60))));

    expect(find.byKey(const Key('rest.open')), findsNothing);
    expect(find.byKey(const Key('rest.affordance')), findsNothing);
  });

  group('with onOpen', () {
    testWidgets('looks tappable, is at least 48 high, and opens', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(RestTimer(reading: _reading(60), onOpen: () => opened++)),
      );

      expect(find.byKey(const Key('rest.affordance')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('rest.open'))).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byKey(const Key('rest.open')));
      expect(opened, 1);
    });

    testWidgets('is announced as the rest timer with the time left', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(RestTimer(reading: _reading(90), onOpen: () {})),
      );

      expect(
        tester.getSemantics(find.byKey(const Key('rest.open'))),
        isSemantics(
          isButton: true,
          label: 'Rest timer, 1 minute 30 seconds left',
        ),
      );
      handle.dispose();
    });
  });

  test('spokenRest says minutes and seconds the way a person would', () {
    expect(spokenRest(90), '1 minute 30 seconds');
    expect(spokenRest(45), '45 seconds');
    expect(spokenRest(120), '2 minutes');
    expect(spokenRest(61), '1 minute 1 second');
    expect(spokenRest(1), '1 second');
    expect(spokenRest(0), '0 seconds');
  });
}
