import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart' show apiClientProvider;
import 'package:fitsync/features/sessions/presentation/providers.dart';

const _session = {
  'sessionId': 7,
  'planId': 42,
  'status': 'in_progress',
  'sessionDate': '2026-09-08',
  'startedAt': '2026-09-08T09:15:00.000Z',
  'durationMin': null,
  'totalVolumeKg': null,
  'sets': <Map<String, dynamic>>[],
};

ProviderContainer _container(MockClient client) {
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(ApiClient(
      baseUrl: 'http://test.local',
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: client,
    )),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the controller loads the active session on first read', () async {
    final container = _container(MockClient((_) async =>
        http.Response(jsonEncode({'data': {'session': _session}}), 200)));

    final session = await container.read(activeSessionProvider.future);
    expect(session!.sessionId, 7);
  });

  test('logging a set folds the stored set into state without refetching', () async {
    var requests = 0;
    final container = _container(MockClient((request) async {
      requests++;
      if (request.method == 'PUT') {
        return http.Response(
          jsonEncode({
            'data': {'set': {'exerciseId': 101, 'setNumber': 1, 'weightKg': 22.5, 'reps': 10}},
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'data': {'session': _session}}), 200);
    }));

    await container.read(activeSessionProvider.future);
    final before = requests;

    await container.read(activeSessionProvider.notifier)
        .logSet(exerciseId: 101, setNumber: 1, weightKg: 22.5, reps: 10);

    final session = container.read(activeSessionProvider).value!;
    expect(session.setFor(101, 1)!.weightKg, 22.5);
    // One PUT, and no follow-up GET: the response is the new truth.
    expect(requests, before + 1);
  });

  test('a failed set write leaves state untouched and rethrows', () async {
    final container = _container(MockClient((request) async {
      if (request.method == 'PUT') {
        return http.Response(
          jsonEncode({'error': {'code': 'WEIGHT_INVALID', 'message': 'too heavy'}}),
          400,
        );
      }
      return http.Response(jsonEncode({'data': {'session': _session}}), 200);
    }));

    await container.read(activeSessionProvider.future);

    await expectLater(
      container.read(activeSessionProvider.notifier)
          .logSet(exerciseId: 101, setNumber: 1, weightKg: 5000, reps: 10),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'WEIGHT_INVALID')),
    );

    // The tick must not appear. A visible tick means a stored set.
    expect(container.read(activeSessionProvider).value!.sets, isEmpty);
  });

  test('un-ticking removes the set from state', () async {
    final withSet = {
      ..._session,
      'sets': [
        {'exerciseId': 101, 'setNumber': 1, 'weightKg': 22.5, 'reps': 10},
      ],
    };
    final container = _container(MockClient((request) async {
      if (request.method == 'DELETE') {
        return http.Response(jsonEncode({'data': {'deleted': true}}), 200);
      }
      return http.Response(jsonEncode({'data': {'session': withSet}}), 200);
    }));

    await container.read(activeSessionProvider.future);
    await container.read(activeSessionProvider.notifier)
        .unlogSet(exerciseId: 101, setNumber: 1);

    expect(container.read(activeSessionProvider).value!.sets, isEmpty);
  });

  test('completing clears the active session and invalidates the week', () async {
    final container = _container(MockClient((request) async {
      if (request.url.path.endsWith('/complete')) {
        return http.Response(
          jsonEncode({
            'data': {'session': {..._session, 'status': 'completed', 'durationMin': 40}},
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/week')) {
        return http.Response(jsonEncode({'data': {'dates': ['2026-09-08']}}), 200);
      }
      return http.Response(jsonEncode({'data': {'session': _session}}), 200);
    }));

    await container.read(activeSessionProvider.future);
    final done = await container.read(activeSessionProvider.notifier).complete(40);

    expect(done.status, 'completed');
    // Nothing is in progress any more, so the Plan tab must not offer Resume.
    expect(container.read(activeSessionProvider).value, isNull);
    expect(await container.read(completedDaysProvider.future), {'2026-09-08'});
  });

  test('starting stores the new session', () async {
    final container = _container(MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(jsonEncode({'data': {'session': _session}}), 201);
      }
      return http.Response(jsonEncode({'data': {'session': null}}), 200);
    }));

    await container.read(activeSessionProvider.future);
    expect(container.read(activeSessionProvider).value, isNull);

    await container.read(activeSessionProvider.notifier).start();
    expect(container.read(activeSessionProvider).value!.sessionId, 7);
  });

  // Beyond the brief: abandon() has no coverage otherwise, and Task 12's
  // Discard flow depends on it clearing state exactly like complete() does.
  test('abandoning clears the active session so the Plan tab offers Start', () async {
    late String method;
    late String path;
    final container = _container(MockClient((request) async {
      if (request.url.path.endsWith('/abandon')) {
        method = request.method;
        path = request.url.path;
        return http.Response(jsonEncode({'data': {'abandoned': true}}), 200);
      }
      return http.Response(jsonEncode({'data': {'session': _session}}), 200);
    }));

    await container.read(activeSessionProvider.future);
    await container.read(activeSessionProvider.notifier).abandon();

    expect(method, 'POST');
    expect(path, '/api/v1/sessions/7/abandon');
    // Nothing is in progress any more, so the Plan tab must not offer Resume.
    expect(container.read(activeSessionProvider).value, isNull);
  });

  // Beyond the brief: lastPerformanceKey is the fix for the identity-
  // comparison problem (a List<int> family key would miss the cache on every
  // rebuild). If it silently stopped sorting, two orderings of the same plan
  // would become two cache entries and two requests with nothing to reveal it.

  test('lastPerformanceKey sorts, so two orderings of the same plan match', () {
    expect(lastPerformanceKey([103, 101, 102]), lastPerformanceKey([101, 102, 103]));
  });

  test('lastPerformanceKey of an empty list is handled without hitting the network', () async {
    var called = false;
    final container = _container(MockClient((_) async {
      called = true;
      return http.Response(jsonEncode({'data': {'performances': []}}), 200);
    }));

    final result = await container.read(lastPerformanceProvider(lastPerformanceKey(const [])).future);

    expect(result, isEmpty);
    expect(called, isFalse);
  });
}
