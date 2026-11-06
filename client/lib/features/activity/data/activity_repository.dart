import '../../../core/api_client.dart';
import '../domain/activity.dart';

class ActivityRepository {
  ActivityRepository(this._api);

  final ApiClient _api;

  /// Sends the day's full total; the server keeps the higher of this and
  /// what it already has, so a failed save needs no queue.
  Future<ActivityDay> saveDay(String date, int steps) async =>
      ActivityDay.fromJson(
        await _api.putJson('/api/v1/activity/$date', {'steps': steps}),
      );

  /// Sends several days' full totals (1 to 7) in one request and gets the
  /// week back with them. The server keeps the higher count for each day,
  /// and skips (lists in `skipped`) a day outside today and the six before
  /// it rather than failing the rest.
  Future<ActivityWeek> saveDays(Map<String, int> days) async =>
      ActivityWeek.fromJson(
        await _api.putJson('/api/v1/activity', {
          'days': [
            for (final e in days.entries) {'date': e.key, 'steps': e.value},
          ],
        }),
      );

  Future<ActivityWeek> week() async =>
      ActivityWeek.fromJson(await _api.getJson('/api/v1/activity'));
}
