import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/session_detail.dart';

SessionRepository _repo(MockClient client) => SessionRepository(
  ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: client,
  ),
);

/// GET /api/v1/sessions/:sessionId's session, as the contract writes it.
const _detailJson = {
  'sessionId': 41,
  'sessionDate': '2026-11-04',
  'startedAt': '2026-11-04T09:12:00.000Z',
  'durationMin': 52,
  'totalVolumeKg': 2953.5,
  'setCount': 12,
  'planName': null,
  'planDayNo': null,
  'muscleGroups': ['pectorals', 'pectorals', 'lats'],
  'exercises': [
    {
      'exerciseId': 12,
      'name': 'Barbell Bench Press',
      'muscleGroup': 'chest',
      'equipment': 'Barbell',
      'thumbnailUrl': '/storage/exercises/0012/thumb.jpg',
      'volumeKg': 1440,
      'sets': [
        {'setNumber': 1, 'weightKg': 60, 'reps': 8},
        {'setNumber': 2, 'weightKg': null, 'reps': 12},
      ],
    },
  ],
};

void main() {
  group('SessionDetail.fromJson', () {
    test('reads the session, its exercises and their sets', () {
      final detail = SessionDetail.fromJson(_detailJson);

      expect(detail.sessionId, 41);
      expect(detail.sessionDate, '2026-11-04');
      expect(detail.startedAt, DateTime.utc(2026, 11, 4, 9, 12));
      expect(detail.durationMin, 52);
      expect(detail.totalVolumeKg, 2953.5);
      expect(detail.setCount, 12);
      expect(detail.planName, isNull);
      expect(detail.planDayNo, isNull);
      expect(detail.muscleGroups, ['pectorals', 'pectorals', 'lats']);
      // Named exactly as its History row is.
      expect(detail.title, 'Chest & Back workout');

      final bench = detail.exercises.single;
      expect(bench.exerciseId, 12);
      expect(bench.name, 'Barbell Bench Press');
      expect(bench.muscleGroup, 'chest');
      expect(bench.equipment, 'Barbell');
      expect(bench.thumbnailUrl, '/storage/exercises/0012/thumb.jpg');
      expect(bench.volumeKg, 1440.0);
      expect(bench.sets.first.setNumber, 1);
      expect(bench.sets.first.weightKg, 60.0);
      expect(bench.sets.first.reps, 8);
      expect(bench.sets.last.weightKg, isNull);
      expect(bench.sets.last.reps, 12);
    });

    test('a plan session is titled by its plan', () {
      final detail = SessionDetail.fromJson({
        ..._detailJson,
        'planName': 'Push Pull Legs',
        'planDayNo': 2,
        'muscleGroups': <String>[],
      });

      expect(detail.title, 'Push Pull Legs');
      expect(detail.planDayNo, 2);
    });

    test('null volume, null duration and missing muscle groups', () {
      final detail = SessionDetail.fromJson({
        'sessionId': 9,
        'sessionDate': '2026-11-01',
        'startedAt': null,
        'durationMin': null,
        'totalVolumeKg': null,
        'setCount': 3,
        'planName': null,
        'exercises': [
          {
            'exerciseId': 3,
            'name': 'pull-up',
            'muscleGroup': 'back',
            'equipment': null,
            'thumbnailUrl': null,
            'volumeKg': null,
            'sets': [
              {'setNumber': 1, 'weightKg': null, 'reps': 10},
            ],
          },
        ],
      });

      expect(detail.durationMin, isNull);
      expect(detail.totalVolumeKg, isNull);
      expect(detail.startedAt, isNull);
      expect(detail.muscleGroups, isEmpty);
      expect(detail.title, 'Your own workout');
      expect(detail.exercises.single.volumeKg, isNull);
      expect(detail.exercises.single.equipment, isNull);
    });

    test('a session with no sets has no exercises', () {
      final detail = SessionDetail.fromJson({
        ..._detailJson,
        'setCount': 0,
        'exercises': <Object>[],
      });

      expect(detail.exercises, isEmpty);
    });
  });

  group('SessionRepository.detail', () {
    test(
      'asks for the one session and reads a whole weight as a double',
      () async {
        late Uri asked;
        final repo = _repo(
          MockClient((request) async {
            asked = request.url;
            return http.Response(
              jsonEncode({
                'data': {'session': _detailJson},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final detail = await repo.detail(41);

        expect(asked.path, '/api/v1/sessions/41');
        expect(detail.sessionId, 41);
        final weight = detail.exercises.single.sets.first.weightKg;
        expect(weight, isA<double>());
        expect(weight, 60.0);
      },
    );
  });
}
