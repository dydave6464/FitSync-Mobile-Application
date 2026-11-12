import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/recovery/data/recovery_repository.dart';

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

  test('muscle groups arrive in the order sent, with their dates', () async {
    final repo = _repo(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'todayCheckin': null,
              'latestEstimate': null,
              'load': [],
              'muscles': [
                {'group': 'chest', 'lastTrained': null, 'daysAgo': null},
                {'group': 'legs', 'lastTrained': '2026-09-20', 'daysAgo': 5},
              ],
            },
          }),
          200,
        ),
      ),
    );

    final muscles = (await repo.overview()).muscles;
    expect(muscles.map((m) => m.group), ['chest', 'legs']);
    expect(muscles.first.daysAgo, isNull);
    expect(muscles.last.lastTrained, '2026-09-20');
    expect(muscles.last.daysAgo, 5);
  });

  test('an older server without muscles parses as none', () async {
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

    expect((await repo.overview()).muscles, isEmpty);
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

  test('a newer estimate brings its source, load and drivers', () async {
    final repo = _repo(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'todayCheckin': null,
              'latestEstimate': {
                'riskLevel': 'moderate',
                'trainingLoadScore': 47.25,
                'checkinDate': '2026-10-18',
                'source': 'rules',
                'loadPct': 35.0,
                'drivers': [
                  {'key': 'load', 'value': 35.0},
                ],
              },
              'load': [],
            },
          }),
          200,
        ),
      ),
    );

    final estimate = (await repo.overview()).latestEstimate!;
    expect(estimate.source, 'rules');
    expect(estimate.loadPct, 35.0);
    expect(estimate.drivers!.single.key, 'load');
  });

  test('checking in posts all four answers verbatim', () async {
    Map<String, dynamic>? sent;
    final repo = _repo(
      MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_checkinResponse), 201);
      }),
    );

    await repo.checkIn(_answers);

    // Verbatim, and all four: risk.py looks each of these up with a
    // defaulting get, so a transformation anywhere on this path scores zero
    // penalty in silence rather than raising. Two asserted fields left the
    // other two free to be reshaped without a test noticing.
    expect(sent!['sleepQuality'], 'poor');
    expect(sent!['muscleSoreness'], 'severe');
    expect(sent!['energy'], 'low');
    expect(sent!['stress'], 'high');
    expect(sent!.keys.length, 4);
  });

  test('a check-in from an older server, with an undated estimate, '
      'returns no estimate rather than throwing', () async {
    final repo = _repo(
      MockClient((_) async => http.Response(jsonEncode(_checkinResponse), 201)),
    );

    // An older server answered with the estimate but no checkinDate.
    // Parsing an InjuryRiskEstimate out of it throws on `null as String`,
    // which would mean every successful check-in reports failure to the
    // user and never refreshes the tab.
    expect(await repo.checkIn(_answers), isNull);
  });

  test('a check-in returns the dated estimate the server sends', () async {
    final repo = _repo(
      MockClient(
        (_) async => http.Response(jsonEncode(_datedCheckinResponse), 201),
      ),
    );

    final estimate = (await repo.checkIn(_answers))!;
    expect(estimate.riskLevel, 'high');
    expect(estimate.trainingLoadScore, 80.0);
    expect(estimate.checkinDate, '2026-09-20');
    expect(estimate.source, 'model');
    expect(estimate.drivers!.single.key, 'sleep');
  });

  test(
    'a check-in saved while the ML service was down returns no estimate',
    () async {
      final repo = _repo(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': {
                'checkin': _datedCheckinResponse['data']!['checkin'],
                'estimate': null,
              },
            }),
            201,
          ),
        ),
      );

      expect(await repo.checkIn(_answers), isNull);
    },
  );

  test(
    'retrying the estimate POSTs to /estimate and parses a dated one',
    () async {
      late http.Request seen;
      final repo = _repo(
        MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'data': {
                'estimate': {
                  'riskLevel': 'moderate',
                  'trainingLoadScore': 47.25,
                  'checkinDate': '2026-10-18',
                  'source': 'rules',
                  'modelVersion': null,
                  'loadPct': 35.0,
                  'drivers': [
                    {'key': 'load', 'value': 35.0},
                  ],
                },
              },
            }),
            201,
          );
        }),
      );

      final estimate = await repo.retryEstimate();

      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/recovery/estimate');
      expect(estimate.riskLevel, 'moderate');
      expect(estimate.checkinDate, '2026-10-18');
      expect(estimate.loadPct, 35.0);
      expect(estimate.drivers!.single.key, 'load');
    },
  );
}

const _answers = {
  'sleepQuality': 'poor',
  'muscleSoreness': 'severe',
  'energy': 'low',
  'stress': 'high',
};

/// What an older server's POST /api/v1/recovery/checkin answered: the stored
/// check-in, and the estimate without its date.
const _checkinResponse = {
  'data': {
    'checkin': {
      'checkinId': 1,
      'checkinDate': '2026-09-20',
      'sleepQuality': 'poor',
      'muscleSoreness': 'severe',
      'energy': 'low',
      'stress': 'high',
    },
    'estimate': {'riskLevel': 'high', 'trainingLoadScore': 80.0},
  },
};

/// What POST /api/v1/recovery/checkin answers now: the estimate carries the
/// check-in's date.
const _datedCheckinResponse = {
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
      'source': 'model',
      'modelVersion': 'v3',
      'loadPct': 50.0,
      'drivers': [
        {'key': 'sleep', 'value': 'poor'},
      ],
    },
  },
};
