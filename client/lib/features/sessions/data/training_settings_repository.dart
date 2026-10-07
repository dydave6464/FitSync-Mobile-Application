import '../../../core/api_client.dart';

/// The account's training preferences, from /training/settings. Today that
/// is the rest between sets, which follows the user to a new phone the way
/// the weight unit does.
class TrainingSettingsRepository {
  TrainingSettingsRepository(this._api);

  final ApiClient _api;

  Future<int> restSeconds() async =>
      _restSeconds(await _api.getJson('/api/v1/training/settings'));

  /// Answers what the server stored, which is what the screen should show.
  Future<int> setRestSeconds(int seconds) async => _restSeconds(
    await _api.patchJson('/api/v1/training/settings', {'restSeconds': seconds}),
  );

  int _restSeconds(Map<String, dynamic> data) =>
      (data['settings'] as Map<String, dynamic>)['restSeconds'] as int;
}
