import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart' show FsTag;
import 'package:fitsync/features/home/presentation/widgets/routine_card.dart';
import 'package:fitsync/features/routine/domain/routine.dart';

import 'helpers/a11y.dart' show contrast;

Habit _habit(int id, String title, {bool done = false, String? time}) => Habit(
  habitId: id,
  title: title,
  time: time,
  durationMin: null,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  done: done,
);

RoutineDay _day(List<Habit> habits, {RoutineWorkout? workout}) =>
    RoutineDay(date: '2026-09-24', habits: habits, workout: workout);

Future<List<String>> _pump(
  WidgetTester tester,
  RoutineDay day, {
  int streak = 0,
  bool dark = false,
  double textScale = 1.0,
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? fsDarkTheme() : fsLightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        // Scrollable, as Home is: at large text the card is taller than a
        // small phone.
        body: SingleChildScrollView(
          child: RoutineCard(
            day: day,
            onTap: () => taps.add('tap'),
            streak: streak,
            onOpenStreak: () => taps.add('streak'),
          ),
        ),
      ),
    ),
  );
  return taps;
}

/// The product of every [Opacity] above [finder]: what its paint is
/// actually multiplied by.
double _opacityOver(WidgetTester tester, Finder finder) => tester
    .widgetList<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)),
    )
    .fold(1.0, (a, o) => a * o.opacity);

