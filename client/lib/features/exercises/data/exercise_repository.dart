import '../../../core/api_client.dart';
import '../domain/exercise.dart';
import '../domain/exercise_filters.dart';

class ExerciseRepository {
  ExerciseRepository(this._api);

  final ApiClient _api;

  String get baseUrl => _api.baseUrl;

  /// [muscleGroups] is sent as a repeated `muscleGroup` key, which the
  /// endpoint reads as "any of these" -- a training day is a set of groups,
  /// not one. Empty means no filter, the same thing an absent key means.
  Future<ExercisePage> list({
    List<String> muscleGroups = const [],
    String? equipment,
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _api.getJson('/api/v1/exercises', query: {
      if (muscleGroups.isNotEmpty) 'muscleGroup': muscleGroups,
      'equipment': equipment,
      'page': '$page',
      'limit': '$limit',
    });
    return ExercisePage.fromJson(data);
  }

  Future<ExerciseDetail> byId(int id) async =>
      ExerciseDetail.fromJson(await _api.getJson('/api/v1/exercises/$id'));

  Future<ExerciseFilters> filters() async =>
      ExerciseFilters.fromJson(await _api.getJson('/api/v1/exercises/filters'));
}
