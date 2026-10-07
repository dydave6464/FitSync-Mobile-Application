import '../../../core/api_client.dart';
import '../domain/health_answers.dart';

/// The user's health check, from /profile/health. Kept apart from
/// ProfileRepository: the answers are never part of the profile payload.
class HealthRepository {
  HealthRepository(this._api);

  final ApiClient _api;

  Future<HealthAnswers?> getHealth() async =>
      _health(await _api.getJson('/api/v1/profile/health'));

  /// Answers what the server stored.
  Future<HealthAnswers?> setHealth(HealthAnswers answers) async =>
      _health(await _api.putJson('/api/v1/profile/health', answers.toJson()));

  Future<void> deleteHealth() async {
    await _api.deleteJson('/api/v1/profile/health');
  }

  HealthAnswers? _health(Map<String, dynamic> data) {
    final health = data['health'];
    return health == null
        ? null
        : HealthAnswers.fromJson(health as Map<String, dynamic>);
  }
}
