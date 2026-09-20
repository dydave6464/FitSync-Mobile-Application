import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy;
import '../data/session_repository.dart';
import '../domain/active_session.dart';
import '../domain/session_history.dart';
import '../domain/training_analytics.dart';

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(ref.watch(apiClientProvider)),
);

/// The session being logged right now, or null.
///
/// Writes fold the server's response back into state rather than refetching:
/// the response IS the stored truth, so a second round trip would only add
/// latency to every tick.
class ActiveSessionController extends AsyncNotifier<ActiveSession?> {
  SessionRepository get _repo => ref.read(sessionRepositoryProvider);

  @override
  Future<ActiveSession?> build() => _repo.active();

  ActiveSession get _current {
    final session = state.value;
    if (session == null) {
      throw StateError('No session is in progress.');
    }
    return session;
  }

  Future<void> start({List<int>? exerciseIds}) async {
    state = AsyncValue.data(await _repo.start(exerciseIds: exerciseIds));
  }

  /// Write-through. The caller awaits this and only then shows a tick, so a
  /// visible tick always means a stored set. A failure rethrows with state
  /// unchanged, leaving the row for the user to retry.
  ///
  /// State is rebuilt from [_current] read AFTER the await, not from the
  /// snapshot taken before it. Two rows can each have an in-flight write at
  /// once; if the write issued second happens to resolve last and folds it
  /// into a pre-await snapshot, that snapshot predates the first write too,
  /// so it would silently erase it. Reading current state fresh after the
  /// await always folds onto whatever the other call already stored.
  Future<void> logSet({
    required int exerciseId,
    required int setNumber,
    double? weightKg,
    int? reps,
  }) async {
    final sessionId = _current.sessionId;
    final stored = await _repo.logSet(
      sessionId,
      exerciseId: exerciseId,
      setNumber: setNumber,
      weightKg: weightKg,
      reps: reps,
    );
    state = AsyncValue.data(_current.withSet(stored));
  }

  /// Same reasoning as [logSet]: [_current] is read again after the await so
  /// a concurrent write in flight for a different set is not clobbered.
  Future<void> unlogSet({
    required int exerciseId,
    required int setNumber,
  }) async {
    final sessionId = _current.sessionId;
    await _repo.deleteSet(
      sessionId,
      exerciseId: exerciseId,
      setNumber: setNumber,
    );
    state = AsyncValue.data(_current.withoutSet(exerciseId, setNumber));
  }

  Future<ActiveSession> complete(int durationMin) async {
    final done = await _repo.complete(_current.sessionId, durationMin);
    // Nothing is in progress now, so the Plan tab offers Start, not Resume.
    state = const AsyncValue.data(null);

    // Everything that answers "what have I done" is now out of date, and none
    // of these is autoDispose -- each holds whatever it resolved to for the
    // life of the app. On a new account they all resolve EMPTY before the
    // first workout, so leaving them alone means the Progress tab goes on
    // saying "No completed workouts yet" over a workout the server has
    // stored, until the app is restarted. Invalidating only the week strip
    // is what that looked like.
    //
    // trainingAnalyticsProvider is invalidated whole, without a period: the
    // user may have looked at more than one segment, and every element of it
    // is equally stale now. (This read "the two families" until the Progress
    // rework removed the e1RM card, which was the only reader of
    // strengthSeriesProvider -- the /sessions/strength endpoint stays.)
    ref.invalidate(completedDaysProvider); // the strip's dot for today
    ref.invalidate(sessionHistoryProvider); // the Progress tab's list
    ref.invalidate(trainingSummaryProvider); // its totals
    ref.invalidate(trainingAnalyticsProvider); // volume, adherence, muscles
    ref.invalidate(lastWorkoutProvider); // what the "+" sheet repeats
    return done;
  }

  Future<void> abandon() async {
    await _repo.abandon(_current.sessionId);
    state = const AsyncValue.data(null);
  }
}

final activeSessionProvider =
    AsyncNotifierProvider<ActiveSessionController, ActiveSession?>(
      ActiveSessionController.new,
    );

/// Which window the Progress tab is summarising: 'week', 'month' or 'year'.
///
/// Rolling windows, not calendar ones -- see SUMMARY_WINDOWS in
/// `server/src/db/sessions.js` for why.
class TrainingPeriodNotifier extends Notifier<String> {
  @override
  String build() => 'week';

  void set(String period) => state = period;
}

final trainingPeriodProvider = NotifierProvider<TrainingPeriodNotifier, String>(
  TrainingPeriodNotifier.new,
);

/// What the chosen window added up to. Rebuilt whenever the window changes,
/// which is exactly the refetch we want with no manual reset logic.
final trainingSummaryProvider = FutureProvider<TrainingSummary>(
  (ref) => ref
      .watch(sessionRepositoryProvider)
      .summary(period: ref.watch(trainingPeriodProvider)),
  retry: apiRetryPolicy,
);

/// Finished workouts, newest first. Not windowed: the list answers "what have
/// I done", which a user reads independently of whichever total is on screen.
final sessionHistoryProvider = FutureProvider<SessionHistoryPage>(
  (ref) => ref.watch(sessionRepositoryProvider).history(),
  retry: apiRetryPolicy,
);

/// The workout the "+" sheet offers to repeat, or null when there is none.
final lastWorkoutProvider = FutureProvider<LastWorkout?>(
  (ref) => ref.watch(sessionRepositoryProvider).lastWorkout(),
  retry: apiRetryPolicy,
);

/// `YYYY-MM-DD` for every completed session since Monday. Feeds the week strip.
final completedDaysProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(sessionRepositoryProvider).completedThisWeek(),
  retry: apiRetryPolicy,
);

/// Previous weights for a whole plan in one request.
///
/// The family key is a comma-joined String, NOT a `List<int>`. A Riverpod
/// family looks its argument up with `==`, and Dart lists compare by identity —
/// so a `List<int>` key would miss the cache on every rebuild and issue a fresh
/// request each time, while leaking a provider element per list instance.
/// Build the key with [lastPerformanceKey].
///
/// `autoDispose` because a swap changes the exercise ids, and the old key would
/// otherwise stay resident for the app's lifetime.
final lastPerformanceProvider = FutureProvider.autoDispose
    .family<Map<int, LastPerformance>, String>(
      (ref, key) => ref
          .watch(sessionRepositoryProvider)
          .lastPerformance(
            key.isEmpty
                ? const []
                : key.split(',').map(int.parse).toList(growable: false),
          ),
      retry: apiRetryPolicy,
    );

/// Sorted so two orderings of the same plan share one cache entry.
String lastPerformanceKey(Iterable<int> exerciseIds) =>
    (exerciseIds.toList()..sort()).join(',');

/// Volume, adherence and muscle split for the Progress tab's chosen window.
///
/// Keyed on period like [bodyWeightProvider], so switching the segment
/// refetches only this card's data.
final trainingAnalyticsProvider =
    FutureProvider.family<TrainingAnalytics, String>(
      (ref, period) => ref.watch(sessionRepositoryProvider).analytics(period),
      retry: apiRetryPolicy,
    );
