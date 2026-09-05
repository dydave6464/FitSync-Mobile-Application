import '../../../core/api_client.dart';
import '../domain/exercise_alternative.dart';
import '../domain/workout_plan.dart';

class PlanRepository {
  PlanRepository(this._api);

  final ApiClient _api;

  String get baseUrl => _api.baseUrl;

  /// Null when the user has no active plan.
  ///
  /// That is a normal state, not a failure — anyone part way through
  /// onboarding is in it — so it comes back as null rather than an exception.
  Future<WorkoutPlan?> activePlan() async {
    final data = await _api.getJson('/api/v1/plans/active');
    final plan = data['plan'];
    if (plan == null) return null;
    return WorkoutPlan.fromJson(plan as Map<String, dynamic>);
  }

  /// Swap candidates for one plan row. [q] searches by name across every
  /// muscle group; without it the server returns same-muscle alternatives.
  Future<List<ExerciseAlternative>> alternatives(
    int planExerciseId, {
    String? q,
  }) async {
    final params = <String>[
      if (q != null && q.isNotEmpty) 'q=${Uri.encodeQueryComponent(q)}',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final data = await _api.getJson('/api/v1/plans/exercises/$planExerciseId/alternatives$query');
    final rows = (data['alternatives'] as List).cast<Map<String, dynamic>>();
    return rows.map(ExerciseAlternative.fromJson).toList(growable: false);
  }

  /// Replaces one exercise and returns the whole updated plan, so the caller
  /// replaces state in a single hop rather than reconciling a partial update.
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) async {
    final data = await _api.patchJson(
      '/api/v1/plans/exercises/$planExerciseId', {'exerciseId': exerciseId},
    );
    return WorkoutPlan.fromJson(data['plan'] as Map<String, dynamic>);
  }
}
