import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/health/data/health_repository.dart';
import 'package:fitsync/features/health/domain/health_answers.dart';

HealthRepository _repo(MockClient client) => HealthRepository(
  ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: client,
  ),
);

http.Response _health(Map<String, dynamic>? health) =>
    http.Response(jsonEncode({'data': {'health': health}}), 200);

const _stored = {
  'conditions': ['asthma'],
  'chestPain': false,
  'dizziness': false,
  'supervisedOnly': false,
  'consentedAt': '2026-10-07T01:00:00.000Z',
  'acknowledgedAt': '2026-10-07T01:00:00.000Z',
};

void main() {
  test('getHealth() reads null when nothing is stored', () async {
    final repo = _repo(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/profile/health');
      return _health(null);
    }));
    expect(await repo.getHealth(), isNull);
  });

  test('getHealth() reads a stored check', () async {
    final repo = _repo(MockClient((request) async => _health(_stored)));
    final health = await repo.getHealth();
    expect(health!.conditions, ['asthma']);
    expect(health.consent, isTrue);
  });

  test('setHealth() PUTs the answers and reads back what was stored', () async {
    final answers = const HealthAnswers()
        .toggle('asthma')
        .answer('chestPain', false)
        .answer('dizziness', false)
        .answer('supervisedOnly', false)
        .withAcknowledged(true)
        .withConsent(true);
    final repo = _repo(MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/profile/health');
      expect(jsonDecode(request.body), answers.toJson());
      return _health(_stored);
    }));
    expect((await repo.setHealth(answers))!.conditions, ['asthma']);
  });

  test('deleteHealth() sends DELETE', () async {
    var called = false;
    final repo = _repo(MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/api/v1/profile/health');
      called = true;
      return _health(null);
    }));
    await repo.deleteHealth();
    expect(called, isTrue);
  });
}
