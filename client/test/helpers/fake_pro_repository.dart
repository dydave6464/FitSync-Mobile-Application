import 'package:fitsync/features/pro/data/pro_repository.dart';
import 'package:fitsync/features/pro/domain/pro_status.dart';

const testPrices = ProPrices(monthly: 249, annual: 1788);

const freeStatus = ProStatus(
  pro: false,
  source: null,
  until: null,
  plan: null,
  method: null,
  endsSoon: false,
  prices: testPrices,
);

const grantedStatus = ProStatus(
  pro: true,
  source: ProSource.granted,
  until: null,
  plan: null,
  method: null,
  endsSoon: false,
  prices: testPrices,
);

ProStatus paidStatus({
  DateTime? until,
  ProPlan plan = ProPlan.monthly,
  String? method = 'gcash',
  bool endsSoon = false,
}) => ProStatus(
  pro: true,
  source: ProSource.paid,
  until: until ?? DateTime(2026, 11, 26, 12),
  plan: plan,
  method: method,
  endsSoon: endsSoon,
  prices: testPrices,
);

/// Answers the Pro calls without a server. Records checkouts and confirms;
/// [confirmAnswers] are handed out in order, then "pending" for ever.
class FakeProRepository implements ProRepository {
  FakeProRepository([this.statusValue = freeStatus]);

  ProStatus statusValue;
  Object? statusError;

  final List<ProPlan> checkouts = [];
  ProCheckout checkoutValue = ProCheckout(
    paymentId: 7,
    checkoutUrl: Uri.parse('https://checkout.example/cs_7'),
  );
  Object? checkoutError;

  final List<int> confirms = [];
  final List<ProConfirmation> confirmAnswers = [];
  Object? confirmError;

  @override
  Future<ProStatus> status() async {
    if (statusError != null) throw statusError!;
    return statusValue;
  }

  @override
  Future<ProCheckout> checkout(ProPlan plan) async {
    checkouts.add(plan);
    if (checkoutError != null) throw checkoutError!;
    return checkoutValue;
  }

  @override
  Future<ProConfirmation> confirm(int paymentId) async {
    confirms.add(paymentId);
    if (confirmError != null) throw confirmError!;
    if (confirmAnswers.isNotEmpty) return confirmAnswers.removeAt(0);
    return ProConfirmation(state: ProPaymentState.pending, status: statusValue);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
