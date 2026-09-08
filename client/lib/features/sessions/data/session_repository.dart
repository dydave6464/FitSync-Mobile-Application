import '../../../core/api_client.dart';
import '../domain/active_session.dart';

class SessionRepository {
  SessionRepository(this._api);

  final ApiClient _api;

  String get baseUrl => _api.baseUrl;

  /// Null when nothing is in progress — a normal state, not a failure, so it
  /// is not an exception. Mirrors `PlanRepository.activePlan`.
  Future<ActiveSession?> active() async {
    final data = await _api.getJson('/api/v1/sessions/active');
    final session = data['session'];
    if (session == null) return null;
    return ActiveSession.fromJson(session as Map<String, dynamic>);
  }

  /// Idempotent server-side: calling this with a session already in progress
  /// returns that one rather than starting a second.
  Future<ActiveSession> start() async {
    final data = await _api.postJson('/api/v1/sessions', const {});
    return ActiveSession.fromJson(data['session'] as Map<String, dynamic>);
  }

  Future<LoggedSet> logSet(
    int sessionId, {
    required int exerciseId,
    required int setNumber,
    double? weightKg,
    int? reps,
  }) async {
    final data = await _api.putJson('/api/v1/sessions/$sessionId/sets', {
      'exerciseId': exerciseId,
      'setNumber': setNumber,
      'weightKg': weightKg,
      'reps': reps,
    });
    return LoggedSet.fromJson(data['set'] as Map<String, dynamic>);
  }

  Future<void> deleteSet(
    int sessionId, {
    required int exerciseId,
    required int setNumber,
  }) =>
      _api.deleteJson('/api/v1/sessions/$sessionId/sets/$exerciseId/$setNumber');

  Future<ActiveSession> complete(int sessionId, int durationMin) async {
    final data = await _api.postJson(
      '/api/v1/sessions/$sessionId/complete',
      {'durationMin': durationMin},
    );
    return ActiveSession.fromJson(data['session'] as Map<String, dynamic>);
  }

  Future<void> abandon(int sessionId) =>
      _api.postJson('/api/v1/sessions/$sessionId/abandon', const {});

  /// Keyed by exercise so the logger can look one up without scanning. One
  /// request for the whole plan — six round trips on gym wifi is the
  /// difference between a screen that is ready and one that fills in.
  Future<Map<int, LastPerformance>> lastPerformance(List<int> exerciseIds) async {
    if (exerciseIds.isEmpty) return const {};

    final data = await _api.getJson(
      '/api/v1/sessions/last-performance',
      query: {'exerciseIds': exerciseIds.join(',')},
    );
    final rows = (data['performances'] as List).cast<Map<String, dynamic>>();
    return {
      for (final row in rows)
        row['exerciseId'] as int: LastPerformance.fromJson(row),
    };
  }

  /// `YYYY-MM-DD` strings, for the Plan tab's week strip.
  Future<Set<String>> completedThisWeek() async {
    final data = await _api.getJson('/api/v1/sessions/week');
    return (data['dates'] as List).cast<String>().toSet();
  }
}
