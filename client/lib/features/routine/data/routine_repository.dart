import '../../../core/api_client.dart';
import '../domain/routine.dart';

class RoutineRepository {
  RoutineRepository(this._api);

  final ApiClient _api;

  Future<RoutineDay> today() async =>
      RoutineDay.fromJson(await _api.getJson('/api/v1/routine/today'));

  Future<Habit> add(HabitDraft draft) async => Habit.fromJson(
    (await _api.postJson('/api/v1/routine/habits', draft.toJson()))['habit']
        as Map<String, dynamic>,
  );

  Future<Habit> edit(int habitId, HabitDraft draft) async => Habit.fromJson(
    (await _api.patchJson(
          '/api/v1/routine/habits/$habitId',
          draft.toJson(),
        ))['habit']
        as Map<String, dynamic>,
  );

  Future<void> remove(int habitId) async {
    await _api.deleteJson('/api/v1/routine/habits/$habitId');
  }

  Future<void> check(int habitId) async {
    await _api.putJson('/api/v1/routine/habits/$habitId/check', const {});
  }

  Future<void> uncheck(int habitId) async {
    await _api.deleteJson('/api/v1/routine/habits/$habitId/check');
  }
}
