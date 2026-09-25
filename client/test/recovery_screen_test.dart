import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart';
import 'package:fitsync/features/recovery/presentation/recovery_screen.dart';

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

Future<void> _pump(WidgetTester tester, RecoveryOverview overview) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recoveryOverviewProvider.overrideWith((ref) async => overview),
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
    },
  );

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

  testWidgets('carries no disclaimer line, with an estimate or without', (
    tester,
  ) async {
    // Removed at the user's request on 2026-09-24.
    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: _checkin,
        latestEstimate: _estimate,
        load: [],
      ),
    );
    expect(find.textContaining('not a medical diagnosis'), findsNothing);

    await _pump(
      tester,
      const RecoveryOverview(
        todayCheckin: null,
        latestEstimate: null,
        load: [],
      ),
    );
    expect(find.textContaining('not a medical diagnosis'), findsNothing);
  });
}
