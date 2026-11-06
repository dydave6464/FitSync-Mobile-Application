import '../../../core/api_client.dart';
import '../domain/exercise_alternative.dart';
import '../domain/workout_plan.dart';

/// A swap that landed: the updated plan, and the exercise the swap replaced
/// in its catalogue name. The previous exercise is null only from a server
/// that predates Undo, which does not say; then there is nothing to undo to.
class SwapResult {
  const SwapResult({
    required this.plan,
    this.previousExerciseId,
    this.previousName,
  });

  final WorkoutPlan plan;
  final int? previousExerciseId;
  final String? previousName;
}

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
  /// replaces state in a single hop rather than reconciling a partial update,
  /// with the exercise it replaced, which [undoSwap] puts back.
  Future<SwapResult> swap(int planExerciseId, int exerciseId) async {
    final data = await _api.patchJson(
      '/api/v1/plans/exercises/$planExerciseId',
      {'exerciseId': exerciseId},
    );
    final previous = data['previous'] as Map<String, dynamic>?;
    return SwapResult(
      plan: WorkoutPlan.fromJson(data['plan'] as Map<String, dynamic>),
      previousExerciseId: previous?['exerciseId'] as int?,
      previousName: previous?['name'] as String?,
    );
  }

  /// Undo for [swap]: puts [previousExerciseId] back in the row and takes
  /// the swap out of the ranker's history, so an undone swap does not read
  /// as the user rejecting it. The server refuses with 409
  /// `SWAP_NOT_UNDOABLE` once the row has moved on (swapped again, or its
  /// swap was never recorded).
  Future<WorkoutPlan> undoSwap(
    int planExerciseId,
    int previousExerciseId,
  ) async {
    final data = await _api.patchJson(
      '/api/v1/plans/exercises/$planExerciseId',
      {'exerciseId': previousExerciseId, 'revert': true},
    );
    return WorkoutPlan.fromJson(data['plan'] as Map<String, dynamic>);
  }

  /// Replaces the active plan with a freshly generated one and returns it.
  ///
  /// The three overrides are all this endpoint takes: goals, injuries,
  /// equipment and level are read from the profile server-side, which is what
  /// stops a client generating against someone else's.
  ///
  /// [sessionLengthMin] is omitted from the body when null, and the generator
  /// then derives the length from the user's level, goal and health check.
  Future<WorkoutPlan> regenerate({
    required String splitStyle,
    required int daysPerWeek,
    int? sessionLengthMin,
    bool replaceCustomPlan = false,
  }) async {
    final data = await _api.postJson('/api/v1/plans/regenerate', {
      'splitStyle': splitStyle,
      'daysPerWeek': daysPerWeek,
      'sessionLengthMin': ?sessionLengthMin,
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
