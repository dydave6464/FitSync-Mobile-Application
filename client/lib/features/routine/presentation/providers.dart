import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  Future<RoutineDay> build() => ref.watch(routineRepositoryProvider).today();

  /// Shown at once; put back and rethrown if the save fails, so the screen
  /// can say so. A tick is small enough that waiting on the network before
  /// the box changes would read as the tap not registering.
  Future<void> setDone(int habitId, bool done) async {
    final before = state.requireValue;
    state = AsyncData(before.withHabitDone(habitId, done));
    try {
      done ? await _repo.check(habitId) : await _repo.uncheck(habitId);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> add(HabitDraft draft) async {
    await _repo.add(draft);
    await _reload();
  }

  Future<void> edit(int habitId, HabitDraft draft) async {
    await _repo.edit(habitId, draft);
    await _reload();
  }

  Future<void> remove(int habitId) async {
    await _repo.remove(habitId);
    await _reload();
  }

  /// A fresh day rather than patching the list locally: a new or edited
  /// habit may or may not repeat today, and only the server says where it
  /// sorts.
  Future<void> _reload() async {
    state = AsyncData(await _repo.today());
  }
}
