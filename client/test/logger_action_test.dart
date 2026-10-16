import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/sessions/presentation/widgets/logger_action.dart';
import 'package:fitsync/features/sessions/presentation/widgets/set_drafts.dart';

Widget _host(Widget child) => MaterialApp(
  theme: fsLightTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('names the set it is about to log', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    await tester.pumpWidget(
      _host(
        LoggerAction(
          activeSetNumber: 3,
          isLastExercise: false,
          drafts: drafts,
          unit: WeightUnit.kg,
          onCompleteSet: (_, _, _) async {},
          onNextExercise: () {},
          onFinish: () {},
        ),
      ),
    );

    expect(find.text('Complete set 3'), findsOneWidget);
  });

  testWidgets('reports the active row\'s typed weight and reps', (
    tester,
  ) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);
    drafts.weight(2).text = '25';
    drafts.reps(2).text = '8';

    int? gotSet;
    double? gotWeight;
    int? gotReps;

    await tester.pumpWidget(
      _host(
        LoggerAction(
          activeSetNumber: 2,
          isLastExercise: false,
          drafts: drafts,
          unit: WeightUnit.kg,
          onCompleteSet: (setNumber, weightKg, reps) async {
            gotSet = setNumber;
            gotWeight = weightKg;
            gotReps = reps;
          },
          onNextExercise: () {},
          onFinish: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(gotSet, 2);
    expect(gotWeight, 25);
    expect(gotReps, 8);
  });

  // The storage contract, now that the button is what reads the field:
  // whatever unit is on screen, the server is handed kilograms.
  testWidgets('a weight typed in pounds is reported in kilograms', (
    tester,
  ) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);
    drafts.weight(1).text = '100';
    drafts.reps(1).text = '5';

    double? sentKg;
    await tester.pumpWidget(
      _host(
        LoggerAction(
          activeSetNumber: 1,
          isLastExercise: false,
          drafts: drafts,
          unit: WeightUnit.lb,
          onCompleteSet: (_, weightKg, _) async => sentKg = weightKg,
          onNextExercise: () {},
          onFinish: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(sentKg, closeTo(45.359237, 1e-9));
  });

  testWidgets('an empty weight is sent as null, not zero', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);
    drafts.reps(1).text = '10';

    var called = false;
    double? sentKg = 99;
    await tester.pumpWidget(
      _host(
        LoggerAction(
          activeSetNumber: 1,
          isLastExercise: false,
          drafts: drafts,
          unit: WeightUnit.kg,
          onCompleteSet: (_, weightKg, _) async {
            called = true;
            sentKg = weightKg;
          },
          onNextExercise: () {},
          onFinish: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    // A bodyweight set has no weight; only missing reps asks first.
    expect(find.byType(AlertDialog), findsNothing);
    expect(called, isTrue);
    expect(sentKg, isNull);
  });

  testWidgets('a finished exercise offers the next one', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    var advanced = false;
    await tester.pumpWidget(
      _host(
        LoggerAction(
          activeSetNumber: null,
          isLastExercise: false,
          drafts: drafts,
          unit: WeightUnit.kg,
          onCompleteSet: (_, _, _) async {},
          onNextExercise: () => advanced = true,
          onFinish: () {},
        ),
      ),
    );

    expect(find.text('Next exercise'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(advanced, isTrue);
  });

  testWidgets('the last finished exercise offers to finish the session', (
    tester,
  ) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);

    var finished = false;
    await tester.pumpWidget(
      _host(
        LoggerAction(
          activeSetNumber: null,
          isLastExercise: true,
          drafts: drafts,
          unit: WeightUnit.kg,
          onCompleteSet: (_, _, _) async {},
          onNextExercise: () {},
          onFinish: () => finished = true,
        ),
      ),
    );

    expect(find.text('Finish session'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
  });

  // The retry moved here with the action. A failed write must not tick the
  // set, and must leave a way to try again.
  testWidgets('a failed write shows a retry and logs nothing', (tester) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);
    drafts.reps(1).text = '8';

    var attempts = 0;
    await tester.pumpWidget(
      _host(
        LoggerAction(
          activeSetNumber: 1,
          isLastExercise: false,
          drafts: drafts,
          unit: WeightUnit.kg,
          onCompleteSet: (_, _, _) async {
            attempts++;
            throw Exception('network');
          },
          onNextExercise: () {},
          onFinish: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.text('Retry set 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  // The failure belongs to the set it happened on. This State outlives a
  // change of set -- reopening a stored row, or jumping to another exercise
  // that is already logged against, keeps the logging stage and rebuilds
  // this button in place -- so a _failed left standing would offer to
  // "Retry set 2" for a set nobody has tried.
  testWidgets('a failure does not follow the button onto another set', (
    tester,
  ) async {
    final drafts = SetDrafts();
    addTearDown(drafts.dispose);
    drafts.reps(1).text = '8';

    var active = 1;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoggerAction(
                activeSetNumber: active,
                isLastExercise: false,
                drafts: drafts,
                unit: WeightUnit.kg,
                onCompleteSet: (_, _, _) async {
                  throw Exception('network');
                },
                onNextExercise: () {},
                onFinish: () {},
              ),
              TextButton(
                // Stands in for whatever moved the active set without rebuilding
                // this widget from scratch.
                onPressed: () => setState(() => active = 2),
                child: const Text('move to set 2'),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('logger.primary')));
    await tester.pumpAndSettle();
    expect(find.text('Retry set 1'), findsOneWidget);

    await tester.tap(find.text('move to set 2'));
    await tester.pumpAndSettle();

    expect(find.text('Complete set 2'), findsOneWidget);
    expect(find.text('Retry set 2'), findsNothing);
  });
  group('a set with no reps asks first', () {
    // A real reps box for set 2, wired to the same controller the row uses,
    // so "Add reps" has a field to put the caret in.
    Widget hostWithField(SetDrafts drafts, LoggerAction action) => _host(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(key: const Key('reps2'), controller: drafts.reps(2)),
          action,
        ],
      ),
    );

    LoggerAction action(SetDrafts drafts, List<int?> logged) => LoggerAction(
      activeSetNumber: 2,
      isLastExercise: false,
      drafts: drafts,
      unit: WeightUnit.kg,
      onCompleteSet: (_, _, reps) async => logged.add(reps),
      onNextExercise: () {},
      onFinish: () {},
    );

    testWidgets('Add reps logs nothing and focuses the reps box', (
      tester,
    ) async {
      final drafts = SetDrafts();
      addTearDown(drafts.dispose);
      drafts.weight(2).text = '40';
      final logged = <int?>[];

      await tester.pumpWidget(hostWithField(drafts, action(drafts, logged)));
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pumpAndSettle();

      expect(find.text('Log set 2 without reps?'), findsOneWidget);
      expect(logged, isEmpty);

      await tester.tap(find.text('Add reps'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(logged, isEmpty);
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('reps2')),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.focusNode.hasFocus, isTrue);
    });

    testWidgets('Log anyway logs the set with no reps', (tester) async {
      final drafts = SetDrafts();
      addTearDown(drafts.dispose);
      final logged = <int?>[];

      await tester.pumpWidget(hostWithField(drafts, action(drafts, logged)));
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log anyway'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(logged, [null]);
    });

    testWidgets('fits a 320 dp screen at 2.0x text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final drafts = SetDrafts();
      addTearDown(drafts.dispose);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: hostWithField(drafts, action(drafts, <int?>[])),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'before tap');
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pumpAndSettle();

      expect(find.text('Log set 2 without reps?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Both actions stay reachable and at least 48 dp tall.
      for (final label in ['Add reps', 'Log anyway']) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(TextButton),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      }
    });
  });

  group('a failed save says why', () {
    Future<void> failWith(WidgetTester tester, Object error) async {
      final drafts = SetDrafts();
      addTearDown(drafts.dispose);
      drafts.reps(1).text = '8';
      await tester.pumpWidget(
        _host(
          LoggerAction(
            activeSetNumber: 1,
            isLastExercise: false,
            drafts: drafts,
            unit: WeightUnit.kg,
            onCompleteSet: (_, _, _) async => throw error,
            onNextExercise: () {},
            onFinish: () {},
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pumpAndSettle();
    }

    testWidgets('an unreachable server is named in plain words', (
      tester,
    ) async {
      await failWith(
        tester,
        const ApiException(
          'NETWORK_ERROR',
          'No connection. Check your internet and try again.',
        ),
      );

      expect(find.text('Retry set 1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(
            'No connection. Check your internet and try again.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unknown error never shows its raw text', (tester) async {
      await failWith(tester, Exception('SocketException: errno 61'));

      expect(find.text('Retry set 1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Something went wrong.'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('SocketException'), findsNothing);
    });
  });

  group('a failed save leaves Retry reachable', () {
    // The logger's button is its footer, at the bottom of the Scaffold body,
    // which is exactly where a default SnackBar lands. The host builds the
    // footer the way the logger screen does: SafeArea, then its padding.
    Widget footerHost(Widget action) => MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: action,
              ),
            ),
          ],
        ),
      ),
    );

    // On a phone the keyboard is usually still up when Complete is tapped:
    // the set row only starts hiding it on pointer-down. While it is up the
    // system's bottom inset (a gesture bar, say) is drawn under it, so the
    // body's own bottom padding is what is left over.
    void setKeyboard(WidgetTester tester, double inset, double systemBar) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      tester.view.viewPadding = FakeViewPadding(bottom: systemBar);
      tester.view.padding = FakeViewPadding(
        bottom: (systemBar - inset).clamp(0, double.infinity).toDouble(),
      );
    }

    Future<void> checkRetryReachable(
      WidgetTester tester, {
      double keyboardAtTap = 0,
      double keyboardAtFailure = 0,
      double systemBar = 0,
    }) async {
      final drafts = SetDrafts();
      addTearDown(drafts.dispose);
      drafts.reps(1).text = '8';
      var calls = 0;
      final firstSave = Completer<void>();
      await tester.pumpWidget(
        footerHost(
          LoggerAction(
            activeSetNumber: 1,
            isLastExercise: false,
            drafts: drafts,
            unit: WeightUnit.kg,
            onCompleteSet: (_, _, _) async {
              calls++;
              if (calls == 1) await firstSave.future;
            },
            onNextExercise: () {},
            onFinish: () {},
          ),
        ),
      );
      setKeyboard(tester, keyboardAtTap, systemBar);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logger.primary')));
      await tester.pump();
      // The keyboard goes down (or part way) while the save is in flight.
      setKeyboard(tester, keyboardAtFailure, systemBar);
      // Not pumpAndSettle: the button's spinner turns until the save ends.
      await tester.pump(const Duration(milliseconds: 300));
      firstSave.completeError(
        const ApiException(
          'NETWORK_ERROR',
          'No connection. Check your internet and try again.',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final snackBar = find.byType(SnackBar);
      expect(snackBar, findsOneWidget);
      final primary = find.byKey(const Key('logger.primary'));
      expect(find.text('Retry set 1'), findsOneWidget);
      // The bar's own surface: the SnackBar widget's box also spans the
      // margin below it, which is see-through and lets taps pass.
      final bar = find
          .descendant(of: snackBar, matching: find.byType(Material))
          .first;
      expect(
        tester.getRect(bar).overlaps(tester.getRect(primary)),
        isFalse,
        reason: 'the SnackBar explains Retry; it must not cover it',
      );
      expect(
        tester.getRect(primary).top - tester.getRect(bar).bottom,
        moreOrLessEquals(8, epsilon: 0.5),
        reason: 'the SnackBar sits just above Retry, not far up the screen',
      );

      await tester.tap(primary);
      await tester.pumpAndSettle();
      expect(calls, 2, reason: 'the Retry tap reached the button');
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'a save that worked leaves no stale failure showing',
      );
      expect(find.text('Complete set 1'), findsOneWidget);
    }

    void onScreen(
      String name,
      Size size, {
      double textScale = 1,
      double keyboardAtTap = 0,
      double keyboardAtFailure = 0,
      double systemBar = 0,
    }) {
      testWidgets(name, (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await checkRetryReachable(
          tester,
          keyboardAtTap: keyboardAtTap,
          keyboardAtFailure: keyboardAtFailure,
          systemBar: systemBar,
        );
      });
    }

    onScreen('on a normal phone', const Size(360, 780));
    onScreen(
      'on a 320 dp screen at 2.0x text',
      const Size(320, 780),
      textScale: 2,
    );
    onScreen(
      'with a gesture bar below the footer',
      const Size(360, 780),
      systemBar: 24,
    );
    onScreen(
      'when the keyboard was up at the tap',
      const Size(360, 780),
      keyboardAtTap: 250,
      systemBar: 24,
    );
    onScreen(
      'when the keyboard was up at the tap, on a shorter phone',
      const Size(360, 740),
      keyboardAtTap: 280,
    );
    onScreen(
      'when the keyboard is part way down at the failure',
      const Size(360, 780),
      keyboardAtTap: 250,
      keyboardAtFailure: 100,
      systemBar: 24,
    );
    onScreen(
      'when the keyboard was up, on a 320 dp screen at 2.0x text',
      const Size(320, 780),
      textScale: 2,
      keyboardAtTap: 250,
      systemBar: 24,
    );
    onScreen(
      'when the keyboard was up, on a short phone at 2.0x text',
      const Size(360, 640),
      textScale: 2,
      keyboardAtTap: 250,
    );
  });
}