void main() {
  testWidgets('several items show the heading, tag, first three titles and a '
      '"more" label', (tester) async {
    final day = _day([
      _habit(1, 'Habit 1', time: '06:00'),
      _habit(2, 'Habit 2', time: '07:00', done: true),
      _habit(3, 'Habit 3', time: '08:00'),
      _habit(4, 'Habit 4', time: '09:00', done: true),
      _habit(5, 'Habit 5', time: '10:00'),
    ]);
    await _pump(tester, day);

    expect(find.text("Today's routine"), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);
    // Only the first three, in screen order.
    expect(find.text('Habit 1'), findsOneWidget);
    expect(find.text('Habit 2'), findsOneWidget);
    expect(find.text('Habit 3'), findsOneWidget);
    expect(find.text('Habit 4'), findsNothing);
    expect(find.text('Habit 5'), findsNothing);
    expect(find.byKey(const Key('home.routine.more')), findsOneWidget);
    expect(find.text('+2 more'), findsOneWidget);
  });

  testWidgets('three or fewer entries show no "more" label', (tester) async {
    final day = _day([
      _habit(1, 'Habit 1', time: '06:00'),
      _habit(2, 'Habit 2', time: '07:00'),
      _habit(3, 'Habit 3', time: '08:00'),
    ]);
    await _pump(tester, day);

    expect(find.byKey(const Key('home.routine.more')), findsNothing);
  });

  testWidgets('a ticked item shows its title struck through', (tester) async {
    final day = _day([
      _habit(1, 'Done habit', time: '06:00', done: true),
      _habit(2, 'Open habit', time: '07:00'),
    ]);
    await _pump(tester, day);

    final doneText = tester.widget<Text>(find.text('Done habit'));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
    final openText = tester.widget<Text>(find.text('Open habit'));
    expect(openText.style?.decoration, TextDecoration.none);
  });

  testWidgets('no habits and no workout shows the build-routine prompt', (
    tester,
  ) async {
    final day = _day(const []);
    await _pump(tester, day);

    expect(find.text("Nothing on today's routine ›"), findsOneWidget);
    expect(find.byType(FsTag), findsNothing);
  });

  testWidgets('tapping the card, including its tick boxes, calls onTap', (
    tester,
  ) async {
    final day = _day([_habit(1, 'Habit 1', time: '06:00', done: true)]);
    final taps = await _pump(tester, day);

    await tester.tap(find.byKey(const Key('home.routine')));
    expect(taps, ['tap']);

    taps.clear();
    // The mini tick box carries no gesture handling of its own; tapping it
    // must still land on the card-wide target rather than doing nothing.
    await tester.tap(find.byIcon(Icons.check));
    expect(taps, ['tap']);
  });

  testWidgets('a streak of one day or more shows as a tag', (tester) async {
    await _pump(tester, _day([_habit(1, 'Walk')]), streak: 1);
    expect(find.text('1-day streak'), findsOneWidget);

    await _pump(tester, _day([_habit(1, 'Walk')]), streak: 12);
    expect(find.text('12-day streak'), findsOneWidget);
  });

  testWidgets('no streak, no tag', (tester) async {
    await _pump(tester, _day([_habit(1, 'Walk')]));

    expect(find.byKey(const Key('home.routine.streak')), findsNothing);
    expect(find.textContaining('streak'), findsNothing);
  });

  testWidgets('tapping the tag opens the streak, not the routine', (
    tester,
  ) async {
    final taps = await _pump(tester, _day([_habit(1, 'Walk')]), streak: 3);

    await tester.tap(find.byKey(const Key('home.routine.streak')));
    await tester.pump();

    expect(taps, ['streak']);
  });

  for (final dark in [false, true]) {
    testWidgets('a done title reads at 4.5:1 on the card '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(
        tester,
        _day([_habit(1, 'Done habit', time: '06:00', done: true)]),
        dark: dark,
      );
      final t = dark ? FsTokens.dark : FsTokens.light;
      final title = find.text('Done habit');
      final color = tester.widget<Text>(title).style!.color!;
      final shown = color.withValues(
        alpha: color.a * _opacityOver(tester, title),
      );

      expect(contrast(shown, t.surface), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('a screen reader hears whether each item is done', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      _day([
        _habit(1, 'Stretch', time: '06:00', done: true),
        _habit(2, 'Walk', time: '07:00'),
      ]),
    );

    final label = tester.getSemantics(find.byKey(const Key('home.routine')));
    expect(label.label, contains('Stretch, done'));
    expect(label.label, contains('Walk, not done'));
    handle.dispose();
  });

  testWidgets('the streak link is a named 48 dp button', (tester) async {
    final handle = tester.ensureSemantics();
    final taps = await _pump(tester, _day([_habit(1, 'Walk')]), streak: 3);

    final link = find.byKey(const Key('home.routine.streak'));
    expect(
      tester.getSemantics(link),
      matchesSemantics(
        label: '3-day streak',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    // A thumb landing just under the drawn chip still means the streak, not
    // the card's own "open the routine".
    final chip = tester.getRect(link);
    await tester.tapAt(Offset(chip.center.dx, chip.bottom + 6));
    await tester.pump();
    expect(taps, ['streak']);
    handle.dispose();
  });

  for (final scale in [1.3, 1.5, 2.0]) {
    testWidgets('at ${scale}x text, with the chip under the title, its reach '
        'stays off the title and the tag', (tester) async {
      // Once the chip wraps under the title (and the tag under the chip),
      // a 48 dp band reaching up or down would take taps meant for the card.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final taps = await _pump(
        tester,
        _day([_habit(1, 'Walk', time: '06:00')]),
        streak: 3,
        textScale: scale,
      );

      final title = tester.getRect(find.text("Today's routine"));
      final tag = tester.getRect(find.byType(FsTag));
      final chip = tester.getRect(find.byKey(const Key('home.routine.streak')));
      expect(chip.top, greaterThan(title.bottom), reason: 'chip wrapped');

      for (final point in [
        title.center,
        title.bottomLeft + const Offset(4, -1),
        tag.center,
        tag.topCenter + const Offset(0, 1),
      ]) {
        taps.clear();
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 500));
        expect(taps, ['tap'], reason: '$point');
      }
      // While the chip itself still opens the streak.
      taps.clear();
      await tester.tap(find.byKey(const Key('home.routine.streak')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(taps, ['streak']);
    });
  }

  for (final size in [const Size(360, 640), const Size(320, 568)]) {
    testWidgets('at 2x text on ${size.width.toInt()} dp the header neither '
        'overflows nor breaks the title mid-word', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        _day([
          for (var i = 1; i <= 15; i++)
            _habit(i, 'Habit $i', time: '06:00', done: i <= 12),
        ]),
        streak: 125,
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      final title = tester.renderObject<RenderParagraph>(
        find.text("Today's routine"),
      );
      // Narrower than its longest word, a paragraph breaks inside it.
      expect(
        title.size.width,
        greaterThanOrEqualTo(title.getMinIntrinsicWidth(double.infinity)),
      );
      expect(find.text('125-day streak'), findsOneWidget);
      expect(find.text('12 / 15'), findsOneWidget);
    });
  }

  // The Routine screen's tick box for the same item is outlined in
  // t.control; Home's kept the 1.4:1 hairline.
  for (final dark in [false, true]) {
    testWidgets('an open tick box is outlined at 3:1, as on the Routine '
        'screen (${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(tester, _day([_habit(1, 'Stretch')]), dark: dark);
      final t = dark ? FsTokens.dark : FsTokens.light;
      final box = tester.widget<Container>(
        find.descendant(
          of: find
              .ancestor(of: find.text('Stretch'), matching: find.byType(Row))
              .first,
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxWidth == 20,
          ),
        ),
      );
      final border = (box.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color, t.control);
      expect(contrast(border.top.color, t.surface), greaterThanOrEqualTo(3));
    });
  }
}
