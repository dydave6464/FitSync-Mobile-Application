import 'package:fitsync/features/exercises/data/recent_exercises_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';

/// Stands in for `GET /exercises/recent` in tests that render the library for
/// some other reason. Without it they reach the real API client, fail
/// quietly, and pass only because the Recent strip hides on error.
class NoRecentExercises implements RecentExercisesRepository {
  @override
  Future<List<ExerciseSummary>> recent({int limit = 10}) async => const [];
}

/// The override to add beside a test's `exerciseRepositoryProvider` one.
final noRecentExercises = recentExercisesRepositoryProvider.overrideWithValue(
  NoRecentExercises(),
);
