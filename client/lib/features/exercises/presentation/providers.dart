import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/api_exception.dart';
import '../data/exercise_repository.dart';
import '../domain/exercise.dart';
import '../domain/exercise_filters.dart';

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
/// Only [ApiException]'s `NETWORK_ERROR` — raised by [ApiClient] when the
/// device could not reach the server at all — is transient in a way a retry
/// can fix. Every other code, whether named by the server
/// (`EXERCISE_NOT_FOUND`, `INVALID_QUERY_PARAM`) or raised locally for a
/// malformed response (`INVALID_RESPONSE`, `UNKNOWN_ERROR`), is permanent
/// from the client's side and must surface immediately. This function only
/// decides whether to retry at all; the backoff for the case that should
/// retry is still Riverpod's own default, bounded by [_maxTransientRetries].
Duration? apiRetryPolicy(int retryCount, Object error) {
  if (error is! ApiException || error.code != 'NETWORK_ERROR') return null;
  if (retryCount >= _maxTransientRetries) return null;
  return ProviderContainer.defaultRetry(retryCount, error);
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final exerciseRepositoryProvider = Provider<ExerciseRepository>(
  (ref) => ExerciseRepository(ref.watch(apiClientProvider)),
);

final exerciseFiltersProvider = FutureProvider<ExerciseFilters>(
  (ref) => ref.watch(exerciseRepositoryProvider).filters(),
  retry: apiRetryPolicy,
);

class SelectedFiltersNotifier extends Notifier<SelectedFilters> {
  @override
  SelectedFilters build() => const SelectedFilters();

  void setMuscleGroup(String? value) => state = state.withMuscleGroup(value);
  void setEquipment(String? value) => state = state.withEquipment(value);
  void clear() => state = const SelectedFilters();
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
  }) =>
      ExerciseListState(
        items: items ?? this.items,
        page: page ?? this.page,
        total: total ?? this.total,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

class ExerciseListNotifier extends AsyncNotifier<ExerciseListState> {
  @override
  Future<ExerciseListState> build() async {
    // Watching the selection means any filter change rebuilds this provider
    // from scratch — which is exactly the "reset to page 1" behaviour we want,
    // with no manual reset logic to forget.
    final filters = ref.watch(selectedFiltersProvider);
    final repo = ref.watch(exerciseRepositoryProvider);

    final result = await repo.list(
      muscleGroup: filters.muscleGroup,
      equipment: filters.equipment,
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

    final filters = ref.read(selectedFiltersProvider);
    final repo = ref.read(exerciseRepositoryProvider);

    try {
      final next = await repo.list(
        muscleGroup: filters.muscleGroup,
        equipment: filters.equipment,
        page: current.page + 1,
      );
      // The selection may have changed while this request was in flight —
      // build() already reran and produced a fresh state for it. Applying
      // this response on top would silently show the old filter's data
      // under the new selection, so discard it instead.
      //
      // Known gap, left alone on purpose: A -> B -> A. If the user switches
      // away from a filter and back while an old request for A is still in
      // flight, this equality check compares the captured `filters` against
      // the current selection and finds them equal again, even though
      // build() reran in between and this response is stale with respect to
      // it. The response still gets merged in.
      //
      // That is fine today because the merge is still correct data for the
      // selected filter: the catalogue is read-only with deterministic
      // ordering, so a stale page for filter A is identical to a fresh page
      // for filter A. The only visible artefact is a brief flicker (items
      // from the in-flight page appearing after the rebuilt list already
      // rendered) that self-heals on the next successful fetch.
      //
      // Reach for a generation counter instead of this value-equality guard
      // if any of these become true:
      //   - a write path is added, so page 1 (or any page) can change
      //     between the two A requests;
      //   - results become per-user or otherwise not deterministic, so a
      //     stale page for filter A is no longer guaranteed to match a
      //     fresh one;
      //   - any caller invalidates this list provider without changing
      //     SelectedFilters — value equality is blind to that by
      //     construction, since the filters object never actually changes.
      if (filters != ref.read(selectedFiltersProvider)) return;
      state = AsyncData(current.copyWith(
        items: [...current.items, ...next.items],
        page: next.page,
        total: next.total,
        hasMore: next.hasMore,
        loadingMore: false,
      ));
    } catch (err, stack) {
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

final exerciseDetailProvider =
    FutureProvider.family<ExerciseDetail, int>(
  (ref, id) => ref.watch(exerciseRepositoryProvider).byId(id),
  retry: apiRetryPolicy,
);
