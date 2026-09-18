import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/sessions/domain/strength_series.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/widgets/progress_cards.dart';

const _series = StrengthSeries(
  exerciseId: 1,
  xAxis: 'date',
  points: [StrengthPoint(label: 'Sep 16', e1rmKg: 100)],
  options: [StrengthOption(exerciseId: 1, name: 'Bench press', sets: 3)],
);

void main() {
  testWidgets(
      'an lb user sees pounds on the estimated-1RM card, not the raw kilogram number',
      (tester) async {
    // e1rmKg is always kilograms from the server; the card used to hardcode
    // ' kg' on the headline regardless of the user's own weight_unit.
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: StrengthCard(series: _series, onPick: (_) {}, unit: WeightUnit.lb),
    )));

    expect(find.textContaining('220.5'), findsOneWidget, reason: '100 kg is 220.5 lb');
    expect(find.textContaining('100.0'), findsNothing,
        reason: 'the raw kg number must not be shown to an lb user');
    expect(find.textContaining(' kg'), findsNothing,
        reason: 'the unit must not be hardcoded to kg');

    final chart = tester.widget<FsLineChart>(find.byType(FsLineChart));
    expect(chart.points.single.y, closeTo(220.46, 0.01),
        reason: 'the chart y-values must convert too, not just the headline');
    expect(chart.minYBand, closeTo(22.05, 0.01),
        reason: 'the noise band must convert along with everything else');
  });

  testWidgets('a kg user sees the plain kilogram figure', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: StrengthCard(series: _series, onPick: (_) {}, unit: WeightUnit.kg),
    )));

    expect(find.textContaining('100 kg'), findsOneWidget);
  });

  group('volume by muscle', () {
    TrainingAnalytics analytics({
      List<MuscleVolume> muscles = const [],
      bool locked = false,
    }) => TrainingAnalytics(
          period: 'week',
          volume: const [],
          change: const VolumeChange(totalKg: 0, previousKg: 0, changePct: null),
          adherence: const Adherence(done: 1, target: 3, weeks: 1),
          muscles: muscles,
          musclesLocked: locked,
        );

    Future<void> pump(WidgetTester tester, TrainingAnalytics a) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: VolumeByMuscleCard(analytics: a)),
        ));

    testWidgets('a Pro user gets a bar per muscle, biggest first',
        (tester) async {
      await pump(tester, analytics(muscles: const [
        MuscleVolume(muscle: 'chest', volumeKg: 3000),
        MuscleVolume(muscle: 'lats', volumeKg: 1500),
      ]));

      expect(find.text('chest'), findsOneWidget);
      expect(find.text('lats'), findsOneWidget);
      final bars = tester.widgetList<FsBarRow>(find.byType(FsBarRow)).toList();
      expect(bars.length, 2);
      // Scaled against the largest, so the top bar is full and 1500 of 3000
      // is half of it.
      expect(bars[0].fraction, 1.0);
      expect(bars[1].fraction, 0.5);
    });

    // The card is Pro in every state, so the badge does not come and go --
    // it is what says the feature exists at all.
    testWidgets('the card names itself and its tier', (tester) async {
      await pump(tester, analytics(locked: true));

      // FsEyebrow uppercases, as every section heading on this screen does.
      expect(find.text('VOLUME BY MUSCLE'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(FsTag), matching: find.text('Pro')),
        findsOneWidget,
      );
    });

    // A blurred bar with a real number behind it is a hint, not a lock. The
    // server sends a free user nothing, and the card must not invent
    // anything that reads as data either.
    testWidgets('a locked card offers the upgrade and shows no muscle',
        (tester) async {
      await pump(tester, analytics(locked: true));

      expect(find.byKey(const Key('muscles.locked')), findsOneWidget);
      expect(find.textContaining('Unlock with Pro'), findsOneWidget);
      // Placeholder bars carry no label, so no muscle name can be read off
      // them and no figure is on screen.
      for (final bar in tester.widgetList<FsBarRow>(find.byType(FsBarRow))) {
        expect(bar.label, isEmpty);
      }
    });

    // Two different empty lists. A Pro user who trains only bodyweight has
    // logged plenty and has no volume -- telling them to upgrade would be
    // wrong, and an empty card reads as broken.
    testWidgets('a Pro user with nothing weighted is told why, not sold to',
        (tester) async {
      await pump(tester, analytics());

      expect(find.byKey(const Key('muscles.empty')), findsOneWidget);
      expect(find.textContaining('Unlock with Pro'), findsNothing);
      expect(find.textContaining(RegExp('bodyweight', caseSensitive: false)),
          findsOneWidget);
      expect(find.byType(FsBarRow), findsNothing);
    });
  });

}
