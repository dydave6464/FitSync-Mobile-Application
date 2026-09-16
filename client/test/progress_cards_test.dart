import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';
import 'package:fitsync/features/sessions/domain/strength_series.dart';
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
}
