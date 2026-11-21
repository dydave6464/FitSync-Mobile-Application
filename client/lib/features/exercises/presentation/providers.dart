import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/api_exception.dart';
import '../data/exercise_repository.dart';
import '../data/recent_exercises_repository.dart';
import '../domain/exercise.dart';
import '../domain/exercise_cues.dart';
import '../domain/exercise_filters.dart';
import '../domain/muscle_regions.dart';

/// How many times a transient failure is retried before the error is shown.
///
/// Riverpod's default allows ten. A refused connection backs off 200ms
/// doubling to a 6.4s cap — about 38 seconds — and a connection that *hangs*
/// is worse still, because each attempt then burns the client's full 10s
/// timeout. Either way the message written specifically to tell a developer
/// their `adb reverse` is missing ends up buried behind a minute of spinner,
/// which is the opposite of what it is for. Two retries still absorb a
/// genuine blip; the third would cost more than it can win.
const _maxTransientRetries = 2;

/// Riverpod retries any provider failure up to 10 times by default
/// (`ProviderContainer.defaultRetry`, ~200ms doubling to a 6.4s cap) for any
/// error that isn't a `ProviderException` or a Dart `Error` — which includes
/// [ApiException], since it `implements Exception`. Left alone, a permanent
/// failure like `EXERCISE_NOT_FOUND` or `INVALID_QUERY_PARAM` would be
/// retried ten times against the live server before the error branch ever
/// renders.
///
/// Only a transient failure, as [isRetryableError] defines it -- the device
/// could not reach the server, the server failed, or its answer was
/// garbled -- is retried; the "Try again" action on failed saves asks the
/// same question. Every other code named by the server
/// (`EXERCISE_NOT_FOUND`, `INVALID_QUERY_PARAM`) is permanent from the
/// client's side and must surface immediately. This function only decides
/// whether to retry at all; the backoff for the case that should retry is
/// still Riverpod's own default, bounded by [_maxTransientRetries].
Duration? apiRetryPolicy(int retryCount, Object error) {
  if (!isRetryableError(error)) return null;
  if (retryCount >= _maxTransientRetries) return null;
  return ProviderContainer.defaultRetry(retryCount, error);
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final exerciseRepositoryProvider = Provider<ExerciseRepository>(
  (ref) => ExerciseRepository(ref.watch(apiClientProvider)),
);

final recentExercisesRepositoryProvider = Provider<RecentExercisesRepository>(
  (ref) => RecentExercisesRepository(ref.watch(apiClientProvider)),
);

/// The user's recently logged exercises, for the library's "Recent" strip.
///
/// autoDispose so a library opened afresh asks again: a workout logged since
/// the last visit is exactly what should appear here next time. Finishing a
/// workout also invalidates it, for the one time the library is still open
/// underneath (see [ActiveSessionController.complete]).
final recentExercisesProvider =
    FutureProvider.autoDispose<List<ExerciseSummary>>(
      (ref) => ref.watch(recentExercisesRepositoryProvider).recent(),
      retry: apiRetryPolicy,
    );

/// The cues for one exercise, which the server may have written for the user's
/// injury. autoDispose because a workout touches a handful of exercises and
/// never returns to most of them.
final exerciseCuesProvider = FutureProvider.autoDispose
    .family<ExerciseCues, int>(
      (ref, exerciseId) =>
          ref.watch(exerciseRepositoryProvider).cues(exerciseId),
      retry: apiRetryPolicy,
    );

final exerciseFiltersProvider = FutureProvider<ExerciseFilters>(
  (ref) => ref.watch(exerciseRepositoryProvider).filters(),
  retry: apiRetryPolicy,
);

class SelectedFiltersNotifier extends Notifier<SelectedFilters> {
  @override
  SelectedFilters build() => const SelectedFilters();

  void setRegion(MuscleRegion? value) => state = state.withRegion(value);
  void setEquipment(String? value) => state = state.withEquipment(value);
  void setSearch(String? value) => state = state.withSearch(value);

  /// Clears the chips, keeping whatever is typed in the search box. See
  /// [SelectedFilters.hasChipFilter] for why the box is not included.
  void clear() => state = SelectedFilters(search: state.search);
}

final selectedFiltersProvider =
    NotifierProvider<SelectedFiltersNotifier, SelectedFilters>(
      SelectedFiltersNotifier.new,
    );

/// The accumulated list across pages, plus enough state to drive infinite
/// scroll without the screen tracking page numbers itself.
class ExerciseListState {
  const ExerciseListState({
    required this.items,
    required this.page,
    required this.total,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<ExerciseSummary> items;
  final int page;
  final int total;
  final bool hasMore;
  final bool loadingMore;

  ExerciseListState copyWith({
    List<ExerciseSummary>? items,
    int? page,
    int? total,
    bool? hasMore,
    bool? loadingMore,
  }) => ExerciseListState(
    items: items ?? this.items,
    page: page ?? this.page,
    total: total ?? this.total,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// What to actually ask the catalogue for: a muscle button picks one body
/// area, itself several groups, and "All" (null) asks for none.
List<String> resolveMuscleGroups(MuscleRegion? region) =>
    region?.muscleGroups ?? const [];

class ExerciseListNotifier extends AsyncNotifier<ExerciseListState> {
  @override
  Future<ExerciseListState> build() async {
    // Watching the selection means any filter change rebuilds this provider
    // from scratch — which is exactly the "reset to page 1" behaviour we want,
    // with no manual reset logic to forget.
    final filters = ref.watch(selectedFiltersProvider);
    final repo = ref.watch(exerciseRepositoryProvider);

    final result = await repo.list(
      muscleGroups: resolveMuscleGroups(filters.region),
      equipment: filters.equipment,
      search: filters.search,
      page: 1,
    );

    return ExerciseListState(
      items: result.items,
      page: result.page,
      total: result.total,
      hasMore: result.hasMore,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true));

    // The Ref of the build this page belongs to. The notifier itself outlives
    // a rebuild, and its `ref` getter moves on to the new build's Ref, so
    // only this captured one can tell that the list was rebuilt meanwhile.
    final ref = this.ref;
    final filters = ref.read(selectedFiltersProvider);
    final repo = ref.read(exerciseRepositoryProvider);

    try {
      final next = await repo.list(
        muscleGroups: resolveMuscleGroups(filters.region),
        equipment: filters.equipment,
        search: filters.search,
        page: current.page + 1,
      );
      // The list was rebuilt while this request was in flight: an injury
      // edit or a sign-out invalidates it without touching SelectedFilters,
      // so the equality check below cannot see that. The captured Ref is no
      // longer mounted then, and the response belongs to a list that is gone
      // (for a sign-out, to another account). Drop it; reading through the
      // old Ref would also throw UnmountedRefException.
      if (!ref.mounted) return;
      // The selection may have changed while this request was in flight —
      // build() already reran and produced a fresh state for it. Applying
      // this response on top would silently show the old filter's data
      // under the new selection, so discard it instead.
      //
      // A -> B -> A needs no extra care: switching filters rebuilds the
      // list, so the mounted check above already drops the old A page.
      if (filters != ref.read(selectedFiltersProvider)) return;
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...next.items],
          page: next.page,
          total: next.total,
          hasMore: next.hasMore,
          loadingMore: false,
        ),
      );
    } catch (err, stack) {
      if (!ref.mounted) return;
      if (filters != ref.read(selectedFiltersProvider)) return;
      // A failed "load more" must not discard the pages already shown.
      state = AsyncData(current.copyWith(loadingMore: false));
      ref.read(listErrorProvider.notifier).report(err, stack);
    }
  }
}

final exerciseListProvider =
    AsyncNotifierProvider<ExerciseListNotifier, ExerciseListState>(
      ExerciseListNotifier.new,
      retry: apiRetryPolicy,
    );

/// Surfaces a pagination failure without tearing down the list already on
/// screen. The list screen shows it as a snack bar.
class ListErrorNotifier extends Notifier<Object?> {
  @override
  Object? build() => null;

  void report(Object error, StackTrace _) => state = error;
  void clear() => state = null;
}

final listErrorProvider = NotifierProvider<ListErrorNotifier, Object?>(
  ListErrorNotifier.new,
);

final exerciseDetailProvider = FutureProvider.family<ExerciseDetail, int>(
  (ref, id) => ref.watch(exerciseRepositoryProvider).byId(id),
  retry: apiRetryPolicy,
);
