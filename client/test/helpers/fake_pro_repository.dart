import 'dart:async';

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
/// [confirmAnswers] are handed out in order, then "pending" for ever. A set
/// [confirmGate] holds each confirm's answer until it completes; a set
/// [statusGate] does the same for each status read.
class FakeProRepository implements ProRepository {
  FakeProRepository([this.statusValue = freeStatus]);

  ProStatus statusValue;
  Object? statusError;
  int statusCalls = 0;
  Completer<void>? statusGate;

  final List<ProPlan> checkouts = [];
  ProCheckout checkoutValue = ProCheckout(
    paymentId: 7,
    checkoutUrl: Uri.parse('https://checkout.example/cs_7'),
  );
  Object? checkoutError;

  final List<int> confirms = [];
  final List<ProConfirmation> confirmAnswers = [];
  Object? confirmError;
  Completer<void>? confirmGate;

  @override
  Future<ProStatus> status() async {
    statusCalls += 1;
    final gate = statusGate;
    if (gate != null) await gate.future;
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
    final gate = confirmGate;
    if (gate != null) await gate.future;
    if (confirmError != null) throw confirmError!;
    if (confirmAnswers.isNotEmpty) return confirmAnswers.removeAt(0);
    return ProConfirmation(state: ProPaymentState.pending, status: statusValue);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
