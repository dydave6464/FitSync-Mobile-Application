import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/widgets/rest_timer.dart';

import 'helpers/fake_training_settings.dart';

Widget _host(Widget child, {FakeTrainingSettings? settings}) => ProviderScope(
  overrides: [
    trainingSettingsRepositoryProvider.overrideWithValue(
      settings ?? FakeTrainingSettings(),
    ),
  ],
  child: MaterialApp(
    theme: fsLightTheme(),
    home: Scaffold(body: Center(child: child)),
  ),
);

/// Opens the sheet from the tag. Explicit frames rather than pumpAndSettle:
/// the countdown ticks every second, so the screen never goes still.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('rest.open')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The countdown on the tag in the app bar, as opposed to the sheet's.
String _tag(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('rest.remaining'))).data!;

void main() {
  testWidgets('counts down and fires onDone exactly once at zero', (
    tester,
  ) async {
    var done = 0;
    await tester.pumpWidget(
      _host(
        RestTimer(duration: const Duration(seconds: 3), onDone: () => done++),
      ),
    );

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
    await tester.pumpWidget(
      _host(RestTimer(duration: const Duration(seconds: 65), onDone: () {})),
    );

    expect(find.text('1:05'), findsOneWidget);
  });

  testWidgets('disposing mid-countdown does not fire onDone', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      _host(
        RestTimer(duration: const Duration(seconds: 3), onDone: () => done++),
      ),
    );

    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump(const Duration(seconds: 5));

    expect(done, 0);
  });

  testWidgets('has no tap target when onSkip is omitted', (tester) async {
    await tester.pumpWidget(
      _host(RestTimer(duration: const Duration(seconds: 60), onDone: () {})),
    );

    expect(find.byKey(const Key('rest.open')), findsNothing);
    expect(find.byKey(const Key('rest.affordance')), findsNothing);
  });

  group('tapping the tag', () {
    Widget timer({
      int seconds = 60,
      VoidCallback? onDone,
      VoidCallback? onSkip,
    }) => _host(
      RestTimer(
        duration: Duration(seconds: seconds),
        onDone: onDone ?? () {},
        onSkip: onSkip ?? () {},
      ),
    );

    testWidgets('looks tappable: an outline and a chevron', (tester) async {
      await tester.pumpWidget(timer());
      expect(find.byKey(const Key('rest.affordance')), findsOneWidget);
    });

    testWidgets('is at least 48 high to tap', (tester) async {
      await tester.pumpWidget(timer());
      expect(
        tester.getSize(find.byKey(const Key('rest.open'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('opens the rest sheet with the live countdown', (tester) async {
      await tester.pumpWidget(timer());
      await _open(tester);

      expect(find.byKey(const Key('rest.sheet')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('rest.sheet.remaining'))).data,
        '1:00',
      );

      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<Text>(find.byKey(const Key('rest.sheet.remaining'))).data,
        '0:59',
      );
    });

    testWidgets('+30s adds to this rest', (tester) async {
      await tester.pumpWidget(timer());
      await _open(tester);

      await tester.tap(find.byKey(const Key('rest.plus')));
      await tester.pump();

      expect(_tag(tester), '1:30');
      expect(
        tester.widget<Text>(find.byKey(const Key('rest.sheet.remaining'))).data,
        '1:30',
      );
    });

    testWidgets('−30s takes from this rest', (tester) async {
      await tester.pumpWidget(timer());
      await _open(tester);

      await tester.tap(find.byKey(const Key('rest.minus')));
      await tester.pump();

      expect(_tag(tester), '0:30');
    });

    testWidgets('−30s past zero ends the rest and closes the sheet', (
      tester,
    ) async {
      var done = 0;
      await tester.pumpWidget(timer(seconds: 20, onDone: () => done++));
      await _open(tester);

      await tester.tap(find.byKey(const Key('rest.minus')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(done, 1);
      expect(find.byKey(const Key('rest.sheet')), findsNothing);
    });

    testWidgets('Skip rest skips and closes the sheet', (tester) async {
      var skipped = 0;
      await tester.pumpWidget(timer(onSkip: () => skipped++));
      await _open(tester);

      await tester.tap(find.byKey(const Key('rest.skip')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(skipped, 1);
      expect(find.byKey(const Key('rest.sheet')), findsNothing);
    });

    testWidgets('the sheet closes itself when the rest runs out', (
      tester,
    ) async {
      var done = 0;
      await tester.pumpWidget(timer(seconds: 3, onDone: () => done++));
      await _open(tester);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));

      expect(done, 1);
      expect(find.byKey(const Key('rest.sheet')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rest that ends under the sheet does not throw later', (
      tester,
    ) async {
      // The tag is torn down by onDone while its sheet is still animating
      // closed; nothing may tick or notify into the disposed timer after.
      var show = true;
      late StateSetter setOuter;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return show
                  ? RestTimer(
                      duration: const Duration(seconds: 2),
                      onDone: () => setOuter(() => show = false),
                      onSkip: () {},
                    )
                  : const SizedBox();
            },
          ),
        ),
      );
      await _open(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('rest.sheet')), findsNothing);
    });
  });
}
