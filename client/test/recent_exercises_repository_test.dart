import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/exercises/data/recent_exercises_repository.dart';

RecentExercisesRepository repoReturning(
  Object body, {
  void Function(http.Request)? onRequest,
}) {
  final mock = MockClient((request) async {
    onRequest?.call(request);
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return RecentExercisesRepository(
    ApiClient(
      client: mock,
      baseUrl: 'http://test.local',
      tokens: TokenStore(backing: InMemorySecureStore()),
    ),
  );
}

void main() {
  test('asks for the ten most recent and parses them as list rows', () async {
    http.Request? sent;
    final repo = repoReturning({
      'data': {
        'exercises': [
          {
            'exerciseId': 7,
            'name': 'Bench press',
            'muscleGroup': 'pectorals',
            'equipment': 'barbell',
            'thumbnailUrl': '/storage/exercises/0007/thumb.jpg',
            'contraindicated': true,
          },
          {
            'exerciseId': 9,
            'name': 'Plank',
            'muscleGroup': 'abs',
            'equipment': null,
            'thumbnailUrl': null,
          },
        ],
      },
    }, onRequest: (request) => sent = request);

    final recent = await repo.recent();

    expect(sent!.url.path, '/api/v1/exercises/recent');
    expect(sent!.url.queryParameters, {'limit': '10'});
    expect(recent.map((e) => e.name), ['Bench press', 'Plank']);
    expect(recent.first.contraindicated, isTrue);
    expect(recent.last.equipment, isNull);
  });

  test('a body with no exercises reads as none', () async {
    final repo = repoReturning({'data': <String, dynamic>{}});

    expect(await repo.recent(), isEmpty);
  });
}
