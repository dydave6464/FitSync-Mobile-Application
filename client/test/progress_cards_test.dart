import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_charts.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/widgets/progress_cards.dart';

void main() {
  group('training volume', () {
    TrainingAnalytics withVolume(double totalKg, {int? changePct}) =>
        TrainingAnalytics(
          period: 'week',
          volume: const [
            VolumeBucket(label: '-1d', volumeKg: 100),
            VolumeBucket(label: 'today', volumeKg: 200),
          ],
          change: VolumeChange(
            totalKg: totalKg, previousKg: 0, changePct: changePct,
          ),
          adherence: const Adherence(done: 1, target: 3, weeks: 1),
          muscles: const [],
        );

    // The card used to show a percentage and nothing else, on the reasoning
    // that nobody has intuition for 48,200 kg. True -- but that is an argument
    // about how to write the number, not about hiding it.
    testWidgets('the card leads with the total lifted', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: VolumeTrendCard(analytics: withVolume(48200), unit: WeightUnit.kg),
      )));

      expect(find.text('48.2k'), findsOneWidget);
      expect(find.text('kg lifted'), findsOneWidget);
    });

    // 1550 kg is 3417.2... lb. Hand-derived, not run through the same
    // conversion the card uses.
    testWidgets('the total converts for an lb user', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: VolumeTrendCard(analytics: withVolume(1550), unit: WeightUnit.lb),
      )));

      expect(find.text('3.4k'), findsOneWidget);
      expect(find.text('lb lifted'), findsOneWidget);
      expect(find.text('1.6k'), findsNothing, reason: 'that is the kg figure');
    });

    // The state every new account is in, and the one that drove this change:
    // with no previous window there is no percentage, and the card used to
    // render a shape with no number on it at all.
    testWidgets('a first window still shows its total', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: VolumeTrendCard(analytics: withVolume(1550), unit: WeightUnit.kg),
      )));

      expect(find.text('1.6k'), findsOneWidget);
      expect(find.byType(FsTag), findsNothing, reason: 'nothing to compare to');
    });

    testWidgets('a later window shows the change beside the total',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: VolumeTrendCard(
          analytics: withVolume(48200, changePct: 12), unit: WeightUnit.kg,
        ),
      )));

      expect(find.text('48.2k'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(FsTag), matching: find.text('+12%')),
        findsOneWidget,
      );
    });
  });


  group('the sessions and sets pair', () {
    // The prototype puts these side by side under the volume chart, where
    // adherence used to be a full-width hero above it. Half a row each, so
    // neither carries the caption the hero had room for -- the segment above
    // already says which window is on screen.
    testWidgets('sessions shows the ratio and how far through it is',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: AdherenceCard(adherence: Adherence(done: 2, target: 3, weeks: 1)),
      )));

      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(2 / 3, 0.001));
    });

    // A user with no active plan has nothing to be two-thirds of. The bar is
    // what would be meaningless, not the count.
    testWidgets('sessions without a target shows the count and no bar',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: AdherenceCard(adherence: Adherence(done: 3, target: null, weeks: 1)),
      )));

      expect(find.text('3'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('sets shows what was logged in the window', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: SetsCard(setCount: 18),
      )));

      expect(find.text('SETS'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
    });
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
