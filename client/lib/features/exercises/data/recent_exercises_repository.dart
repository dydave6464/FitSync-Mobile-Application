import '../../../core/api_client.dart';
import '../domain/exercise.dart';

/// The exercises the signed-in user has logged lately, newest first.
///
/// Its own class rather than a method on `ExerciseRepository`: that one is
/// implemented in full by several test doubles, and every one of them would
/// have to grow a method none of their tests call.
class RecentExercisesRepository {
  RecentExercisesRepository(this._api);

  final ApiClient _api;

  /// Rows in the catalogue list's own shape, so the library can render and
  /// pick them exactly as it does a list row.
  Future<List<ExerciseSummary>> recent({int limit = 10}) async {
    final data = await _api.getJson(
      '/api/v1/exercises/recent',
      query: {'limit': '$limit'},
    );
    return (data['exercises'] as List<dynamic>? ?? const [])
        .map((e) => ExerciseSummary.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}
