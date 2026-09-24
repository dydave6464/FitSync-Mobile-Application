import '../../../core/api_client.dart';
import '../domain/streaks.dart';

class StreakRepository {
  StreakRepository(this._api);

  final ApiClient _api;

  Future<Streak> read() async =>
      Streak.fromJson(await _api.getJson('/api/v1/streak'));
}

class GoalsRepository {
  GoalsRepository(this._api);

  final ApiClient _api;

  Future<List<LiftGoal>> list() async {
    final data = await _api.getJson('/api/v1/goals');
    return (data['goals'] as List<dynamic>)
        .map((g) => LiftGoal.fromJson(g as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<GoalOption>> options() async {
    final data = await _api.getJson('/api/v1/goals/options');
    return (data['options'] as List<dynamic>)
        .map((o) => GoalOption.fromJson(o as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// [targetKg] in kilograms, whatever unit the user typed it in.
  Future<LiftGoal> add({
    required int exerciseId,
    required double targetKg,
  }) async => LiftGoal.fromJson(
    (await _api.postJson('/api/v1/goals', {
          'exerciseId': exerciseId,
          'targetKg': targetKg,
        }))['goal']
        as Map<String, dynamic>,
  );

  Future<void> remove(int goalId) async {
    await _api.deleteJson('/api/v1/goals/$goalId');
  }
}
