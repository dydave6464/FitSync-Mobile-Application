import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/manila_day.dart';
import 'package:fitsync/features/home/presentation/day_rollover.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart'
    show recoveryOverviewProvider;
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart'
    show RoutineController, routineTodayProvider;
import 'package:fitsync/features/sessions/domain/session_outcome.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart'
    show TrainingSummary;
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart'
    show
        completedDaysProvider,
        homeSummaryProvider,
        pendingOutcomeProvider,
        trainingAnalyticsProvider,
        trainingSummaryProvider;

/// Never settles: these tests count builds, and a value would only need
/// constructing to be ignored.
Future<T> _pending<T>() => Completer<T>().future;

class _CountingRoutine extends RoutineController {
  _CountingRoutine(this.builds);
  final Map<String, int> builds;
  @override
  Future<RoutineDay> build() {
    builds.update('routine', (n) => n + 1, ifAbsent: () => 1);
    return _pending();
  }
}

void main() {
  group('manilaDayOf', () {
    test('turns over at midnight in Manila, not UTC or the device', () {
      // Manila is UTC+8, so its midnight is 16:00 UTC the day before.
      expect(manilaDayOf(DateTime.utc(2026, 9, 23, 15, 59)), '2026-09-23');
      expect(manilaDayOf(DateTime.utc(2026, 9, 23, 16)), '2026-09-24');
      expect(manilaDayOf(DateTime.utc(2026, 12, 31, 16)), '2027-01-01');
    });
  });

  group('DayRollover', () {
    late Map<String, int> builds;
    late DateTime now;

    void count(String key) =>
        builds.update(key, (n) => n + 1, ifAbsent: () => 1);

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routineTodayProvider.overrideWith(() => _CountingRoutine(builds)),
            recoveryOverviewProvider.overrideWith((ref) {
              count('recovery');
              return _pending<RecoveryOverview>();
            }),
            homeSummaryProvider.overrideWith((ref) {
              count('homeSummary');
              return _pending<TrainingSummary>();
            }),
            trainingSummaryProvider.overrideWith((ref) {
              count('trainingSummary');
              return _pending<TrainingSummary>();
            }),
            trainingAnalyticsProvider.overrideWith((ref, period) {
              count('analytics:$period');
              return _pending<TrainingAnalytics>();
            }),
            completedDaysProvider.overrideWith((ref) {
              count('completedDays');
              return _pending<Set<String>>();
            }),
            pendingOutcomeProvider.overrideWith((ref) {
              count('pendingOutcome');
              return _pending<PendingOutcome?>();
            }),
          ],
          child: MaterialApp(
            home: DayRollover(
              now: () => now,
              child: Consumer(
                builder: (context, ref, _) {
                  ref.watch(routineTodayProvider);
                  ref.watch(recoveryOverviewProvider);
                  ref.watch(homeSummaryProvider);
                  ref.watch(trainingSummaryProvider);
                  ref.watch(trainingAnalyticsProvider('month'));
                  ref.watch(trainingAnalyticsProvider('week'));
                  ref.watch(completedDaysProvider);
                  ref.watch(pendingOutcomeProvider);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
    }

    Future<void> resume(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    }

    const everything = {
      'routine',
      'recovery',
      'homeSummary',
      'trainingSummary',
      'analytics:month',
      'analytics:week',
      'completedDays',
      'pendingOutcome',
    };

    setUp(() => builds = {});

    testWidgets('resuming on a new Manila day refetches every dated view', (
      tester,
    ) async {
      now = DateTime.utc(2026, 9, 23, 15, 30); // 23:30 in Manila
      await pump(tester);
      expect(builds, {for (final k in everything) k: 1});

      now = DateTime.utc(2026, 9, 23, 16, 5); // 00:05, the next day
      await resume(tester);

      expect(builds, {for (final k in everything) k: 2});
    });

    testWidgets('resuming later the same Manila day refetches nothing', (
      tester,
    ) async {
      // 00:30 to 23:30 in Manila: the UTC date changes in between, Manila's
      // does not.
      now = DateTime.utc(2026, 9, 23, 16, 30);
      await pump(tester);

      now = DateTime.utc(2026, 9, 24, 15, 30);
      await resume(tester);

      expect(builds, {for (final k in everything) k: 1});
    });

    testWidgets('a second resume on the same new day refetches only once', (
      tester,
    ) async {
      now = DateTime.utc(2026, 9, 23, 15, 30);
      await pump(tester);

      now = DateTime.utc(2026, 9, 23, 16, 5);
      await resume(tester);
      now = DateTime.utc(2026, 9, 23, 18);
      await resume(tester);

      expect(builds, {for (final k in everything) k: 2});
    });
  });
}
