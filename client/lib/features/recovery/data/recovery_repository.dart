import '../../../core/api_client.dart';
import '../domain/recovery.dart';

class RecoveryRepository {
  RecoveryRepository(this._api);

  final ApiClient _api;

  /// getJson/postJson, not get/post -- those are the names ApiClient actually
  /// exposes, and both already strip the outer 'data' envelope (see
  /// ApiClient._unwrap and ProfileRepository's bodyWeight()/logBodyWeight()),
  /// so the map handed back here is the overview itself, not a wrapper around it.
  Future<RecoveryOverview> overview() async {
    final data = await _api.getJson('/api/v1/recovery');
    return RecoveryOverview.fromJson(data);
  }

  /// Answers go up exactly as given. See MorningCheckin's class comment.
  Future<InjuryRiskEstimate> checkIn(Map<String, String> answers) async {
    final data = await _api.postJson('/api/v1/recovery/checkin', answers);
    return InjuryRiskEstimate.fromJson(
      data['estimate'] as Map<String, dynamic>,
    );
  }
}
