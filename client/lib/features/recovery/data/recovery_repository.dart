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
  /// Returns the server's checked copy of the ML service's answer
  /// (`toEstimate` in server/src/routes/recovery.js), dated by the check-in
  /// that produced it, or null when no estimate came back (the ML service
  /// was down, or its answer was refused). An older server sent the
  /// estimate without `checkinDate`; an [InjuryRiskEstimate] is dated, so
  /// that one is null too rather than a parse failure that would report a
  /// saved check-in as failed. Callers still invalidate the overview, which
  /// also carries today's check-in, the load and the muscles.
  Future<InjuryRiskEstimate?> checkIn(Map<String, String> answers) async {
    final data = await _api.postJson('/api/v1/recovery/checkin', answers);
    return _datedEstimate(data['estimate']);
  }

  /// Works out today's estimate again from the check-in already saved,
  /// without sending the answers again. The server answers with the
  /// estimate it already has when today's is there, so a double tap stores
  /// nothing twice. Throws NO_CHECKIN_TODAY when there is no check-in for
  /// today (the day rolled over), and ESTIMATE_UNAVAILABLE when the ML
  /// service still cannot answer.
  Future<InjuryRiskEstimate> retryEstimate() async {
    final data = await _api.postJson('/api/v1/recovery/estimate', const {});
    return InjuryRiskEstimate.fromJson(
      data['estimate'] as Map<String, dynamic>,
    );
  }
}

InjuryRiskEstimate? _datedEstimate(Object? raw) =>
    raw is Map<String, dynamic> && raw['checkinDate'] is String
    ? InjuryRiskEstimate.fromJson(raw)
    : null;
