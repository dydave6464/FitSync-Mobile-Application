import '../../../core/api_client.dart';
import '../domain/exercise.dart';
import '../domain/exercise_filters.dart';

class ExerciseRepository {
  ExerciseRepository(this._api);

  final ApiClient _api;

  String get baseUrl => _api.baseUrl;

  Future<ExercisePage> list({
    String? muscleGroup,
    String? equipment,
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _api.getJson('/api/v1/exercises', query: {
      'muscleGroup': muscleGroup,
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
