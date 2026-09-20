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
  ///
  /// Nothing is read back out. The `estimate` this POST returns is the ML
  /// service's own body -- `riskLevel` and `trainingLoadScore`, and nothing
  /// else (ml/app/schemas.py, InjuryRiskResponse) -- so it cannot build an
  /// [InjuryRiskEstimate], which is dated. The dated one comes from
  /// GET /api/v1/recovery, which joins the check-in that produced it; callers
  /// invalidate the overview rather than using a return value here, and the
  /// two shapes stay one shape each.
  Future<void> checkIn(Map<String, String> answers) async {
    await _api.postJson('/api/v1/recovery/checkin', answers);
  }
}
