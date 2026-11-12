import '../../../core/api_client.dart';
import '../domain/routine.dart';

class RoutineRepository {
  RoutineRepository(this._api);

  final ApiClient _api;

  Future<RoutineDay> today() async =>
      RoutineDay.fromJson(await _api.getJson('/api/v1/routine/today'));

  /// Every active habit, whatever day it repeats on, in the server's order:
  /// timed by time, then untimed by title. None is ticked.
  Future<List<Habit>> all() async {
    final data = await _api.getJson('/api/v1/routine/habits');
    return (data['habits'] as List<dynamic>)
        .map((h) => Habit.fromJson(h as Map<String, dynamic>))
        .toList(growable: false);
  }

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

  /// Brings back a habit [remove] took away: Undo after a delete. A delete
  /// is soft, so the habit returns with its days and today's tick. Safe to
  /// send twice: restoring an active habit answers with it unchanged.
  Future<Habit> restore(int habitId) async => Habit.fromJson(
    (await _api.postJson(
          '/api/v1/routine/habits/$habitId/restore',
          const {},
        ))['habit']
        as Map<String, dynamic>,
  );

  /// [date] is the day the screen believes it is, from the [RoutineDay] it
  /// last loaded. The server compares it against its own CURDATE() and
  /// refuses the tick with `DAY_CHANGED` if the day has since turned over,
  /// rather than silently filing it under the new day.
  Future<void> check(int habitId, {String? date}) async {
    await _api.putJson(_checkPath(habitId, date), const {});
  }

  Future<void> uncheck(int habitId, {String? date}) async {
    await _api.deleteJson(_checkPath(habitId, date));
  }

  String _checkPath(int habitId, String? date) =>
      '/api/v1/routine/habits/$habitId/check${date == null ? '' : '?date=$date'}';
}
