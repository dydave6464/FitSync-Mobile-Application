import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/presentation/progress_screen.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';

/// The real numbers off a completed manual workout.
const _mine = SessionHistoryEntry(
  sessionId: 32,
  sessionDate: '2026-09-14',
  setCount: 21,
  exerciseCount: 4,
  durationMin: 2,
  totalVolumeKg: 2953,
);

const _fromPlan = SessionHistoryEntry(
  sessionId: 30,
  sessionDate: '2026-09-12',
  setCount: 12,
  exerciseCount: 6,
  durationMin: 44,
  totalVolumeKg: 5100,
  planName: 'Upper Body · Push',
);

class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository({
    this.entries = const [],
    this.summaryValue = const TrainingSummary(
        sessionCount: 0, setCount: 0, totalVolumeKg: 0),
    this.error,
  });

  final List<SessionHistoryEntry> entries;
  final TrainingSummary summaryValue;
  final Object? error;

  final periodsAsked = <String>[];

  @override
  Future<SessionHistoryPage> history({int page = 1, int limit = 20}) async {
    if (error != null) throw error!;
    return SessionHistoryPage(
      sessions: entries, total: entries.length, page: page, limit: limit,
    );
  }

  @override
  Future<TrainingSummary> summary({String period = 'week'}) async {
    periodsAsked.add(period);
    if (error != null) throw error!;
    return summaryValue;
  }

  @override
  String get baseUrl => 'http://test.local';

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

Future<FakeSessionRepository> _pump(
  WidgetTester tester, {
  FakeSessionRepository? repo,
}) async {
  final fake = repo ?? FakeSessionRepository();
  await tester.pumpWidget(ProviderScope(
    overrides: [sessionRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(theme: fsLightTheme(), home: const ProgressScreen()),
  ));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('a completed workout is visible at last', (tester) async {
    // The whole reason this screen exists: a manual session completed, was
    // stored with its 21 sets and 2,953 kg, and had nowhere to be seen.
    await _pump(tester, repo: FakeSessionRepository(
      entries: const [_mine],
      summaryValue:
          const TrainingSummary(sessionCount: 1, setCount: 21, totalVolumeKg: 2953),
    ));

    expect(find.text('Your own workout'), findsOneWidget);
    expect(find.textContaining('21 sets'), findsWidgets);
  });

  testWidgets('the headline is what was lifted', (tester) async {
    await _pump(tester, repo: FakeSessionRepository(
      summaryValue:
          const TrainingSummary(sessionCount: 2, setCount: 35, totalVolumeKg: 8053),
    ));

    expect(find.textContaining('8,053'), findsOneWidget,
        reason: 'a five-figure total is unreadable without separators');
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('a plan workout is listed under its plan name', (tester) async {
    await _pump(tester, repo: FakeSessionRepository(entries: const [_fromPlan]));

    expect(find.text('Upper Body · Push'), findsOneWidget);
  });

  testWidgets('changing the window asks the server for it', (tester) async {
    final repo = await _pump(tester, repo: FakeSessionRepository());
    expect(repo.periodsAsked, ['week']);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    expect(repo.periodsAsked.last, 'month');
  });

  testWidgets('nothing trained yet says so plainly', (tester) async {
    // The placeholder this screen replaces said volume "appears here once you
    // have logged a few workouts" -- so a user who HAD logged one went
    // looking for a bug. An empty state must not imply the screen is waiting
    // on the user when it has simply been handed nothing.
    await _pump(tester, repo: FakeSessionRepository(entries: const []));

    expect(find.textContaining('No completed workouts yet'), findsOneWidget);
    expect(find.textContaining('once you have logged'), findsNothing);
  });

  testWidgets('a failure offers a retry rather than an empty screen',
      (tester) async {
    await _pump(tester, repo: FakeSessionRepository(
      error: const ApiException('NETWORK_ERROR', 'Could not reach the server.'),
    ));

    expect(find.textContaining('Could not reach the server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('No completed workouts yet'), findsNothing,
        reason: 'a failure is not the same as having trained nothing');
  });

  testWidgets('a session that logged no weight does not read as zero',
      (tester) async {
    // A bodyweight-only workout has no volume. Printing "0 kg" next to it
    // reads as a failure to record rather than as a fact about the workout.
    await _pump(tester, repo: FakeSessionRepository(entries: const [
      SessionHistoryEntry(
        sessionId: 1, sessionDate: '2026-09-13', setCount: 9,
        exerciseCount: 3, durationMin: 20,
      ),
    ]));

    expect(find.textContaining('0 kg'), findsNothing);
    expect(find.textContaining('9 sets'), findsWidgets);
  });
}
