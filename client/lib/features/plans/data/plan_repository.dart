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
    final data = await _api.getJson(
      '/api/v1/plans/exercises/$planExerciseId/alternatives$query',
    );
    final rows = (data['alternatives'] as List).cast<Map<String, dynamic>>();
    return rows.map(ExerciseAlternative.fromJson).toList(growable: false);
  }

  /// Replaces one exercise and returns the whole updated plan, so the caller
  /// replaces state in a single hop rather than reconciling a partial update.
  Future<WorkoutPlan> swap(int planExerciseId, int exerciseId) async {
    final data = await _api.patchJson(
      '/api/v1/plans/exercises/$planExerciseId',
      {'exerciseId': exerciseId},
    );
    return WorkoutPlan.fromJson(data['plan'] as Map<String, dynamic>);
  }

  /// Replaces the active plan with a freshly generated one and returns it.
  ///
  /// The three overrides are all this endpoint takes: goals, injuries,
  /// equipment and level are read from the profile server-side, which is what
  /// stops a client generating against someone else's.
  Future<WorkoutPlan> regenerate({
    required String splitStyle,
    required int daysPerWeek,
    required int sessionLengthMin,
    bool replaceCustomPlan = false,
  }) async {
    final data = await _api.postJson('/api/v1/plans/regenerate', {
      'splitStyle': splitStyle,
      'daysPerWeek': daysPerWeek,
      'sessionLengthMin': sessionLengthMin,
      // Sent only when the user has actually answered the question. Sending it
      // unasked would defeat the server's guard for every caller at once.
      if (replaceCustomPlan) 'replaceCustomPlan': true,
    });
    return WorkoutPlan.fromJson(data['plan'] as Map<String, dynamic>);
  }

  /// Makes a finished workout part of the user's own plan.
  ///
  /// [splitStyle] is required only when this call CREATES the plan — the
  /// server reads the active plan's source to decide, so the caller does not
  /// have to. [dayNo] replaces that day; omitted, the workout is appended as a
  /// new one.
  ///
  /// Both are omitted from the body rather than sent as null: the endpoint
  /// treats an absent key and an explicit null the same, and leaving them out
  /// keeps the request describing only what the caller actually chose.
  Future<WorkoutPlan> planFromSession({
    required int sessionId,
    String? splitStyle,
    int? dayNo,
  }) async {
    final data = await _api.postJson('/api/v1/plans/from-session', {
      'sessionId': sessionId,
      'splitStyle': ?splitStyle,
      'dayNo': ?dayNo,
    });
    return WorkoutPlan.fromJson(data['plan'] as Map<String, dynamic>);
  }
}
