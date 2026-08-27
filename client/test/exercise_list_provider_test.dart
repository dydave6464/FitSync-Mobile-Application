import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_filters.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';

/// A repository double whose page-1 responses are fixed per muscle group and
/// whose page-2 response is supplied by the caller, so a test can control
/// exactly when the "load more" request resolves.
class FakeExerciseRepository implements ExerciseRepository {
  FakeExerciseRepository({
    required this.pageOneByMuscleGroup,
    this.page2Provider,
  });

  final Map<String, ExercisePage> pageOneByMuscleGroup;
  final Future<ExercisePage> Function()? page2Provider;

  @override
  String get baseUrl => 'http://test.local';

  @override
  Future<ExercisePage> list({
    String? muscleGroup,
    String? equipment,
    int page = 1,
    int limit = 20,
  }) {
    if (page == 1) {
      final page1 = pageOneByMuscleGroup[muscleGroup ?? ''];
      if (page1 == null) {
        throw StateError('no page-1 fixture for muscleGroup "$muscleGroup"');
      }
      return Future.value(page1);
    }
    return page2Provider!();
  }

  @override
  Future<ExerciseDetail> byId(int id) => throw UnimplementedError();

  @override
  Future<ExerciseFilters> filters() => throw UnimplementedError();
}

ExerciseSummary _summary(int id, String name) => ExerciseSummary(
      exerciseId: id,
      name: name,
      muscleGroup: 'abs',
      equipment: null,
      thumbnailUrl: null,
    );

void main() {
  test('a stale loadMore response does not overwrite a fresher selection', () async {
    final page2Completer = Completer<ExercisePage>();
    final fake = FakeExerciseRepository(
      pageOneByMuscleGroup: {
        'abs': ExercisePage(
          items: [_summary(1, 'abs page 1')],
          page: 1,
          limit: 20,
          total: 40,
        ),
        'biceps': ExercisePage(
          items: [_summary(101, 'biceps page 1')],
          page: 1,
          limit: 20,
          total: 40,
        ),
      },
      page2Provider: () => page2Completer.future,
    );

    final container = ProviderContainer(overrides: [
      exerciseRepositoryProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    // Select filter A and let its page 1 settle.
    container.read(selectedFiltersProvider.notifier).setMuscleGroup('abs');
    await container.read(exerciseListProvider.future);

    // Start loading page 2 for filter A, but don't let it resolve yet.
    final loadMoreFuture =
        container.read(exerciseListProvider.notifier).loadMore();

    // Switch to filter B while filter A's page-2 request is still in flight.
    // build() reruns and settles on filter B's page 1.
    container.read(selectedFiltersProvider.notifier).setMuscleGroup('biceps');
    await container.read(exerciseListProvider.future);

    // Now let the stale filter-A page-2 response arrive.
    page2Completer.complete(ExercisePage(
      items: [_summary(2, 'abs page 2')],
      page: 2,
      limit: 20,
      total: 40,
    ));
    await loadMoreFuture;

    final state = container.read(exerciseListProvider).value!;
    expect(state.items.map((e) => e.name), ['biceps page 1']);
  });

  test('loadMore appends the next page when the selection has not changed', () async {
    final fake = FakeExerciseRepository(
      pageOneByMuscleGroup: {
        '': ExercisePage(
          items: [_summary(1, 'page 1')],
          page: 1,
          limit: 20,
          total: 40,
        ),
      },
      page2Provider: () => Future.value(ExercisePage(
        items: [_summary(2, 'page 2')],
        page: 2,
        limit: 20,
        total: 40,
      )),
    );

    final container = ProviderContainer(overrides: [
      exerciseRepositoryProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);

    await container.read(exerciseListProvider.future);
    await container.read(exerciseListProvider.notifier).loadMore();

    final state = container.read(exerciseListProvider).value!;
    expect(state.items.map((e) => e.name), ['page 1', 'page 2']);
    expect(state.page, 2);
  });
}
