import 'dart:async';
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

  // Two rows can each have their own in-flight write. If the request issued
  // first happens to resolve first but the request issued second resolves
  // last, a controller that builds new state from a snapshot taken *before*
  // its own await -- rather than re-reading current state *after* it -- lets
  // the later write clobber the earlier one, because that snapshot predates
  // both writes. The completers below pin the resolution order explicitly so
  // the race is deterministic instead of a timing gamble.
  test('two concurrent logSet calls for different sets both end up in state', () async {
    final responses = {
      101: Completer<http.Response>(),
      102: Completer<http.Response>(),
    };
    final container = _container(MockClient((request) async {
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return responses[body['exerciseId'] as int]!.future;
      }
      return http.Response(jsonEncode({'data': {'session': _session}}), 200);
    }));

    await container.read(activeSessionProvider.future);
    final notifier = container.read(activeSessionProvider.notifier);

    final callA = notifier.logSet(exerciseId: 101, setNumber: 1, weightKg: 20, reps: 8);
    final callB = notifier.logSet(exerciseId: 102, setNumber: 1, weightKg: 25, reps: 6);

    // Resolve the first-issued call first...
    responses[101]!.complete(http.Response(
      jsonEncode({
        'data': {'set': {'exerciseId': 101, 'setNumber': 1, 'weightKg': 20.0, 'reps': 8}},
      }),
      200,
    ));
    await callA;

    // ...then the second-issued call. Its pre-await snapshot was taken
    // before either write happened, so it exposes the race unless the
    // controller re-reads current state after this await too.
    responses[102]!.complete(http.Response(
      jsonEncode({
        'data': {'set': {'exerciseId': 102, 'setNumber': 1, 'weightKg': 25.0, 'reps': 6}},
      }),
      200,
    ));
    await callB;

    final session = container.read(activeSessionProvider).value!;
    expect(session.setFor(101, 1)!.weightKg, 20.0);
    expect(session.setFor(102, 1)!.weightKg, 25.0);
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

  test('a failed unlogSet write leaves state untouched and rethrows', () async {
    final withSet = {
      ..._session,
      'sets': [
        {'exerciseId': 101, 'setNumber': 1, 'weightKg': 22.5, 'reps': 10},
      ],
    };
    final container = _container(MockClient((request) async {
      if (request.method == 'DELETE') {
        return http.Response(
          jsonEncode({'error': {'code': 'SET_NOT_FOUND', 'message': 'no such set'}}),
          404,
        );
      }
      return http.Response(jsonEncode({'data': {'session': withSet}}), 200);
    }));

    await container.read(activeSessionProvider.future);

    await expectLater(
      container.read(activeSessionProvider.notifier)
          .unlogSet(exerciseId: 101, setNumber: 1),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SET_NOT_FOUND')),
    );

    // The tick must still be there. A failed delete must not silently untick.
    expect(container.read(activeSessionProvider).value!.setFor(101, 1), isNotNull);
  });

  test('completing clears the active session and invalidates the week', () async {
    var weekCalls = 0;
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
        weekCalls++;
        // Different payload each call, so a second read that actually
        // reaches the network is distinguishable from one served out of a
        // stale cache.
        final dates = weekCalls == 1 ? <String>[] : ['2026-09-08'];
        return http.Response(jsonEncode({'data': {'dates': dates}}), 200);
      }
      return http.Response(jsonEncode({'data': {'session': _session}}), 200);
    }));

    await container.read(activeSessionProvider.future);
    // Read completedDaysProvider BEFORE complete() so it already has an
    // element: invalidating a provider with no element yet is a no-op, and
    // without this read the assertion below would pass even if
    // ref.invalidate(completedDaysProvider) were deleted from complete().
    expect(await container.read(completedDaysProvider.future), isEmpty);

    final done = await container.read(activeSessionProvider.notifier).complete(40);

    expect(done.status, 'completed');
    // Nothing is in progress any more, so the Plan tab must not offer Resume.
    expect(container.read(activeSessionProvider).value, isNull);
    // This only holds if invalidate() actually forced a refetch -- a cached
    // read would still show the pre-complete empty set.
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

  test('lastPerformanceKey sorts a copy, leaving the original list unchanged', () {
    final ids = [103, 101, 102];

    lastPerformanceKey(ids);

    expect(ids, [103, 101, 102]);
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
