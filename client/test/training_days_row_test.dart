import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/plans/presentation/widgets/training_days_row.dart';

/// Pumps just the row, standing in for both callers -- the generator screen
/// and, from the next task, Settings -- neither of which this widget should
/// need to know about.
Future<void> _pump(
  WidgetTester tester, {
  List<int> selected = const [],
  int? busyWeekday,
  bool enabled = true,
  required ValueChanged<List<int>> onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: TrainingDaysRow(
          selected: selected,
          busyWeekday: busyWeekday,
          enabled: enabled,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

TrainingDayCell _cell(WidgetTester tester, int weekday) =>
    tester.widget<TrainingDayCell>(find.byKey(Key('weekday.$weekday')));

void main() {
  testWidgets(
    'seven cells are offered, keyed weekday.1 through weekday.7, and no eighth',
    (tester) async {
      await _pump(tester, onChanged: (_) {});

      for (var weekday = 1; weekday <= 7; weekday += 1) {
        expect(find.byKey(Key('weekday.$weekday')), findsOneWidget);
      }
      expect(find.byKey(const Key('weekday.8')), findsNothing);
    },
  );

  testWidgets(
    'a selected day renders selected and an unselected one does not',
    (tester) async {
      // The assertion whose absence means the row could render nothing ticked
      // and still pass: this proves the control actually shows what is stored,
      // not just that it can be tapped.
      await _pump(tester, selected: const [1, 3], onChanged: (_) {});

      expect(_cell(tester, 1).selected, isTrue);
      expect(_cell(tester, 3).selected, isTrue);
      expect(_cell(tester, 2).selected, isFalse);
      expect(_cell(tester, 7).selected, isFalse);
    },
  );

  testWidgets('the week reads Monday first: M T W T F S S', (tester) async {
    await _pump(tester, onChanged: (_) {});

    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    for (var weekday = 1; weekday <= 7; weekday += 1) {
      expect(
        _cell(tester, weekday).label,
        labels[weekday - 1],
        reason: 'weekday $weekday',
      );
    }
  });

  testWidgets(
    'ticking an unselected day emits the whole new set, ascending, with that day added',
    (tester) async {
      List<int>? emitted;
      await _pump(
        tester,
        selected: const [1, 3],
        onChanged: (next) => emitted = next,
      );

      await tester.tap(find.byKey(const Key('weekday.5')));
      await tester.pump();

      expect(emitted, [1, 3, 5]);
    },
  );

  testWidgets('ticking a selected day emits the set with it removed', (
    tester,
  ) async {
    List<int>? emitted;
    await _pump(
      tester,
      selected: const [1, 3, 5],
      onChanged: (next) => emitted = next,
    );

    await tester.tap(find.byKey(const Key('weekday.3')));
    await tester.pump();

    expect(emitted, [1, 5]);
  });

  testWidgets('a disabled row emits nothing, whichever cell is tapped', (
    tester,
  ) async {
    // The caller does not know what is stored. Since the endpoint replaces
    // the whole set, one tap against a row that is blank only because
    // nothing arrived would send a single day and wipe the rest.
    var calls = 0;
    await _pump(tester, enabled: false, onChanged: (_) => calls += 1);

    for (var weekday = 1; weekday <= 7; weekday += 1) {
      await tester.tap(find.byKey(Key('weekday.$weekday')));
      await tester.pump();
    }

    expect(calls, 0);
    for (var weekday = 1; weekday <= 7; weekday += 1) {
      expect(_cell(tester, weekday).onTap, isNull, reason: 'weekday $weekday');
    }
  });

  testWidgets('a disabled row reads as disabled rather than merely inert', (
    tester,
  ) async {
    // A control that looks live and silently swallows taps reads as broken.
    await _pump(tester, enabled: false, onChanged: (_) {});
    final off = tester.widget<Opacity>(find.byType(Opacity)).opacity;

    await _pump(tester, onChanged: (_) {});
    expect(find.byType(Opacity), findsNothing);
    expect(off, lessThan(1.0));
  });

  testWidgets(
    'a busy weekday shows a progress indicator instead of its label, and every cell refuses taps',
    (tester) async {
      var calls = 0;
      await _pump(
        tester,
        selected: const [1],
        busyWeekday: 3,
        onChanged: (_) => calls += 1,
      );

      // The busy cell itself: spinner in, label out.
      expect(
        find.descendant(
          of: find.byKey(const Key('weekday.3')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('weekday.3')),
          matching: find.text('W'),
        ),
        findsNothing,
      );
      expect(_cell(tester, 3).busy, isTrue);

      // Tapping the busy cell itself does nothing.
      await tester.tap(find.byKey(const Key('weekday.3')));
      await tester.pump();
      expect(calls, 0);

      // Nor does tapping some other, non-busy cell -- a second tap must not be
      // able to race the write already in flight.
      await tester.tap(find.byKey(const Key('weekday.1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('weekday.6')));
      await tester.pump();
      expect(calls, 0);
    },
  );

  group('screen readers', () {
    testWidgets('each day is a button named in full, with its selected state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, selected: const [1], onChanged: (_) {});

      expect(
        tester.getSemantics(find.byKey(const Key('weekday.1'))),
        matchesSemantics(
          label: 'Monday',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('weekday.2'))),
        matchesSemantics(
          label: 'Tuesday',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          isSelected: false,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Sunday'), findsOneWidget);
      // The bare letter is not announced alongside the full name.
      expect(find.bySemanticsLabel('M'), findsNothing);
      handle.dispose();
    });

    testWidgets('a screen-reader tap ticks the day', (tester) async {
      final handle = tester.ensureSemantics();
      List<int>? emitted;
      await _pump(tester, onChanged: (next) => emitted = next);

      tester.semantics.tap(find.semantics.byLabel('Wednesday'));
      expect(emitted, [3]);
      handle.dispose();
    });

    testWidgets('a disabled row announces its days as disabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, enabled: false, onChanged: (_) {});

      expect(
        tester.getSemantics(find.byKey(const Key('weekday.1'))),
        matchesSemantics(
          label: 'Monday',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: true,
          isSelected: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('each day offers a 48 dp tall tap target', (tester) async {
      await _pump(tester, onChanged: (_) {});

      expect(
        tester.getSize(find.byKey(const Key('weekday.1'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('fits a 320 dp screen at 2x text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: fsLightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: TrainingDaysRow(
              selected: const [1, 4],
              busyWeekday: 4,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
