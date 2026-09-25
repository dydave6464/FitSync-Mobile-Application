import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart'
    show apiClientProvider;
import 'package:fitsync/features/routine/presentation/providers.dart'
    show routineTodayProvider;
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/recovery/presentation/providers.dart'
    show recoveryOverviewProvider;
import 'package:fitsync/features/streaks/presentation/providers.dart';

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
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(
          baseUrl: 'http://test.local',
          tokens: TokenStore(backing: InMemorySecureStore()),
          client: client,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the controller loads the active session on first read', () async {
    final container = _container(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {'session': _session},
          }),
          200,
        ),
      ),
    );

    final session = await container.read(activeSessionProvider.future);
    expect(session!.sessionId, 7);
  });

  test(
    'logging a set folds the stored set into state without refetching',
    () async {
      var requests = 0;
      final container = _container(
        MockClient((request) async {
          requests++;
          if (request.method == 'PUT') {
            return http.Response(
              jsonEncode({
                'data': {
                  'set': {
                    'exerciseId': 101,
                    'setNumber': 1,
                    'weightKg': 22.5,
                    'reps': 10,
                  },
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': {'session': _session},
            }),
            200,
          );
        }),
      );

      await container.read(activeSessionProvider.future);
      final before = requests;

      await container
          .read(activeSessionProvider.notifier)
          .logSet(exerciseId: 101, setNumber: 1, weightKg: 22.5, reps: 10);

      final session = container.read(activeSessionProvider).value!;
      expect(session.setFor(101, 1)!.weightKg, 22.5);
      // One PUT, and no follow-up GET: the response is the new truth.
      expect(requests, before + 1);
    },
  );

  test('a failed set write leaves state untouched and rethrows', () async {
    final container = _container(
      MockClient((request) async {
        if (request.method == 'PUT') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'WEIGHT_INVALID', 'message': 'too heavy'},
            }),
            400,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {'session': _session},
          }),
          200,
        );
      }),
    );

    await container.read(activeSessionProvider.future);

    await expectLater(
      container
          .read(activeSessionProvider.notifier)
          .logSet(exerciseId: 101, setNumber: 1, weightKg: 5000, reps: 10),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'WEIGHT_INVALID'),
      ),
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
  test(
    'two concurrent logSet calls for different sets both end up in state',
    () async {
      final responses = {
        101: Completer<http.Response>(),
        102: Completer<http.Response>(),
      };
      final container = _container(
        MockClient((request) async {
          if (request.method == 'PUT') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return responses[body['exerciseId'] as int]!.future;
          }
          return http.Response(
            jsonEncode({
              'data': {'session': _session},
            }),
            200,
          );
        }),
      );

      await container.read(activeSessionProvider.future);
      final notifier = container.read(activeSessionProvider.notifier);

      final callA = notifier.logSet(
        exerciseId: 101,
        setNumber: 1,
        weightKg: 20,
        reps: 8,
      );
      final callB = notifier.logSet(
        exerciseId: 102,
        setNumber: 1,
        weightKg: 25,
        reps: 6,
      );

      // Resolve the first-issued call first...
      responses[101]!.complete(
        http.Response(
          jsonEncode({
            'data': {
              'set': {
                'exerciseId': 101,
                'setNumber': 1,
                'weightKg': 20.0,
                'reps': 8,
              },
            },
          }),
          200,
        ),
      );
      await callA;

      // ...then the second-issued call. Its pre-await snapshot was taken
      // before either write happened, so it exposes the race unless the
      // controller re-reads current state after this await too.
      responses[102]!.complete(
        http.Response(
          jsonEncode({
            'data': {
              'set': {
                'exerciseId': 102,
                'setNumber': 1,
                'weightKg': 25.0,
                'reps': 6,
              },
            },
          }),
          200,
        ),
      );
      await callB;

      final session = container.read(activeSessionProvider).value!;
      expect(session.setFor(101, 1)!.weightKg, 20.0);
      expect(session.setFor(102, 1)!.weightKg, 25.0);
    },
  );

  test('un-ticking removes the set from state', () async {
    final withSet = {
      ..._session,
      'sets': [
        {'exerciseId': 101, 'setNumber': 1, 'weightKg': 22.5, 'reps': 10},
      ],
    };
    final container = _container(
      MockClient((request) async {
        if (request.method == 'DELETE') {
          return http.Response(
            jsonEncode({
              'data': {'deleted': true},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {'session': withSet},
          }),
          200,
        );
      }),
    );

    await container.read(activeSessionProvider.future);
    await container
        .read(activeSessionProvider.notifier)
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
    final container = _container(
      MockClient((request) async {
        if (request.method == 'DELETE') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'SET_NOT_FOUND', 'message': 'no such set'},
            }),
            404,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {'session': withSet},
          }),
          200,
        );
      }),
    );

    await container.read(activeSessionProvider.future);

    await expectLater(
      container
          .read(activeSessionProvider.notifier)
          .unlogSet(exerciseId: 101, setNumber: 1),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SET_NOT_FOUND'),
      ),
    );

    // The tick must still be there. A failed delete must not silently untick.
    expect(
      container.read(activeSessionProvider).value!.setFor(101, 1),
      isNotNull,
    );
  });

  test(
    'completing clears the active session and invalidates the week',
    () async {
      var weekCalls = 0;
      final container = _container(
        MockClient((request) async {
          if (request.url.path.endsWith('/complete')) {
            return http.Response(
              jsonEncode({
                'data': {
                  'session': {
                    ..._session,
                    'status': 'completed',
                    'durationMin': 40,
                  },
                },
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
            return http.Response(
              jsonEncode({
                'data': {'dates': dates},
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': {'session': _session},
            }),
            200,
          );
        }),
      );

      await container.read(activeSessionProvider.future);
      // Read completedDaysProvider BEFORE complete() so it already has an
      // element: invalidating a provider with no element yet is a no-op, and
      // without this read the assertion below would pass even if
      // ref.invalidate(completedDaysProvider) were deleted from complete().
      expect(await container.read(completedDaysProvider.future), isEmpty);

      final done = await container
          .read(activeSessionProvider.notifier)
          .complete(40);

      expect(done.status, 'completed');
      // Nothing is in progress any more, so the Plan tab must not offer Resume.
      expect(container.read(activeSessionProvider).value, isNull);
      // This only holds if invalidate() actually forced a refetch -- a cached
      // read would still show the pre-complete empty set.
      expect(await container.read(completedDaysProvider.future), {
        '2026-09-08',
      });
    },
  );

  // Finishing a workout changes what every "what have I done" read answers,
  // and none of those providers is autoDispose -- each one holds whatever it
  // resolved to for the life of the app. On a new account they all resolve
  // EMPTY before the first workout, so without an invalidation the Progress
  // tab keeps saying "No completed workouts yet" over a workout that is
  // stored, until the app is restarted.
  //
  // Each test below reads its provider BEFORE complete(), for the reason the
  // week test above gives: invalidating a provider with no element yet is a
  // no-op, and the assertion would pass on a deleted invalidate().
  group('completing refreshes what reads finished workouts', () {
    /// Answers every read this group makes, counting calls per endpoint so
    /// the second read of a provider is distinguishable from a cached one:
    /// the first call to each answers as a user who has trained nothing,
    /// every later call as one who has just finished session 7.
    ///
    /// Counted per URL rather than per path, because the analytics and
    /// strength endpoints are one path serving a family: keyed on the path
    /// alone, reading 'month' would consume 'week''s first call and be
    /// answered as though a workout had already landed.
    MockClient serverWithOneWorkout() {
      final calls = <String, int>{};
      return MockClient((request) async {
        final path = request.url.path;
        final key = '$path?${request.url.query}';
        final n = calls[key] = (calls[key] ?? 0) + 1;
        final first = n == 1;

        if (path.endsWith('/complete')) {
          return http.Response(
            jsonEncode({
              'data': {
                'session': {
                  ..._session,
                  'status': 'completed',
                  'durationMin': 40,
                },
              },
            }),
            200,
          );
        }
        if (path == '/api/v1/sessions') {
          return http.Response(
            jsonEncode({
              'data': {
                'sessions': first
                    ? []
                    : [
                        {
                          'sessionId': 7,
                          'sessionDate': '2026-09-08',
                          'setCount': 18,
                          'exerciseCount': 6,
                          'durationMin': 40,
                          'totalVolumeKg': 1550,
                          'planName': 'Full Body',
                        },
                      ],
                'total': first ? 0 : 1,
                'page': 1,
                'limit': 20,
              },
            }),
            200,
          );
        }
        if (path.endsWith('/summary')) {
          return http.Response(
            jsonEncode({
              'data': {
                'summary': first
                    ? {'sessionCount': 0, 'setCount': 0, 'totalVolumeKg': 0}
                    : {
                        'sessionCount': 1,
                        'setCount': 18,
                        'totalVolumeKg': 1550,
                      },
              },
            }),
            200,
          );
        }
        if (path.endsWith('/analytics')) {
          return http.Response(
            jsonEncode({
              'data': {
                'period': 'week',
                'volume': [],
                'change': {
                  'totalKg': first ? 0 : 1550,
                  'previousKg': 0,
                  'changePct': null,
                },
                'adherence': {'done': first ? 0 : 1, 'target': 3, 'weeks': 1},
                'muscles': [],
              },
            }),
            200,
          );
        }
        if (path.endsWith('/strength')) {
          return http.Response(
            jsonEncode({
              'data': {
                'exerciseId': first ? null : 101,
                'xAxis': 'date',
                'points': [],
                'options': [],
              },
            }),
            200,
          );
        }
        if (path == '/api/v1/streak') {
          return http.Response(
            jsonEncode({
              'data': {
                'current': first ? 0 : 1,
                'best': first ? 0 : 1,
                'todayActive': !first,
                'week': [],
              },
            }),
            200,
          );
        }
        if (path == '/api/v1/recovery') {
          return http.Response(
            jsonEncode({
              'data': {
                'todayCheckin': null,
                'latestEstimate': null,
                'load': [],
                'muscles': [
                  {
                    'group': 'legs',
                    'lastTrained': first ? null : '2026-09-21',
                    'daysAgo': first ? null : 0,
                  },
                ],
              },
            }),
            200,
          );
        }
        if (path == '/api/v1/routine/today') {
          return http.Response(
            jsonEncode({
              'data': {
                'date': '2026-09-21',
                'habits': [],
                'workout': {'title': 'Plan', 'done': !first},
              },
            }),
            200,
          );
        }
        if (path.endsWith('/last')) {
          return http.Response(
            jsonEncode({
              'data': {
                'session': first
                    ? null
                    : {
                        'sessionId': 7,
                        'sessionDate': '2026-09-08',
                        'planName': 'Full Body',
                        'exercises': [],
                      },
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {'session': _session},
          }),
          200,
        );
      });
    }

    Future<ProviderContainer> completed() async {
      final container = _container(serverWithOneWorkout());
      await container.read(activeSessionProvider.future);
      return container;
    }

    // The one the user sees as "No completed workouts yet" over a workout
    // they just finished.
    test('the history the Progress tab lists', () async {
      final container = await completed();
      expect((await container.read(sessionHistoryProvider.future)).total, 0);

      await container.read(activeSessionProvider.notifier).complete(40);

      final history = await container.read(sessionHistoryProvider.future);
      expect(history.total, 1);
      expect(history.sessions.single.sessionId, 7);
    });

    test('the totals the period segment sums', () async {
      final container = await completed();
      expect(
        (await container.read(trainingSummaryProvider.future)).sessionCount,
        0,
      );

      await container.read(activeSessionProvider.notifier).complete(40);

      expect(
        (await container.read(trainingSummaryProvider.future)).sessionCount,
        1,
      );
    });

    test('the 30-day totals Home shows', () async {
      final container = await completed();
      expect(
        (await container.read(homeSummaryProvider.future)).sessionCount,
        0,
      );

      await container.read(activeSessionProvider.notifier).complete(40);

      expect(
        (await container.read(homeSummaryProvider.future)).sessionCount,
        1,
      );
    });

    // A family: every period the user has looked at is its own element, and
    // all of them are stale once a workout lands. Invalidating the family
    // itself is what reaches the ones not currently on screen.
    test('the analytics cards, for every period already read', () async {
      final container = await completed();
      expect(
        (await container.read(trainingAnalyticsProvider('week').future))
            .adherence
            .done,
        0,
      );
      expect(
        (await container.read(trainingAnalyticsProvider('month').future))
            .adherence
            .done,
        0,
      );

      await container.read(activeSessionProvider.notifier).complete(40);

      expect(
        (await container.read(trainingAnalyticsProvider('week').future))
            .adherence
            .done,
        1,
      );
      expect(
        (await container.read(trainingAnalyticsProvider('month').future))
            .adherence
            .done,
        1,
      );
    });

    // The "+" sheet offers to repeat this, and the workout just finished is
    // the one it should be offering.
    test('the workout the repeat sheet offers', () async {
      final container = await completed();
      expect(await container.read(lastWorkoutProvider.future), isNull);

      await container.read(activeSessionProvider.notifier).complete(40);

      expect((await container.read(lastWorkoutProvider.future))!.sessionId, 7);
    });

    // The routine screen's automatic workout item, and Home's card that
    // shares the same provider.
    test("the routine's workout item", () async {
      final container = await completed();
      expect(
        (await container.read(routineTodayProvider.future)).workout!.done,
        isFalse,
      );

      await container.read(activeSessionProvider.notifier).complete(40);

      expect(
        (await container.read(routineTodayProvider.future)).workout!.done,
        isTrue,
      );
    });

    // Recovery's "last trained" card and its 7-day load.
    test('the recovery overview', () async {
      final container = await completed();
      expect(
        (await container.read(recoveryOverviewProvider.future))
            .muscles
            .single
            .daysAgo,
        isNull,
      );

      await container.read(activeSessionProvider.notifier).complete(40);

      expect(
        (await container.read(recoveryOverviewProvider.future))
            .muscles
            .single
            .daysAgo,
        0,
      );
    });

    // A finished workout is a streak day.
    test('the streak', () async {
      final container = await completed();
      expect((await container.read(streakProvider.future)).current, 0);

      await container.read(activeSessionProvider.notifier).complete(40);

      expect((await container.read(streakProvider.future)).current, 1);
    });
  });

  test('starting stores the new session', () async {
    final container = _container(
      MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'data': {'session': _session},
            }),
            201,
          );
        }
        return http.Response(
          jsonEncode({
            'data': {'session': null},
          }),
          200,
        );
      }),
    );

    await container.read(activeSessionProvider.future);
    expect(container.read(activeSessionProvider).value, isNull);

    await container.read(activeSessionProvider.notifier).start();
    expect(container.read(activeSessionProvider).value!.sessionId, 7);
  });

  // Beyond the brief: abandon() has no coverage otherwise, and Task 12's
  // Discard flow depends on it clearing state exactly like complete() does.
  test(
    'abandoning clears the active session so the Plan tab offers Start',
    () async {
      late String method;
      late String path;
      final container = _container(
        MockClient((request) async {
          if (request.url.path.endsWith('/abandon')) {
            method = request.method;
            path = request.url.path;
            return http.Response(
              jsonEncode({
                'data': {'abandoned': true},
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'data': {'session': _session},
            }),
            200,
          );
        }),
      );

      await container.read(activeSessionProvider.future);
      await container.read(activeSessionProvider.notifier).abandon();

      expect(method, 'POST');
      expect(path, '/api/v1/sessions/7/abandon');
      // Nothing is in progress any more, so the Plan tab must not offer Resume.
      expect(container.read(activeSessionProvider).value, isNull);
    },
  );

  // Beyond the brief: lastPerformanceKey is the fix for the identity-
  // comparison problem (a List<int> family key would miss the cache on every
  // rebuild). If it silently stopped sorting, two orderings of the same plan
  // would become two cache entries and two requests with nothing to reveal it.

  test('lastPerformanceKey sorts, so two orderings of the same plan match', () {
    expect(
      lastPerformanceKey([103, 101, 102]),
      lastPerformanceKey([101, 102, 103]),
    );
  });

  test(
    'lastPerformanceKey sorts a copy, leaving the original list unchanged',
    () {
      final ids = [103, 101, 102];

      lastPerformanceKey(ids);

      expect(ids, [103, 101, 102]);
    },
  );

  test('lastPerformanceKey of an empty list is handled without hitting the network', () async {
    var called = false;
    final container = _container(
      MockClient((_) async {
        called = true;
        return http.Response(
          jsonEncode({
            'data': {'performances': []},
          }),
          200,
        );
      }),
    );

    final result = await container.read(
      lastPerformanceProvider(lastPerformanceKey(const [])).future,
    );

    expect(result, isEmpty);
    expect(called, isFalse);
  });
}
