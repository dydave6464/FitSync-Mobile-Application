import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/pro/data/pro_repository.dart';
import 'package:fitsync/features/pro/domain/pro_status.dart';

import 'helpers/fake_pro_repository.dart';

const _prices = {'monthly': 249, 'annual': 1788};
const _free = {
  'pro': false, 'source': null, 'until': null, 'plan': null, 'method': null,
  'endsSoon': false, 'prices': _prices,
};
const _paid = {
  'pro': true, 'source': 'paid', 'until': '2026-11-26T04:00:00.000Z', 'plan': 'annual',
  'method': 'paymaya', 'endsSoon': true, 'prices': _prices,
};

(ProRepository, List<http.Request>) _repo(Object body, {int status = 200}) {
  final requests = <http.Request>[];
  final api = ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: MockClient((request) async {
      requests.add(request);
      return http.Response(jsonEncode({'data': body}), status, headers: {'content-type': 'application/json'});
    }),
  );
  return (ProRepository(api), requests);
}

void main() {
  test('status reads a free account and its prices', () async {
    final (repo, requests) = _repo(_free);
    final s = await repo.status();
    expect(requests.single.url.path, '/api/v1/pro');
    expect(s.pro, isFalse);
    expect(s.source, isNull);
    expect(s.until, isNull);
    expect(s.prices.monthly, 249);
    expect(s.prices.annual, 1788);
    expect(s.prices.forPlan(ProPlan.annual), 1788);
    expect(s.prices.annualPerMonth, 149);
    expect(s.prices.annualSavingPct, 40);
  });

  test('status reads a paid period', () async {
    final (repo, _) = _repo(_paid);
    final s = await repo.status();
    expect(s.pro, isTrue);
    expect(s.source, ProSource.paid);
    expect(s.until, DateTime.utc(2026, 11, 26, 4));
    expect(s.plan, ProPlan.annual);
    expect(s.method, 'paymaya');
    expect(s.endsSoon, isTrue);
  });

  test('checkout sends the plan and returns where to pay', () async {
    final (repo, requests) = _repo({'paymentId': 12, 'checkoutUrl': 'https://checkout.paymongo.com/cs_12'}, status: 201);
    final c = await repo.checkout(ProPlan.monthly);
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v1/pro/checkout');
    expect(jsonDecode(requests.single.body), {'plan': 'monthly'});
    expect(c.paymentId, 12);
    expect(c.checkoutUrl, Uri.parse('https://checkout.paymongo.com/cs_12'));
  });

  test('confirm reads paid or pending, with the new status', () async {
    final (repo, requests) = _repo({'status': 'paid', 'pro': _paid});
    final r = await repo.confirm(12);
    expect(requests.single.url.path, '/api/v1/pro/payments/12/confirm');
    expect(r.state, ProPaymentState.paid);
    expect(r.status.source, ProSource.paid);
    final (pending, _) = _repo({'status': 'pending', 'pro': _free});
    expect((await pending.confirm(12)).state, ProPaymentState.pending);
  });

  test('dates, pesos and payment methods read the way the screen shows them', () {
    final d = DateTime(2026, 11, 26, 12);
    expect(formatProDate(d), '26 Nov 2026');
    expect(formatProDay(d), '26 Nov');
    expect(peso(249), '₱249');
    expect(peso(1788), '₱1,788');
    expect(peso(12345), '₱12,345');
    expect(methodLabel('gcash'), 'GCash');
    expect(methodLabel('paymaya'), 'Maya');
    expect(methodLabel('card'), 'card');
    expect(methodLabel(null), isNull);
    expect(methodLabel('other'), isNull);
  });

  test('the Settings card says how the user is Pro', () {
    expect(proCardSubtitle(null), 'See where your training volume goes');
    expect(proCardSubtitle(freeStatus), 'See where your training volume goes');
    expect(proCardSubtitle(grantedStatus), 'Pro (granted)');
    expect(proCardSubtitle(paidStatus(until: DateTime(2026, 11, 26, 12))), 'Pro until 26 Nov 2026');
    expect(proCardSubtitle(paidStatus(until: DateTime(2026, 11, 26, 12), endsSoon: true)),
        'Pro ends on 26 Nov. Renew to keep Snap a meal and your analytics.');
  });
}
