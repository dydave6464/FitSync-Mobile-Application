import 'package:flutter/material.dart';
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

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

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

  // Home's own copy of the volume shape: bars, like the Progress tab's, in
  // the user's unit. It plotted kilograms for a pound user before. A preview
  // the whole card opens from, so it carries no axis words of its own.
  // 2100 kg is 4629.7... lb, derived by hand.
  testWidgets('the volume shape is bars in the user\'s unit, unlabelled', (
    tester,
  ) async {
    await _pump(tester, unit: WeightUnit.lb);

    final chart = tester.widget<FsBarChart>(find.byType(FsBarChart));
    expect(chart.bars.last.value, closeTo(4629.7, 0.1));
    expect(chart.showLabels, isFalse);
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
}
