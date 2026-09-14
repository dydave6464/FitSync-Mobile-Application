import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';

ExerciseRepository repoReturning(Object body, {void Function(http.Request)? onRequest}) {
  final mock = MockClient((request) async {
    onRequest?.call(request);
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  });
  // An in-memory token store, because the real one reaches a platform channel
  // that has no binding under `flutter test`.
  return ExerciseRepository(ApiClient(
    client: mock,
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
  ));
}

void main() {
  test('parses a page of exercises', () async {
    final repo = repoReturning({
      'data': {
        'exercises': [
          {
            'exerciseId': 1,
            'name': '3/4 sit-up',
            'muscleGroup': 'abs',
            'equipment': 'body weight',
            'thumbnailUrl': '/storage/exercises/0001/thumb.jpg',
          }
        ],
        'page': 1,
        'limit': 20,
        'total': 1203,
      }
    });

    final page = await repo.list();
    expect(page.total, 1203);
    expect(page.items.single.name, '3/4 sit-up');
    expect(page.items.single.muscleGroup, 'abs');
    expect(page.items.single.thumbnailUrl, '/storage/exercises/0001/thumb.jpg');
  });

  test('sends filters and pagination as query parameters', () async {
    Uri? seen;
    final repo = repoReturning(
      {'data': {'exercises': [], 'page': 2, 'limit': 20, 'total': 0}},
      onRequest: (r) => seen = r.url,
    );

    await repo.list(muscleGroups: const ['biceps'], equipment: 'dumbbell', page: 2);

    expect(seen!.path, '/api/v1/exercises');
    expect(seen!.queryParameters['muscleGroup'], 'biceps');
    expect(seen!.queryParameters['equipment'], 'dumbbell');
    expect(seen!.queryParameters['page'], '2');
  });

  test('sends a search term as a query parameter', () async {
    Uri? seen;
    final repo = repoReturning(
      {'data': {'exercises': [], 'page': 1, 'limit': 20, 'total': 0}},
      onRequest: (r) => seen = r.url,
    );

    await repo.list(search: 'curl');

    expect(seen!.queryParameters['search'], 'curl');
  });

  test('omits the search key when nothing is being searched for', () async {
    // An absent key and an empty one mean the same thing to the endpoint, but
    // only the absent one keeps the URL honest about what was asked.
    Uri? seen;
    final repo = repoReturning(
      {'data': {'exercises': [], 'page': 1, 'limit': 20, 'total': 0}},
      onRequest: (r) => seen = r.url,
    );

    await repo.list(search: '');

    expect(seen!.queryParameters.containsKey('search'), isFalse);
  });

  test('parses a detail with its cues in order', () async {
    final repo = repoReturning({
      'data': {
        'exerciseId': 1,
        'name': '3/4 sit-up',
        'muscleGroup': 'abs',
        'equipment': 'body weight',
        'thumbnailUrl': '/storage/exercises/0001/thumb.jpg',
        'animationUrl': '/storage/exercises/0001/animation.gif',
        'cues': ['Lie flat.', 'Curl forward.'],
      }
    });

    final detail = await repo.byId(1);
    expect(detail.animationUrl, endsWith('.gif'));
    expect(detail.cues, ['Lie flat.', 'Curl forward.']);
  });

  test('parses filter options with counts', () async {
    final repo = repoReturning({
      'data': {
        'muscleGroups': [{'value': 'abs', 'count': 147}],
        'equipment': [
          {'value': 'body weight', 'label': 'Bodyweight', 'count': 304}
        ],
      }
    });

    final filters = await repo.filters();
    expect(filters.muscleGroups.single.value, 'abs');
    expect(filters.muscleGroups.single.count, 147);
    expect(filters.equipment.single.value, 'body weight');
  });

  test('an equipment option keeps its label apart from its value', () async {
    // The value is the API contract and the label is what the user reads.
    // Folding them together would send 'Bodyweight' to an endpoint that only
    // answers to 'body weight'.
    final repo = repoReturning({
      'data': {
        'muscleGroups': const [],
        'equipment': [
          {'value': 'body weight', 'label': 'Bodyweight', 'count': 304}
        ],
      }
    });

    final option = (await repo.filters()).equipment.single;
    expect(option.value, 'body weight');
    expect(option.label, 'Bodyweight');
  });

  test('an option with no label reads as its own value', () async {
    // Muscle groups never carry one, and neither does a server predating the
    // equipment rollup. Either way the option has to render as something.
    final repo = repoReturning({
      'data': {
        'muscleGroups': [{'value': 'abs', 'count': 147}],
        'equipment': [{'value': 'kettlebell', 'count': 41}],
      }
    });

    final filters = await repo.filters();
    expect(filters.muscleGroups.single.label, 'abs');
    expect(filters.equipment.single.label, 'kettlebell');
  });

  test('tolerates a null equipment on an exercise', () async {
    final repo = repoReturning({
      'data': {
        'exercises': [
          {
            'exerciseId': 9,
            'name': 'Odd one',
            'muscleGroup': 'abs',
            'equipment': null,
            'thumbnailUrl': null,
          }
        ],
        'page': 1, 'limit': 20, 'total': 1,
      }
    });

    final page = await repo.list();
    expect(page.items.single.equipment, isNull);
    expect(page.items.single.thumbnailUrl, isNull);
  });
}
