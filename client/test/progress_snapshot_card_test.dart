import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_charts.dart' show FsBarChart;
import 'package:fitsync/features/home/presentation/widgets/progress_snapshot_card.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';

TrainingAnalytics _analytics({int? changePct = 12, int done = 5}) =>
    TrainingAnalytics(
      period: 'month',
      volume: const [
        VolumeBucket(label: 'W1', volumeKg: 1200),
        VolumeBucket(label: 'W2', volumeKg: 1800),
        VolumeBucket(label: 'W3', volumeKg: 1500),
        VolumeBucket(label: 'W4', volumeKg: 2100),
      ],
      change: VolumeChange(
        totalKg: 6600,
        previousKg: 5900,
        changePct: changePct,
      ),
      adherence: Adherence(done: done, target: 12, weeks: 4),
      muscles: const [],
    );

Future<List<String>> _pump(
  WidgetTester tester, {
  TrainingSummary summary = const TrainingSummary(
    sessionCount: 4,
    setCount: 40,
    totalVolumeKg: 6600,
    newPrCount: 3,
  ),
  TrainingAnalytics? analytics,
  WeightUnit unit = WeightUnit.kg,
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: ProgressSnapshotCard(
          summary: summary,
          analytics: analytics ?? _analytics(),
          unit: unit,
          onTap: () => taps.add('card'),
        ),
      ),
    ),
  );
  return taps;
}

/// The words under [key], whatever wraps them.
String _textOf(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .data!;

void main() {
  testWidgets('shows sessions, new PRs and volume change', (tester) async {
    await _pump(tester);

    expect(find.text('Your progress'), findsOneWidget);
    expect(find.textContaining('Past month'), findsOneWidget);
    expect(_textOf(tester, 'home.progress.sessions'), '5');
    expect(_textOf(tester, 'home.progress.prs'), '3');
    expect(_textOf(tester, 'home.progress.change'), '+12%');
    expect(find.byType(FsBarChart), findsOneWidget);
  });

  testWidgets('a rise in volume reads in the text green, not the fill', (
    tester,
  ) async {
    // The brand green on white is 2.87:1, too faint for a figure.
    await _pump(tester);

    final change = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('home.progress.change')),
        matching: find.byType(Text),
      ),
    );
    expect(change.style?.color, FsTokens.light.accentText);
  });

  // Home's own copy of the volume shape: bars, like the Progress tab's, in
  // the user's unit. It plotted kilograms for a pound user before.
  // 2100 kg is 4629.7... lb, derived by hand.
  testWidgets('the volume shape is bars in the user\'s unit', (tester) async {
    await _pump(tester, unit: WeightUnit.lb);

    final chart = tester.widget<FsBarChart>(find.byType(FsBarChart));
    expect(chart.bars.last.value, closeTo(4629.7, 0.1));
  });

  // Unnamed bars left "which week was that?" unanswered; each now carries the
  // date its span ends under it, as on the Progress tab.
  testWidgets('each bar is named by the date its span ends', (tester) async {
    await _pump(tester);

    final chart = tester.widget<FsBarChart>(find.byType(FsBarChart));
    expect(chart.bars, hasLength(4));
    for (final bar in chart.bars) {
      expect(bar.label, isNotEmpty);
      expect(find.text(bar.label), findsOneWidget, reason: bar.label);
    }
  });

  testWidgets('a tap on the bars still opens Progress', (tester) async {
    // The chart claims no touches here: the whole card is the way in.
    final taps = await _pump(tester);

    await tester.tap(find.byType(FsBarChart));
    await tester.pumpAndSettle();

    expect(taps, ['card']);
  });

  testWidgets('no earlier window to compare shows a dash, not 0%', (
    tester,
  ) async {
    await _pump(tester, analytics: _analytics(changePct: null));
    expect(_textOf(tester, 'home.progress.change'), '—');
  });

  testWidgets('nothing trained in the month says so', (tester) async {
    // Keyed on the analytics done count, not the summary: a summary that is
    // not itself empty must still show the empty state when adherence.done
    // is 0, since that is the number the card (and Progress) now agree on.
    await _pump(
      tester,
      summary: const TrainingSummary(
        sessionCount: 4,
        setCount: 40,
        totalVolumeKg: 6600,
      ),
      analytics: _analytics(done: 0),
    );
    expect(
      find.text('Finish a workout to see your progress here.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home.progress.sessions')), findsNothing);
  });

  testWidgets('tapping it opens Progress', (tester) async {
    final taps = await _pump(tester);
    await tester.tap(find.byKey(const Key('home.progress')));
    expect(taps, ['card']);
  });

  // Reported on a 320 dp phone at 2x text: "progre / ss", "session / s",
  // "+12 / %" and "volum / e".
  testWidgets('at 2x text on a small phone no word breaks', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester);
    expect(tester.takeException(), isNull);

    /// How many lines [part] of [words] is drawn across.
    int lines(String words, [String? part]) {
      final start = part == null ? 0 : words.indexOf(part);
      return tester
          .renderObject<RenderParagraph>(find.text(words))
          .getBoxesForSelection(
            TextSelection(
              baseOffset: start,
              extentOffset: start + (part ?? words).length,
            ),
          )
          .map((box) => box.top)
          .toSet()
          .length;
    }

    // The title may wrap between its words, never inside one.
    expect(lines('Your progress', 'progress'), 1);
    for (final words in ['5', '3', '+12%', 'sessions', 'new PRs', 'volume']) {
      expect(lines(words), 1, reason: words);
    }
    // No room beside the title, so "Past month" goes under it.
    expect(
      tester.getTopLeft(find.text('Past month')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('Your progress')).dy),
    );
  });

  testWidgets('the words under the figures are a readable size', (
    tester,
  ) async {
    await _pump(tester);
    for (final label in ['sessions', 'new PRs', 'volume']) {
      expect(
        tester.widget<Text>(find.text(label)).style!.fontSize,
        greaterThanOrEqualTo(12),
        reason: label,
      );
    }
  });

  testWidgets('with room, "Past month" sits at the far right of the title', (
    tester,
  ) async {
    await _pump(tester);
    final card = tester.getRect(find.byKey(const Key('home.progress')));
    final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
    final title = tester.getRect(find.text('Your progress'));
    // Inside the card's 16 dp padding, on the title's line.
    expect(chevron.right, closeTo(card.right - 16, 1));
    expect(chevron.center.dy, closeTo(title.center.dy, 4));
  });
}
