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

  Future<ActivityWeek> week() async =>
      ActivityWeek.fromJson(await _api.getJson('/api/v1/activity'));
}
