import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_charts.dart' show FsRing;
import 'package:fitsync/features/home/presentation/widgets/readiness_card.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';

const _today = MorningCheckin(
  checkinId: 1,
  checkinDate: '2026-09-24',
  sleepQuality: 'good',
  muscleSoreness: 'none',
  energy: 'moderate',
  stress: 'low',
);

InjuryRiskEstimate _estimate(String level, {String date = '2026-09-24'}) =>
    InjuryRiskEstimate(
      riskLevel: level,
      trainingLoadScore: 10,
      checkinDate: date,
    );

Future<({List<String> taps})> _pump(
  WidgetTester tester, {
  InjuryRiskEstimate? estimate,
  MorningCheckin? todayCheckin,
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: ReadinessCard(
          estimate: estimate,
          todayCheckin: todayCheckin,
          onCheckIn: () => taps.add('checkin'),
          onTap: () => taps.add('card'),
        ),
      ),
    ),
  );
  return (taps: taps);
}

void main() {
  for (final (level, label) in [
    ('low', 'Low'),
    ('moderate', 'Moderate'),
    ('high', 'High'),
  ]) {
    testWidgets('shows a $level estimate in Recovery\'s ring', (tester) async {
      await _pump(tester, estimate: _estimate(level), todayCheckin: _today);

      expect(find.text('INJURY-RISK ESTIMATE'), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      final ring = tester.widget<FsRing>(find.byType(FsRing));
      expect(ring.value, _estimate(level).ringValue);
    });
  }

  testWidgets('with no estimate it asks for a check-in', (tester) async {
    await _pump(tester);
    expect(find.text('INJURY-RISK ESTIMATE'), findsOneWidget);
    // Recovery's own empty-state sentence, not a Home-specific rewrite.
    expect(
      find.text('Check in this morning to get your first estimate.'),
      findsOneWidget,
    );
    expect(find.byType(FsRing), findsNothing);
    expect(find.byKey(const Key('home.readiness.checkin')), findsOneWidget);
  });

  testWidgets('an estimate from an earlier day says which day', (tester) async {
    await _pump(tester, estimate: _estimate('low', date: '2026-09-20'));
    expect(find.textContaining('From '), findsOneWidget);
  });

  testWidgets(
    'an estimate with no check-in today does not claim to be today\'s',
    (tester) async {
      // No todayCheckin -- the estimate may be from an earlier day, so none
      // of the per-level "today" advice lines can be shown.
      await _pump(tester, estimate: _estimate('high', date: '2026-09-20'));

      expect(find.text('Check in for today\'s estimate'), findsOneWidget);
      expect(find.text('Consider a lighter day'), findsNothing);
      expect(find.text('Worth easing in today'), findsNothing);
      expect(find.text('Load and check-ins look manageable'), findsNothing);
    },
  );

  testWidgets('today\'s estimate does not repeat the date', (tester) async {
    await _pump(tester, estimate: _estimate('low'), todayCheckin: _today);
    expect(find.textContaining('From '), findsNothing);
  });

  testWidgets('the chip checks in and the card opens Recovery', (tester) async {
    final r = await _pump(
      tester,
      estimate: _estimate('low'),
      todayCheckin: _today,
    );

    await tester.tap(find.byKey(const Key('home.readiness.checkin')));
    // The ring, not the card's centre: the centre can land on the chip.
    await tester.tap(find.byType(FsRing));

    expect(r.taps, ['checkin', 'card']);
  });
}
