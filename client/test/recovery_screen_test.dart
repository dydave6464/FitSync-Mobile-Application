import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_charts.dart' show FsRing, FsBarChart;
import 'package:fitsync/features/profile/presentation/providers.dart'
    show weightUnitProvider;
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart';
import 'package:fitsync/features/recovery/presentation/recovery_screen.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart'
    show VolumeBucket;
import 'package:fitsync/features/sessions/domain/volume_labels.dart';

const _estimate = InjuryRiskEstimate(
  riskLevel: 'moderate',
  trainingLoadScore: 42.5,
  checkinDate: '2026-09-18',
);

const _checkin = MorningCheckin(
  checkinId: 1,
  checkinDate: '2026-09-20',
  sleepQuality: 'good',
  muscleSoreness: 'mild',
  energy: 'moderate',
  stress: 'low',
);

/// Today's check-in and an estimate from it, with drivers.
const _todayCheckin = MorningCheckin(
  checkinId: 2,
  checkinDate: '2026-10-18',
  sleepQuality: 'poor',
  muscleSoreness: 'mild',
  energy: 'moderate',
  stress: 'low',
);

InjuryRiskEstimate _todays({
  String level = 'moderate',
  double? score = 47.25,
  String? source = 'model',
  List<RiskDriver>? drivers = const [
    RiskDriver(key: 'sleep', value: 'poor'),
    RiskDriver(key: 'load', value: 35.0),
  ],
}) => InjuryRiskEstimate(
  riskLevel: level,
  trainingLoadScore: score,
  checkinDate: '2026-10-18',
  source: source,
  drivers: drivers,
);

RecoveryOverview _withToday(
  InjuryRiskEstimate estimate, {
  List<VolumeBucket> load = const [],
}) => RecoveryOverview(
  todayCheckin: _todayCheckin,
  latestEstimate: estimate,
  load: load,
);

final _tokens = fsLightTheme().extension<FsTokens>()!;

FsRing _ring(WidgetTester tester) => tester.widget<FsRing>(find.byType(FsRing));

