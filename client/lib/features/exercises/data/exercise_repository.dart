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
  /// [search] matches anywhere in an exercise's name, case-insensitively, and
  /// narrows whatever the other filters already selected rather than
  /// replacing it. Empty is omitted rather than sent: the endpoint reads '' as
  /// no filter either way, but a URL that carries the key implies a search
  /// that is not happening.
  Future<ExercisePage> list({
    List<String> muscleGroups = const [],
    String? equipment,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final data = await _api.getJson('/api/v1/exercises', query: {
      if (muscleGroups.isNotEmpty) 'muscleGroup': muscleGroups,
      'equipment': equipment,
      if (search != null && search.isNotEmpty) 'search': search,
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
