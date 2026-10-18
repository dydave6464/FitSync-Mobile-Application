import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise_cues.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/domain/exercise_filters.dart';
import 'package:fitsync/features/exercises/domain/muscle_regions.dart';
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

  // These doubles predate the cues endpoint and no test here exercises it.
  @override
  Future<ExerciseCues> cues(int id) async =>
      const ExerciseCues(source: 'catalogue', injuryName: null, cues: []);

  @override
  Future<ExercisePage> list({
    List<String> muscleGroups = const [],
    String? equipment,
    String? search,
    int page = 1,
    int limit = 20,
  }) {
    if (page == 1) {
      final key = muscleGroups.isEmpty ? '' : muscleGroups.first;
      final page1 = pageOneByMuscleGroup[key];
      if (page1 == null) {
        throw StateError('no page-1 fixture for muscleGroup "$key"');
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
  test(
    'a stale loadMore response does not overwrite a fresher selection',
    () async {
      final page2Completer = Completer<ExercisePage>();
      final fake = FakeExerciseRepository(
        pageOneByMuscleGroup: {
          'abs': ExercisePage(
            items: [_summary(1, 'core page 1')],
            page: 1,
            limit: 20,
            total: 40,
          ),
          'biceps': ExercisePage(
            items: [_summary(101, 'arms page 1')],
            page: 1,
            limit: 20,
            total: 40,
          ),
        },
        page2Provider: () => page2Completer.future,
      );

      final container = ProviderContainer(
        overrides: [exerciseRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      // Select filter A and let its page 1 settle.
      container
          .read(selectedFiltersProvider.notifier)
          .setRegion(MuscleRegion.core);
      await container.read(exerciseListProvider.future);

      // Start loading page 2 for filter A, but don't let it resolve yet.
      final loadMoreFuture = container
          .read(exerciseListProvider.notifier)
          .loadMore();

      // Switch to filter B while filter A's page-2 request is still in flight.
      // build() reruns and settles on filter B's page 1.
      container
          .read(selectedFiltersProvider.notifier)
          .setRegion(MuscleRegion.arms);
      await container.read(exerciseListProvider.future);

      // Now let the stale filter-A page-2 response arrive.
      page2Completer.complete(
        ExercisePage(
          items: [_summary(2, 'core page 2')],
          page: 2,
          limit: 20,
          total: 40,
        ),
      );
      await loadMoreFuture;

      final state = container.read(exerciseListProvider).value!;
      expect(state.items.map((e) => e.name), ['arms page 1']);
    },
  );

  test(
    'loadMore appends the next page when the selection has not changed',
    () async {
      final fake = FakeExerciseRepository(
        pageOneByMuscleGroup: {
          '': ExercisePage(
            items: [_summary(1, 'page 1')],
            page: 1,
            limit: 20,
            total: 40,
          ),
        },
        page2Provider: () => Future.value(
          ExercisePage(
            items: [_summary(2, 'page 2')],
            page: 2,
            limit: 20,
            total: 40,
          ),
        ),
      );

      final container = ProviderContainer(
        overrides: [exerciseRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(exerciseListProvider.future);
      await container.read(exerciseListProvider.notifier).loadMore();

      final state = container.read(exerciseListProvider).value!;
      expect(state.items.map((e) => e.name), ['page 1', 'page 2']);
      expect(state.page, 2);
    },
  );

  group('the muscle region', () {
    test('a region asks for exactly its own muscle groups', () {
      for (final region in MuscleRegion.values) {
        expect(
          resolveMuscleGroups(region),
          region.muscleGroups,
          reason: region.label,
        );
      }
    });

    test('All asks for no muscle group at all', () {
      expect(resolveMuscleGroups(null), isEmpty);
    });

    test('clearing the filters takes the region off and keeps the term', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(selectedFiltersProvider.notifier);

      notifier.setRegion(MuscleRegion.legs);
      notifier.setEquipment('dumbbell');
      notifier.setSearch('squat');
      expect(container.read(selectedFiltersProvider).hasChipFilter, isTrue);

      notifier.clear();

      final after = container.read(selectedFiltersProvider);
      expect(after.region, isNull);
      expect(after.equipment, isNull);
      expect(after.search, 'squat');
      expect(after.hasChipFilter, isFalse);
    });

    test('a region alone counts as a filter', () {
      const filters = SelectedFilters(region: MuscleRegion.back);
      expect(filters.isEmpty, isFalse);
      expect(filters.hasChipFilter, isTrue);
      expect(filters, const SelectedFilters(region: MuscleRegion.back));
      expect(
        filters == const SelectedFilters(region: MuscleRegion.chest),
        isFalse,
      );
    });

    test('setting one filter leaves the others as they were', () {
      const start = SelectedFilters(
        region: MuscleRegion.arms,
        equipment: 'cable',
        search: 'curl',
      );
      expect(start.withEquipment(null).region, MuscleRegion.arms);
      expect(start.withSearch(null).region, MuscleRegion.arms);
      expect(start.withRegion(null).equipment, 'cable');
      expect(start.withRegion(null).search, 'curl');
    });
  });
}
