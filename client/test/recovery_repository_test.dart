import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/recovery/data/recovery_repository.dart';
import 'package:fitsync/features/recovery/domain/recovery.dart';

RecoveryRepository _repo(MockClient client) => RecoveryRepository(
  ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: client,
  ),
);

void main() {
  test('an empty tab parses as nulls rather than throwing', () async {
    final repo = _repo(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {'todayCheckin': null, 'latestEstimate': null, 'load': []},
          }),
          200,
        ),
      ),
    );

    final overview = await repo.overview();
    expect(overview.todayCheckin, isNull);
    expect(overview.latestEstimate, isNull);
    expect(overview.load, isEmpty);
  });

  test('an estimate carries its date and a ring value', () async {
    final repo = _repo(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'todayCheckin': null,
              'latestEstimate': {
                'riskLevel': 'moderate',
                'trainingLoadScore': 42.5,
                'checkinDate': '2026-09-18',
              },
              'load': [],
            },
          }),
          200,
        ),
      ),
    );

    final estimate = (await repo.overview()).latestEstimate!;
    expect(estimate.riskLevel, 'moderate');
    expect(estimate.trainingLoadScore, 42.5);
    expect(estimate.checkinDate, '2026-09-18');
    expect(estimate.ringValue, greaterThan(0));
    expect(estimate.ringValue, lessThanOrEqualTo(1));
  });

  test('checking in posts the answers verbatim', () async {
    Map<String, dynamic>? sent;
    final repo = _repo(
      MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'data': {
              'checkin': {
                'checkinId': 1,
                'checkinDate': '2026-09-20',
                'sleepQuality': 'poor',
                'muscleSoreness': 'severe',
                'energy': 'low',
                'stress': 'high',
              },
              'estimate': {
                'riskLevel': 'high',
                'trainingLoadScore': 80.0,
                'checkinDate': '2026-09-20',
              },
            },
          }),
          201,
        );
      }),
    );

    final estimate = await repo.checkIn({
      'sleepQuality': 'poor',
      'muscleSoreness': 'severe',
      'energy': 'low',
      'stress': 'high',
    });

    // Verbatim: risk.py looks these up with a defaulting get, so a
    // transformation anywhere on this path scores zero penalty in silence.
    expect(sent!['sleepQuality'], 'poor');
    expect(sent!['muscleSoreness'], 'severe');
    expect(estimate.riskLevel, 'high');
  });
}
