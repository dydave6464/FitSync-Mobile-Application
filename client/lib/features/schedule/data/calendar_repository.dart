import '../../../core/api_client.dart';
import '../domain/calendar.dart';

class CalendarRepository {
  CalendarRepository(this._api);

  final ApiClient _api;

  /// [from] to [to] inclusive, `YYYY-MM-DD`; at most 62 days.
  Future<CalendarRange> range(String from, String to) async =>
      CalendarRange.fromJson(
        await _api.getJson('/api/v1/calendar', query: {'from': from, 'to': to}),
      );
}
