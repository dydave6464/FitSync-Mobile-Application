import '../../../core/api_client.dart';
import '../domain/reminders.dart';

class ReminderRepository {
  ReminderRepository(this._api);

  final ApiClient _api;

  Future<ReminderSettings> read() async => ReminderSettings.fromJson(
    (await _api.getJson('/api/v1/reminders/settings'))['settings']
        as Map<String, dynamic>,
  );

  /// Sends only [fields]; answers the full settings.
  Future<ReminderSettings> patch(Map<String, dynamic> fields) async =>
      ReminderSettings.fromJson(
        (await _api.patchJson('/api/v1/reminders/settings', fields))['settings']
            as Map<String, dynamic>,
      );
}
