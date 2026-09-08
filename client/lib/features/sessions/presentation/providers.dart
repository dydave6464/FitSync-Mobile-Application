import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/providers.dart' show apiClientProvider, apiRetryPolicy;
import '../data/session_repository.dart';
import '../domain/active_session.dart';

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

  Future<void> start() async {
    state = AsyncValue.data(await _repo.start());
  }

  /// Write-through. The caller awaits this and only then shows a tick, so a
  /// visible tick always means a stored set. A failure rethrows with state
  /// unchanged, leaving the row for the user to retry.
  Future<void> logSet({
    required int exerciseId,
    required int setNumber,
    double? weightKg,
    int? reps,
  }) async {
    final session = _current;
    final stored = await _repo.logSet(
      session.sessionId,
      exerciseId: exerciseId,
      setNumber: setNumber,
      weightKg: weightKg,
      reps: reps,
    );
    state = AsyncValue.data(session.withSet(stored));
  }

  Future<void> unlogSet({required int exerciseId, required int setNumber}) async {
    final session = _current;
    await _repo.deleteSet(session.sessionId, exerciseId: exerciseId, setNumber: setNumber);
    state = AsyncValue.data(session.withoutSet(exerciseId, setNumber));
  }

  Future<ActiveSession> complete(int durationMin) async {
    final done = await _repo.complete(_current.sessionId, durationMin);
    // Nothing is in progress now, so the Plan tab offers Start, not Resume.
    state = const AsyncValue.data(null);
    // The strip gains a filled dot for today.
    ref.invalidate(completedDaysProvider);
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
  (ref, key) => ref.watch(sessionRepositoryProvider).lastPerformance(
        key.isEmpty
            ? const []
            : key.split(',').map(int.parse).toList(growable: false),
      ),
  retry: apiRetryPolicy,
);

/// Sorted so two orderings of the same plan share one cache entry.
String lastPerformanceKey(Iterable<int> exerciseIds) =>
    (exerciseIds.toList()..sort()).join(',');
