import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/core/widgets/fs_charts.dart' show FsRing;
import 'package:fitsync/core/widgets/fs_kit.dart' hide FsRing;
import 'package:fitsync/features/sessions/data/rest_alerts.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/widgets/rest_sheet.dart';

import 'helpers/fake_rest_alerts.dart';
import 'helpers/fake_training_settings.dart';

/// Opens the sheet the way the logger's menu does: no countdown, just the
/// default. A countdown-less sheet has nothing ticking, so it can settle.
Future<FakeTrainingSettings> _open(
  WidgetTester tester, {
  int stored = 90,
  FakeRestAlertScheduler? alerts,
  RestAlertStore? alertStore,
}) async {
  final settings = FakeTrainingSettings(stored);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingSettingsRepositoryProvider.overrideWithValue(settings),
        restAlertSchedulerProvider.overrideWithValue(
          alerts ?? FakeRestAlertScheduler(),
        ),
        restAlertStoreProvider.overrideWithValue(
          alertStore ?? RestAlertStore(backing: InMemorySecureStore()),
        ),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRestSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return settings;
}

FsChip _chip(WidgetTester tester, String key) =>
    tester.widget<FsChip>(find.byKey(Key(key)));

void main() {
  testWidgets('offers 30-second steps from 0:30 to 5:00, and Custom', (
    tester,
  ) async {
    await _open(tester);

    for (var s = 30; s <= 300; s += 30) {
      expect(find.byKey(Key('rest.preset.$s')), findsOneWidget, reason: '$s');
    }
    expect(find.byKey(const Key('rest.preset.330')), findsNothing);
    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('5:00'), findsOneWidget);
    expect(find.byKey(const Key('rest.custom')), findsOneWidget);
  });

  testWidgets('the saved rest time is the one selected', (tester) async {
    await _open(tester, stored: 150);

    expect(_chip(tester, 'rest.preset.150').selected, isTrue);
    expect(_chip(tester, 'rest.preset.90').selected, isFalse);
    expect(_chip(tester, 'rest.custom').selected, isFalse);
  });

  testWidgets('without a countdown it shows no timer and no skip', (
    tester,
  ) async {
    await _open(tester);

    expect(find.byKey(const Key('rest.sheet')), findsOneWidget);
    expect(find.byKey(const Key('rest.sheet.remaining')), findsNothing);
    expect(find.byKey(const Key('rest.skip')), findsNothing);
    expect(find.byKey(const Key('rest.plus')), findsNothing);
  });

  testWidgets('says the default applies from the next rest', (tester) async {
    await _open(tester);
    expect(find.textContaining('next rest'), findsOneWidget);
  });

  testWidgets('tapping a preset saves it to the account', (tester) async {
    final settings = await _open(tester);

    await tester.tap(find.byKey(const Key('rest.preset.120')));
    await tester.pumpAndSettle();

    expect(settings.writes, [120]);
    expect(_chip(tester, 'rest.preset.120').selected, isTrue);
  });

  testWidgets('a save that fails says so and keeps the old choice', (
    tester,
  ) async {
    final settings = await _open(tester);
    settings.writeError = Exception('offline');

    await tester.tap(find.byKey(const Key('rest.preset.120')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Couldn't save your rest time."),
      findsOneWidget,
    );
    expect(_chip(tester, 'rest.preset.90').selected, isTrue);
    expect(_chip(tester, 'rest.preset.120').selected, isFalse);
  });

  // Opened from the menu, before any rest, setting the default is the point.
  testWidgets('from the menu, the defaults are open', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('rest.preset.90')), findsOneWidget);
  });

  testWidgets('the default rest row names the saved time', (tester) async {
    await _open(tester, stored: 150);
    expect(find.text('Default rest: 2:30'), findsOneWidget);
  });

  testWidgets('the caption is readable grey, not the faint one', (
    tester,
  ) async {
    await _open(tester);
    final caption = tester.widget<Text>(find.text('Used from your next rest.'));
    expect(caption.style?.color, FsTokens.light.text2);
  });

  // A chip is drawn 27 dp tall; the tap that lands just above it must count.
  testWidgets('a chip takes a tap just outside its paint', (tester) async {
    final settings = await _open(tester);
    final chip = tester.getRect(find.byKey(const Key('rest.preset.120')));

    await tester.tapAt(Offset(chip.center.dx, chip.top - 8));
    await tester.pumpAndSettle();

    expect(settings.writes, [120]);
    expect(
      tester.getSize(find.byKey(const Key('rest.preset.120.target'))).height,
      greaterThanOrEqualTo(48),
    );
  });

  // The band around a chip must not be a focus stop of its own: a screen
  // reader should land on the chip, with its label, once.
  testWidgets('each chip is one labelled node, not wrapped in a blank one', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(tester);

    final keys = [for (final s in restPresets) 'rest.preset.$s', 'rest.custom'];
    for (final key in keys) {
      final node = tester.getSemantics(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(InkWell),
        ),
      );
      expect(node.label, isNotEmpty, reason: key);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      final around = node.parent!.getSemanticsData();
      expect(
        around.hasAction(SemanticsAction.tap) && around.label.isEmpty,
        isFalse,
        reason: '$key sits inside an unlabelled tap node',
      );
    }
    handle.dispose();
  });

  group('the alert switch', () {
    testWidgets('is on by default, and turning it off is remembered', (
      tester,
    ) async {
      final store = RestAlertStore(backing: InMemorySecureStore());
      await _open(tester, alertStore: store);

      expect(
        tester.widget<Switch>(find.byKey(const Key('rest.alert'))).value,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('rest.alert')));
      await tester.pumpAndSettle();

      expect(await store.enabled(), isFalse);
    });

    testWidgets('says when the phone blocks notifications, with a way out', (
      tester,
    ) async {
      final alerts = FakeRestAlertScheduler(granted: false);
      final store = RestAlertStore(backing: InMemorySecureStore());
      await store.markAsked();
      await _open(tester, alerts: alerts, alertStore: store);

      expect(
        find.text(
          "Notifications are blocked for FitSync. Allow them in your phone's "
          'settings to get rest alerts.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('rest.alert.settings')));
      expect(alerts.settingsOpened, 1);
    });

    testWidgets('drops the blocked note once allowed in the phone settings', (
      tester,
    ) async {
      final alerts = FakeRestAlertScheduler(granted: false);
      final store = RestAlertStore(backing: InMemorySecureStore());
      await store.markAsked();
      await _open(tester, alerts: alerts, alertStore: store);
      expect(find.byKey(const Key('rest.alert.blocked')), findsOneWidget);

      alerts.granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rest.alert.blocked')), findsNothing);
    });

    testWidgets('switching on before ever asking asks once', (tester) async {
      final alerts = FakeRestAlertScheduler(granted: false);
      final store = RestAlertStore(backing: InMemorySecureStore());
      await store.setEnabled(false);
      await _open(tester, alerts: alerts, alertStore: store);

      await tester.tap(find.byKey(const Key('rest.alert')));
      await tester.pumpAndSettle();

      expect(alerts.requests, 1);
      expect(await store.asked(), isTrue);
    });
  });

  group('Custom', () {
    Future<void> enter(WidgetTester tester, String text) async {
      await tester.tap(find.byKey(const Key('rest.custom')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rest.custom.field')), text);
      await tester.tap(find.byKey(const Key('rest.custom.save')));
      await tester.pumpAndSettle();
    }

    testWidgets('takes minutes and seconds', (tester) async {
      final settings = await _open(tester);
      await enter(tester, '1:45');

      expect(settings.writes, [105]);
      expect(_chip(tester, 'rest.custom').selected, isTrue);
      expect(find.text('Custom (1:45)'), findsOneWidget);
    });

    testWidgets('takes plain seconds', (tester) async {
      final settings = await _open(tester);
      await enter(tester, '45');
      expect(settings.writes, [45]);
    });

    testWidgets('a saved off-preset time shows as Custom', (tester) async {
      await _open(tester, stored: 105);
      expect(_chip(tester, 'rest.custom').selected, isTrue);
      expect(find.text('Custom (1:45)'), findsOneWidget);
    });

    for (final bad in ['0:05', '9', '10:01', '11:00', 'abc', '1:75', '']) {
      testWidgets('refuses "$bad" without saving', (tester) async {
        final settings = await _open(tester);
        await enter(tester, bad);

        expect(settings.writes, isEmpty);
        expect(find.text('Enter a time from 0:10 to 10:00.'), findsOneWidget);
      });
    }

    testWidgets('accepts the bounds, 0:10 and 10:00', (tester) async {
      final settings = await _open(tester);
      await enter(tester, '0:10');
      await enter(tester, '10:00');
      expect(settings.writes, [10, 600]);
    });
  });

  group('with a running rest', () {
    Future<
      ({
        ValueNotifier<RestReading?> reading,
        List<int> adjusts,
        List<int> skips,
      })
    >
    openRunning(WidgetTester tester) async {
      final reading = ValueNotifier<RestReading?>((
        secondsLeft: 60,
        fractionLeft: 1.0,
      ));
      final adjusts = <int>[];
      final skips = <int>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainingSettingsRepositoryProvider.overrideWithValue(
              FakeTrainingSettings(),
            ),
            restAlertSchedulerProvider.overrideWithValue(
              FakeRestAlertScheduler(),
            ),
            restAlertStoreProvider.overrideWithValue(
              RestAlertStore(backing: InMemorySecureStore()),
            ),
          ],
          child: MaterialApp(
            theme: fsLightTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showRestSheet(
                    context,
                    countdown: RestCountdown(
                      reading: reading,
                      onAdjust: adjusts.add,
                      onSkip: () => skips.add(1),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (reading: reading, adjusts: adjusts, skips: skips);
    }

    testWidgets('shows the live time left', (tester) async {
      final h = await openRunning(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('rest.sheet.remaining'))).data,
        '1:00',
      );

      h.reading.value = (secondsLeft: 59, fractionLeft: 0.98);
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('rest.sheet.remaining'))).data,
        '0:59',
      );
    });

    testWidgets('±30s asks for 30 seconds more or less', (tester) async {
      final h = await openRunning(tester);

      await tester.tap(find.byKey(const Key('rest.plus')));
      await tester.tap(find.byKey(const Key('rest.minus')));

      expect(h.adjusts, [30, -30]);
    });

    testWidgets('Skip rest skips and closes the sheet', (tester) async {
      final h = await openRunning(tester);

      await tester.tap(find.byKey(const Key('rest.skip')));
      await tester.pumpAndSettle();

      expect(h.skips, [1]);
      expect(find.byKey(const Key('rest.sheet')), findsNothing);
    });

    testWidgets('closes itself once the rest is over', (tester) async {
      final h = await openRunning(tester);

      h.reading.value = null;
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rest.sheet')), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('a ring around the time, the numbers in the text colour', (
      tester,
    ) async {
      await openRunning(tester);

      expect(find.byType(FsRing), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('rest.sheet.remaining')))
            .style
            ?.color,
        FsTokens.light.text,
      );
    });

    // Mid-rest the sheet is about this rest; the defaults are one tap away.
    testWidgets('the defaults start folded, and open on a tap', (tester) async {
      await openRunning(tester);
      expect(find.byKey(const Key('rest.preset.90')), findsNothing);

      await tester.tap(find.byKey(const Key('rest.defaults')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rest.preset.90')), findsOneWidget);
    });

    testWidgets('speaks the time left and the buttons in words', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openRunning(tester);

      expect(find.bySemanticsLabel('1 minute of rest left'), findsOneWidget);
      expect(find.bySemanticsLabel('Add 30 seconds'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove 30 seconds'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('fits a 320 dp phone at large text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await openRunning(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
