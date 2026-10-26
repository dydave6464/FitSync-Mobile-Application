import '../../../core/api_client.dart';
import '../domain/pro_status.dart';

/// Buying Pro: the account's status, a checkout, and "was it paid?". The
/// server talks to PayMongo; the app never sees a key or a card.
class ProRepository {
  ProRepository(this._api);

  final ApiClient _api;

  /// The server waits up to 15 s for PayMongo; this leaves room for the trip.
  static const paymentTimeout = Duration(seconds: 20);

  Future<ProStatus> status() async =>
      ProStatus.fromJson(await _api.getJson('/api/v1/pro'));

  Future<ProCheckout> checkout(ProPlan plan) async => ProCheckout.fromJson(
    await _api.postJson('/api/v1/pro/checkout', {
      'plan': plan.wire,
    }, timeout: paymentTimeout),
  );

  Future<ProConfirmation> confirm(int paymentId) async =>
      ProConfirmation.fromJson(
        await _api.postJson(
          '/api/v1/pro/payments/$paymentId/confirm',
          const {},
          timeout: paymentTimeout,
        ),
      );
}
