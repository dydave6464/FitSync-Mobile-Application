import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/widgets/rest_sheet.dart';

import 'helpers/fake_training_settings.dart';

/// Opens the sheet the way the logger's menu does: no countdown, just the
/// default. A countdown-less sheet has nothing ticking, so it can settle.
Future<FakeTrainingSettings> _open(
  WidgetTester tester, {
  int stored = 90,
}) async {
  final settings = FakeTrainingSettings(stored);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainingSettingsRepositoryProvider.overrideWithValue(settings),
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
}
