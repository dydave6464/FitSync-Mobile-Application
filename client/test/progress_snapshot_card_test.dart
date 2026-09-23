import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_charts.dart' show FsLineChart;
import 'package:fitsync/features/home/presentation/widgets/progress_snapshot_card.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';

TrainingAnalytics _analytics({int? changePct = 12}) => TrainingAnalytics(
  period: 'month',
  volume: const [
    VolumeBucket(label: 'W1', volumeKg: 1200),
    VolumeBucket(label: 'W2', volumeKg: 1800),
    VolumeBucket(label: 'W3', volumeKg: 1500),
    VolumeBucket(label: 'W4', volumeKg: 2100),
  ],
  change: VolumeChange(totalKg: 6600, previousKg: 5900, changePct: changePct),
  adherence: const Adherence(done: 4, target: 12, weeks: 4),
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
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: ProgressSnapshotCard(
          summary: summary,
          analytics: analytics ?? _analytics(),
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
    expect(find.textContaining('Last 30 days'), findsOneWidget);
    expect(_textOf(tester, 'home.progress.sessions'), '4');
    expect(_textOf(tester, 'home.progress.prs'), '3');
    expect(_textOf(tester, 'home.progress.change'), '+12%');
    expect(find.byType(FsLineChart), findsOneWidget);
  });

  testWidgets('no earlier window to compare shows a dash, not 0%', (
    tester,
  ) async {
    await _pump(tester, analytics: _analytics(changePct: null));
    expect(_textOf(tester, 'home.progress.change'), '—');
  });

  testWidgets('nothing trained in 30 days says so', (tester) async {
    await _pump(
      tester,
      summary: const TrainingSummary(
        sessionCount: 0,
        setCount: 0,
        totalVolumeKg: 0,
      ),
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