Future<void> _pump(
  WidgetTester tester,
  RecoveryOverview overview, {
  WeightUnit unit = WeightUnit.kg,
}) async {
  await tester.pumpWidget(
    // A fresh scope each pump, so a test that pumps twice reads its new
    // overview rather than the first one's cached result.
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        recoveryOverviewProvider.overrideWith((ref) async => overview),
        weightUnitProvider.overrideWithValue(unit),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: const Scaffold(body: RecoveryScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an account that has never checked in is invited to', (
    tester,
  ) async {
    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: null,
        latestEstimate: null,
        load: [],
      ),
    );

    expect(find.byKey(const Key('recovery.empty')), findsOneWidget);
    expect(find.byKey(const Key('recovery.checkin')), findsOneWidget);
    // Nothing to be moderate about yet.
    expect(find.text('Moderate'), findsNothing);
  });

  testWidgets('an older estimate is shown with the day it came from', (
    tester,
  ) async {
    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: null,
        latestEstimate: _estimate,
        load: [],
      ),
    );

    expect(find.text('Moderate'), findsOneWidget);
    expect(find.textContaining('September 18'), findsOneWidget);
    // Not today's, so the invitation stands.
    expect(find.byKey(const Key('recovery.checkin')), findsOneWidget);
  });

  testWidgets(
    'a check-in today without its estimate says so and dates the older one',
    (tester) async {
      // _checkin is today's (the 20th); the latest estimate is the 18th's, as
      // when today's was saved while the ML service was down.
      await _pump(
        tester,
        const RecoveryOverview(
          todayCheckin: _checkin,
          latestEstimate: _estimate,
          load: [],
        ),
      );

      expect(find.text('Today\'s estimate is unavailable'), findsOneWidget);
      expect(find.textContaining('September 18'), findsOneWidget);
      // The same way forward as with no older estimate at all.
      expect(find.text('Tap Update below to try again.'), findsOneWidget);
      expect(find.byKey(const Key('recovery.update')), findsOneWidget);
    },
  );

  testWidgets('an older estimate with no check-in today offers no retry', (
    tester,
  ) async {
    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: null,
        latestEstimate: _estimate,
        load: [],
      ),
    );
    expect(find.textContaining('try again'), findsNothing);
  });

  testWidgets(
    'keeps the injury-risk estimate as its headline, readiness beside it',
    (tester) async {
      await _pump(
        tester,
        const RecoveryOverview(
          todayCheckin: null,
          latestEstimate: _estimate,
          load: [],
        ),
      );

      expect(find.text('INJURY-RISK ESTIMATE'), findsOneWidget);
      expect(find.text('Moderate'), findsOneWidget);
      // 100 - 42.5, rounded up.
      expect(find.text('Readiness 58'), findsOneWidget);
      // The caption explaining Readiness was noise on the tab itself; the
      // How-to-read sheet carries it.
      expect(find.textContaining('the other way up'), findsNothing);
    },
  );

  testWidgets('an estimate saved without a score shows no readiness number', (
    tester,
  ) async {
    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: null,
        latestEstimate: InjuryRiskEstimate(
          riskLevel: 'low',
          trainingLoadScore: null,
          checkinDate: '2026-09-18',
        ),
        load: [],
      ),
    );

    expect(find.text('Low'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Readiness \d')), findsNothing);
  });

  testWidgets('last trained lists each group in the order the server sent', (
    tester,
  ) async {
    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: null,
        latestEstimate: _estimate,
        load: [],
        muscles: [
          MuscleRecency(group: 'chest', lastTrained: null, daysAgo: null),
          MuscleRecency(group: 'legs', lastTrained: '2026-09-15', daysAgo: 5),
          MuscleRecency(group: 'arms', lastTrained: '2026-09-19', daysAgo: 1),
          MuscleRecency(group: 'core', lastTrained: '2026-09-20', daysAgo: 0),
        ],
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('recovery.muscles')),
      200,
    );
    await tester.pumpAndSettle();

    final names = ['Chest', 'Legs', 'Arms', 'Core'];
    final ys = [for (final n in names) tester.getTopLeft(find.text(n)).dy];
    expect(ys, [...ys]..sort(), reason: 'rows keep the server order');
    expect(find.text('Not trained yet'), findsOneWidget);
    expect(find.text('5 days ago'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('with no training yet the card says how to fill it', (
    tester,
  ) async {
    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: null,
        latestEstimate: null,
        load: [],
        muscles: [
          MuscleRecency(group: 'chest', lastTrained: null, daysAgo: null),
          MuscleRecency(group: 'back', lastTrained: null, daysAgo: null),
        ],
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('recovery.muscles')),
      200,
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Finish a workout to see when each muscle group was last trained.',
      ),
      findsOneWidget,
    );
    expect(find.text('Not trained yet'), findsNothing);
  });

  testWidgets('a check-in already made today is not asked for again', (
    tester,
  ) async {
    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: _checkin,
        latestEstimate: _estimate,
        load: [],
      ),
    );

    expect(find.byKey(const Key('recovery.checkin')), findsNothing);
    expect(find.byKey(const Key('recovery.update')), findsOneWidget);
  });

  testWidgets('the load row and the chart below it agree', (tester) async {
    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: _checkin,
        latestEstimate: _estimate,
        load: [],
      ),
    );

    // One window, one number. The index is 7 days of volume against a 3-week
    // baseline; 14 days was the old check-in window and was never a
    // training-load figure -- least of all on the same screen as a card
    // titled "7-day training load".
    expect(find.text('Training load · 7 days'), findsOneWidget);
    expect(find.textContaining('14 days'), findsNothing);
  });

  testWidgets('carries the one-line disclaimer, with an estimate or without', (
    tester,
  ) async {
    // Removed on 2026-09-24, and brought back as one line on 2026-10-18 when
    // the card began to explain the estimate.
    const disclaimer =
        'An estimate from your check-ins, training load and past injuries '
        '— not a medical diagnosis.';
    await _pump(tester, _withToday(_todays()));
    expect(find.text(disclaimer), findsOneWidget);

    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: null,
        latestEstimate: null,
        load: [],
      ),
    );
    expect(find.text(disclaimer), findsOneWidget);
  });

  group('explaining the estimate', () {
    testWidgets('the line under the ring says what each level means', (
      tester,
    ) async {
      await _pump(tester, _withToday(_todays(level: 'low', score: 20)));
      expect(find.text('Train as planned.'), findsOneWidget);

      await _pump(tester, _withToday(_todays(level: 'moderate', score: 47)));
      expect(find.text('Train, but go a little easier.'), findsOneWidget);

      await _pump(tester, _withToday(_todays(level: 'high', score: 75)));
      expect(
        find.text('Consider a lighter day: mobility or rest.'),
        findsOneWidget,
      );
    });

    testWidgets('the ring fills to the score in the level colour', (
      tester,
    ) async {
      await _pump(tester, _withToday(_todays(level: 'low', score: 35)));
      expect(_ring(tester).value, closeTo(0.35, 1e-9));
      expect(_ring(tester).color, _tokens.accent);

      await _pump(tester, _withToday(_todays(level: 'moderate', score: 47.25)));
      expect(_ring(tester).value, closeTo(0.4725, 1e-9));
      expect(_ring(tester).color, _tokens.amber);
    });

    testWidgets('an older estimate is greyed and gives no advice for today', (
      tester,
    ) async {
      await _pump(
        tester,
        const RecoveryOverview(
          todayCheckin: null,
          latestEstimate: _estimate,
          load: [],
        ),
      );

      expect(_ring(tester).color, _tokens.text3);
      expect(find.text('Train, but go a little easier.'), findsNothing);
      expect(find.text("Check in for today's estimate"), findsOneWidget);
    });

    testWidgets('the "Why" line names what raised it', (tester) async {
      await _pump(tester, _withToday(_todays()));
      expect(
        find.text(
          'Why: recent check-ins show poor sleep, and this week is 35% above '
          'your usual.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an earlier day\'s estimate shows no "Why" line', (
      tester,
    ) async {
      // Like the advice line, the reasons held for the day they were worked
      // out, so a greyed estimate shows neither -- whether or not today's
      // check-in is in.
      final earlier = InjuryRiskEstimate(
        riskLevel: 'moderate',
        trainingLoadScore: 47.25,
        checkinDate: '2026-09-18',
        source: 'model',
        drivers: const [RiskDriver(key: 'sleep', value: 'poor')],
      );
      for (final checkin in [null, _checkin]) {
        await _pump(
          tester,
          RecoveryOverview(
            todayCheckin: checkin,
            latestEstimate: earlier,
            load: const [],
          ),
        );
        expect(_ring(tester).color, _tokens.text3);
        expect(find.byKey(const Key('recovery.why')), findsNothing);
        expect(find.textContaining('recent check-ins'), findsNothing);
        expect(find.text('Train, but go a little easier.'), findsNothing);
      }
    });

    testWidgets('with no drivers it says nothing stands out', (tester) async {
      await _pump(tester, _withToday(_todays(drivers: const [])));
      expect(
        find.text('Nothing in your check-ins, training or history stands out.'),
        findsOneWidget,
      );
    });

    testWidgets('an estimate from before drivers has no "Why" line', (
      tester,
    ) async {
      await _pump(tester, _withToday(_todays(source: null, drivers: null)));
      expect(find.byKey(const Key('recovery.why')), findsNothing);
      expect(find.textContaining('stands out'), findsNothing);

      // As GET actually sends such a row: no source, but an empty list.
      await _pump(
        tester,
        _withToday(
          InjuryRiskEstimate.fromJson({
            'riskLevel': 'moderate',
            'trainingLoadScore': 47.25,
            'checkinDate': '2026-10-18',
            'source': null,
            'loadPct': null,
            'drivers': <Object>[],
          }),
        ),
      );
      expect(find.byKey(const Key('recovery.why')), findsNothing);
      expect(find.textContaining('stands out'), findsNothing);
    });

    testWidgets('the ring and readiness are named for a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _withToday(_todays(level: 'moderate', score: 47.25)));

      expect(find.bySemanticsLabel('Injury risk: Moderate'), findsOneWidget);
      // Home reads readiness out of 100; Recovery says it the same way.
      expect(find.bySemanticsLabel('Readiness 53 out of 100'), findsOneWidget);
      // The ring's word is not read again on its own.
      expect(find.bySemanticsLabel('Moderate'), findsNothing);
      semantics.dispose();
    });

    testWidgets('the ⓘ control is named, big enough and opens the guide', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _withToday(_todays()));

      final info = find.byKey(const Key('recovery.howToRead'));
      expect(info, findsOneWidget);
      final size = tester.getSize(info);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      // Named for a screen reader: the tooltip is what TalkBack and
      // VoiceOver announce for an icon button.
      final node = tester.getSemantics(info);
      expect('${node.label} ${node.tooltip}', contains('How to read this'));
      expect(node.flagsCollection.isButton, isTrue);
      semantics.dispose();

      await tester.tap(info);
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('howto.sheet'));
      expect(sheet, findsOneWidget);
      for (final level in ['low', 'moderate', 'high']) {
        expect(find.byKey(Key('howto.level.$level')), findsOneWidget);
      }
      expect(find.text('Readiness 61–100'), findsOneWidget);
      expect(find.text('Readiness 31–60'), findsOneWidget);
      expect(find.text('Readiness 0–30'), findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('Train as planned.')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('howto.disclaimer')),
        200,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.textContaining('simulated data'),
        ),
        findsOneWidget,
      );
      // Both score the inputs, the higher counts, and today the rules set
      // the level on almost every day. The rules come first: the model is not the
      // main engine.
      final how = tester
          .widgetList<Text>(
            find.descendant(of: sheet, matching: find.byType(Text)),
          )
          .map((t) => t.data ?? '')
          .join(' ');
      expect(how, contains('the higher score counts'));
      expect(how, contains('the rules set the level on almost every day'));
      expect(how, contains('the model can only raise it'));
      expect(how, contains('retrained on real check-in outcomes'));
      final worked = how.substring(how.indexOf("How it's worked out"));
      expect(worked, contains('safety rules'));
      expect(
        worked.indexOf('safety rules'),
        lessThan(worked.indexOf('model')),
        reason: 'the rules are introduced before the model',
      );
      expect(how, isNot(contains('gives the estimate')));
      // The usual week is averaged over the weeks a user has trained in, up
      // to three, so a newcomer's early weeks no longer read high.
      expect(
        find.descendant(
          of: sheet,
          matching: find.textContaining(
            'the average of the weeks you have trained before this one',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('can read higher than it really is'),
        findsNothing,
      );
      expect(find.textContaining('a few weeks of workouts'), findsNothing);
      expect(
        find.descendant(
          of: sheet,
          matching: find.textContaining('not a medical diagnosis'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the guide can be opened before the first estimate', (
      tester,
    ) async {
      await _pump(
        tester,
        const RecoveryOverview(
          todayCheckin: null,
          latestEstimate: null,
          load: [],
        ),
      );
      expect(find.byKey(const Key('recovery.howToRead')), findsOneWidget);
    });
  });

  group('empty states', () {
    testWidgets('no check-in yet invites one', (tester) async {
      await _pump(
        tester,
        const RecoveryOverview(
          todayCheckin: null,
          latestEstimate: null,
          load: [],
        ),
      );
      expect(
        find.text('Check in this morning to get your first estimate.'),
        findsOneWidget,
      );
    });

    testWidgets('a check-in with no estimate back says so honestly', (
      tester,
    ) async {
      await _pump(
        tester,
        const RecoveryOverview(
          todayCheckin: _checkin,
          latestEstimate: null,
          load: [],
        ),
      );
      expect(
        find.text('Check in this morning to get your first estimate.'),
        findsNothing,
      );
      expect(
        find.text(
          'Your check-in is saved, but no estimate came back. '
          'Tap Update below to try again.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('what feeds this score names the real inputs', (tester) async {
    await _pump(tester, _withToday(_todays()));

    expect(find.text('Morning check-in'), findsOneWidget);
    expect(
      find.text('Sleep, soreness, energy and stress over the last 3 days'),
      findsOneWidget,
    );
    expect(
      find.text('This week compared with your usual week'),
      findsOneWidget,
    );
    expect(find.text('Past injuries'), findsOneWidget);
    expect(
      find.text('From your profile, and pain you report after a workout'),
      findsOneWidget,
    );
  });

  testWidgets('the load bars are named by weekday and read in the unit', (
    tester,
  ) async {
    final load = [
      for (var i = 0; i < 7; i++)
        VolumeBucket(label: '-${6 - i}d', volumeKg: i * 100.0),
    ];
    await _pump(tester, _withToday(_todays(), load: load), unit: WeightUnit.lb);
    await tester.scrollUntilVisible(find.byType(FsBarChart), 200);
    await tester.pumpAndSettle();

    final today = volumeToday();
    for (var i = 0; i < 7; i++) {
      final name = volumeBucketName(
        period: 'week',
        index: i,
        count: 7,
        fallback: load[i].label,
        today: today,
      );
      expect(find.text(name.axis), findsOneWidget);
    }
    final chart = tester.widget<FsBarChart>(find.byType(FsBarChart));
    // 600 kg is 1,323 lb, and the newest bar is today's.
    expect(chart.bars.last.tooltip, 'Today · 1,323 lb');
    expect(chart.bars.last.value, closeTo(1322.77, 0.01));
    expect(chart.label, '7-day training load');
  });

  group('320 dp at 2x text', () {
    Future<void> narrow(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    testWidgets('the card does not overflow', (tester) async {
      await narrow(tester);
      await _pump(
        tester,
        _withToday(
          _todays(
            level: 'high',
            score: 80,
            drivers: const [
              RiskDriver(key: 'recent_pain', value: 'severe'),
              RiskDriver(key: 'soreness', value: 'severe'),
              RiskDriver(key: 'injury_history', value: 2),
            ],
          ),
          load: [
            for (var i = 0; i < 7; i++)
              VolumeBucket(label: '-${6 - i}d', volumeKg: 1000.0 * i),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byType(FsBarChart), 200);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the guide does not overflow and scrolls to its end', (
      tester,
    ) async {
      await narrow(tester);
      await _pump(tester, _withToday(_todays()));
      await tester.tap(find.byKey(const Key('recovery.howToRead')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final sheet = find.byKey(const Key('howto.sheet'));
      await tester.scrollUntilVisible(
        find.byKey(const Key('howto.close')),
        200,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('howto.close')));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    });
  });
}
