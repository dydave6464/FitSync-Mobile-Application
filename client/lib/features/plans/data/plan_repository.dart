import '../../../core/api_client.dart';
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
}
