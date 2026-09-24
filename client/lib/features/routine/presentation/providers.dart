import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy;
import '../data/routine_repository.dart';
import '../domain/routine.dart';

final routineRepositoryProvider = Provider<RoutineRepository>(
  (ref) => RoutineRepository(ref.watch(apiClientProvider)),
);

/// Today's checklist, shared by the routine screen and Home's card, so a tick
/// on one is already on the other.
final routineTodayProvider =
    AsyncNotifierProvider<RoutineController, RoutineDay>(
      RoutineController.new,
      retry: apiRetryPolicy,
    );

class RoutineController extends AsyncNotifier<RoutineDay> {
  RoutineRepository get _repo => ref.read(routineRepositoryProvider);

  /// Habits with a tick in flight. A second tap on one of these is ignored
  /// rather than queued: the first tap's outcome is what will land, and
  /// firing a second write for the same habit could resolve out of order
  /// with it.
  final Set<int> _inFlight = {};

  @override
  Future<RoutineDay> build() => ref.watch(routineRepositoryProvider).today();

  /// Shown at once; put back and rethrown if the save fails, so the screen
  /// can say so. A tick is small enough that waiting on the network before
  /// the box changes would read as the tap not registering.
  ///
  /// The rollback on failure reads and writes the CURRENT state, not a
  /// snapshot taken before the write started: another habit's tick, add,
  /// edit or delete may have landed while this one was in flight, and a
  /// whole-day snapshot would silently erase it. `withHabitDone` is a no-op
  /// for a habit id no longer in the day, so a rollback after a reload that
  /// dropped it does nothing rather than throwing.
  ///
  /// The day shown is sent with the write, so the server can tell a stale
  /// screen from a live one. `DAY_CHANGED` (the day turned over since this
  /// screen loaded) and `HABIT_NOT_TODAY` (the habit was never on the day now
  /// current) both mean the same thing to the user -- the checklist on screen
  /// is no longer today's -- so both reload it via [_reload], which is safe
  /// to call after a failure: it never throws its own error into this one.
  Future<void> setDone(int habitId, bool done) async {
    if (_inFlight.contains(habitId)) return;
    _inFlight.add(habitId);
    final date = state.requireValue.date;
    state = AsyncData(state.requireValue.withHabitDone(habitId, done));
    try {
      done
          ? await _repo.check(habitId, date: date)
          : await _repo.uncheck(habitId, date: date);
    } catch (error) {
      state = AsyncData(state.requireValue.withHabitDone(habitId, !done));
      if (error is ApiException &&
          (error.code == 'DAY_CHANGED' || error.code == 'HABIT_NOT_TODAY')) {
        await _reload();
      }
      rethrow;
    } finally {
      _inFlight.remove(habitId);
    }
  }

  /// Returns the saved habit -- the repository already gets it back from the
  /// server -- so the sheet can tell whether it repeats today without a
  /// second round trip, and say so if it does not.
  Future<Habit> add(HabitDraft draft) async {
    final habit = await _repo.add(draft);
    await _reload();
    return habit;
  }

  Future<Habit> edit(int habitId, HabitDraft draft) async {
    final habit = await _repo.edit(habitId, draft);
    await _reload();
    return habit;
  }

  Future<void> remove(int habitId) async {
    await _repo.remove(habitId);
    await _reload();
  }

  /// A fresh day rather than patching the list locally: a new or edited
  /// habit may or may not repeat today, and only the server says where it
  /// sorts.
  ///
  /// The write above this already landed, so a failure here must not read as
  /// one: it falls back to [AsyncNotifier.invalidateSelf], which asks the
  /// provider to refetch on its own, rather than throwing into the caller.
  /// Without this, a reload that failed right after a successful write left
  /// the sheet showing an error over a save that had, in fact, gone through —
  /// saving again created a duplicate habit, and deleting again answered "No
  /// such habit".
  Future<void> _reload() async {
    try {
      state = AsyncData(await _repo.today());
    } catch (_) {
      ref.invalidateSelf();
    }
  }
}
