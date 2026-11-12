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
  'pro': false,
  'source': null,
  'until': null,
  'plan': null,
  'method': null,
  'endsSoon': false,
  'prices': _prices,
};
const _paid = {
  'pro': true,
  'source': 'paid',
  'until': '2026-11-26T04:00:00.000Z',
  'plan': 'annual',
  'method': 'paymaya',
  'endsSoon': true,
  'prices': _prices,
};

(ProRepository, List<http.Request>) _repo(Object body, {int status = 200}) {
  final requests = <http.Request>[];
  final api = ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({'data': body}),
        status,
        headers: {'content-type': 'application/json'},
      );
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

  // #31: the server states each plan's terms; the app reads them rather
  // than inferring months and "no renewal" itself.
  test('status reads the plans, renews and nextPeriodStartsAt', () async {
    final (repo, _) = _repo({
      ..._paid,
      'plans': {
        'monthly': {'pricePhp': 299, 'months': 3},
        'annual': {'pricePhp': 1788, 'months': 12},
      },
      'renews': false,
      'nextPeriodStartsAt': '2026-12-01T04:00:00.000Z',
    });
    final s = await repo.status();
    expect(s.plans[ProPlan.monthly]?.months, 3);
    expect(s.plans[ProPlan.monthly]?.pricePhp, 299);
    expect(s.plans[ProPlan.annual]?.months, 12);
    expect(s.plans[ProPlan.annual]?.pricePhp, 1788);
    // The prices follow the plans: 299, not the 249 still sent in prices.
    expect(s.prices.monthly, 299);
    expect(s.prices.annual, 1788);
    expect(s.renews, isFalse);
    expect(s.nextPeriodStartsAt, DateTime.utc(2026, 12, 1, 4));
  });

  test('an older server without plans: prices and the usual months', () async {
    final (repo, _) = _repo(_free);
    final s = await repo.status();
    expect(s.plans[ProPlan.monthly]?.pricePhp, 249);
    expect(s.plans[ProPlan.monthly]?.months, 1);
    expect(s.plans[ProPlan.annual]?.pricePhp, 1788);
    expect(s.plans[ProPlan.annual]?.months, 12);
    expect(s.renews, isFalse);
    expect(s.nextPeriodStartsAt, isNull);
  });

  test('a renewing plan is read as one', () async {
    final (repo, _) = _repo({..._free, 'renews': true});
    expect((await repo.status()).renews, isTrue);
  });

  test('checkout sends the plan and returns where to pay', () async {
    final (repo, requests) = _repo({
      'paymentId': 12,
      'checkoutUrl': 'https://checkout.paymongo.com/cs_12',
    }, status: 201);
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

  test(
    'dates, pesos and payment methods read the way the screen shows them',
    () {
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
    },
  );

  test('the Settings card says how the user is Pro', () {
    // PS-14: what Pro unlocks, not only the analytics.
    const free = 'Muscle analytics, Snap a meal, unlimited AI cues';
    expect(proCardSubtitle(null), free);
    expect(proCardSubtitle(freeStatus), free);
    // PS-14: no status yet (still loading, or a failed read) for an account
    // the profile already says is Pro is not sold Pro again.
    expect(proCardSubtitle(null, premium: true), 'Pro');
    expect(proCardSubtitle(freeStatus, premium: true), free);
    expect(proCardSubtitle(grantedStatus), 'Pro (granted)');
    expect(
      proCardSubtitle(paidStatus(until: DateTime(2026, 11, 26, 12))),
      'Pro until 26 Nov 2026',
    );
    expect(
      proCardSubtitle(
        paidStatus(until: DateTime(2026, 11, 26, 12), endsSoon: true),
      ),
      'Pro ends on 26 Nov. Renew to keep Snap a meal and your analytics.',
    );
  });
}
