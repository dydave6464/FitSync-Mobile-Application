import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/profile.dart';

const _fullProfileJson = {
  'userId': 7,
  'email': 'juan@example.com',
  'fullName': 'Juan Dela Cruz',
  'onboardingCompleted': true,
  'isPremium': false,
  'sex': 'male',
  'dateOfBirth': '1999-04-17',
  'heightCm': 172.5,
  'weightKg': 68.4,
  'goalWeightKg': 64.0,
  'mainGoal': 'lose_weight',
  'fitnessLevel': 'beginner',
  'activityLevel': 'moderate',
  'trainingLocation': 'home_gym',
  'city': 'Cebu City',
  'notificationsEnabled': true,
  'equipment': [
    {'equipmentId': 3, 'name': 'Dumbbells'},
  ],
  'injuries': [
    {'injuryId': 5, 'side': 'left'},
  ],
};

/// A profile for a user who has just registered: every optional column is
/// still null. This is the state onboarding starts from, so it is the common
/// case rather than an edge case.
const _emptyProfileJson = {
  'userId': 7,
  'email': 'juan@example.com',
  'fullName': 'Juan Dela Cruz',
  'onboardingCompleted': false,
  'isPremium': false,
  'sex': null,
  'dateOfBirth': null,
  'heightCm': null,
  'weightKg': null,
  'goalWeightKg': null,
  'mainGoal': null,
  'fitnessLevel': null,
  'activityLevel': null,
  'trainingLocation': null,
  'city': null,
  'notificationsEnabled': true,
  'equipment': <Object>[],
  'injuries': <Object>[],
};

class _Captured {
  final List<http.Request> requests = [];
}

(ProfileRepository, _Captured) _repoReturning(Object body, {int status = 200}) {
  final captured = _Captured();
  final api = ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: MockClient((request) async {
      captured.requests.add(request);
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  return (ProfileRepository(api), captured);
}

void main() {
  test('parses a fully populated profile', () {
    final profile = Profile.fromJson(
      Map<String, dynamic>.from(_fullProfileJson),
    );

    expect(profile.fullName, 'Juan Dela Cruz');
    expect(profile.sex, 'male');
    expect(profile.dateOfBirth, '1999-04-17');
    expect(profile.heightCm, 172.5);
    expect(profile.weightKg, 68.4);
    expect(profile.goalWeightKg, 64.0);
    expect(profile.mainGoal, 'lose_weight');
    expect(profile.activityLevel, 'moderate');
    expect(profile.city, 'Cebu City');
    expect(profile.notificationsEnabled, isTrue);
    expect(profile.equipment.single.name, 'Dumbbells');
    expect(profile.injuries.single.injuryId, 5);
    expect(profile.injuries.single.side, 'left');
  });

  test(
    'parses a just-registered profile whose optional fields are all null',
    () {
      final profile = Profile.fromJson(
        Map<String, dynamic>.from(_emptyProfileJson),
      );

      expect(profile.sex, isNull);
      expect(profile.dateOfBirth, isNull);
      expect(profile.heightCm, isNull);
      expect(profile.mainGoal, isNull);
      expect(profile.equipment, isEmpty);
      expect(profile.injuries, isEmpty);
      expect(profile.onboardingCompleted, isFalse);
    },
  );

  test('parses the weight unit, defaulting to kilograms', () {
    final pounds = Profile.fromJson({
      ...Map<String, dynamic>.from(_fullProfileJson),
      'weightUnit': 'lb',
    });
    expect(pounds.weightUnit, WeightUnit.lb);

    // The fixture carries no weightUnit at all -- a server older than the
    // column, which must read as metric rather than throw on the profile.
    final missing = Profile.fromJson(
      Map<String, dynamic>.from(_emptyProfileJson),
    );
    expect(missing.weightUnit, WeightUnit.kg);
  });

  test('normalises a date of birth the server returned as a timestamp', () {
    // Verified against the running server: PATCH /profile stores 1999-04-17
    // and GET returns "1999-04-17T00:00:00.000Z", but PATCH then REJECTS that
    // same value with INVALID_PROFILE_FIELD ("must be ... YYYY-MM-DD form").
    // Without trimming it here, editing any body metric fails for every user
    // who has already set a birthday.
    final profile = Profile.fromJson({
      ..._fullProfileJson,
      'dateOfBirth': '1999-04-17T00:00:00.000Z',
    });

    expect(profile.dateOfBirth, '1999-04-17');
  });

  test('leaves an already-plain date of birth alone', () {
    final profile = Profile.fromJson({
      ..._fullProfileJson,
      'dateOfBirth': '1999-04-17',
    });

    expect(profile.dateOfBirth, '1999-04-17');
  });

  test('parses measurements the driver returned as strings', () {
    // MySQL DECIMAL columns come back as strings through some driver
    // configurations. Parsing defensively is what stops a runtime
    // "type 'String' is not a subtype of type 'double'" crash.
    final profile = Profile.fromJson({
      ..._fullProfileJson,
      'heightCm': '172.50',
      'weightKg': '68.40',
      'goalWeightKg': '64.00',
    });

    expect(profile.heightCm, 172.5);
    expect(profile.weightKg, 68.4);
    expect(profile.goalWeightKg, 64.0);
  });

  test('patch sends only the keys it was given', () async {
    final (repo, captured) = _repoReturning({
      'data': {'profile': _fullProfileJson},
    });

    await repo.patch({'mainGoal': 'build_muscle'});

    expect(jsonDecode(captured.requests.single.body), {
      'mainGoal': 'build_muscle',
    });
    expect(captured.requests.single.method, 'PATCH');
  });

  test('setEquipment sends the complete id set', () async {
    final (repo, captured) = _repoReturning({
      'data': {'profile': _fullProfileJson},
    });

    await repo.setEquipment([3, 7]);

    expect(jsonDecode(captured.requests.single.body), {
      'equipmentIds': [3, 7],
    });
    expect(captured.requests.single.method, 'PUT');
  });

  test('setInjuries omits the side for a non-lateral injury', () async {
    final (repo, captured) = _repoReturning({
      'data': {'profile': _fullProfileJson},
    });

    await repo.setInjuries(const [
      SelectedInjury(injuryId: 5, side: 'left'),
      SelectedInjury(injuryId: 11),
    ]);

    expect(jsonDecode(captured.requests.single.body), {
      'injuries': [
        {'injuryId': 5, 'side': 'left'},
        {'injuryId': 11},
      ],
    });
  });

  test('parses the chosen training days', () async {
    final (repo, _) = _repoReturning({
      'data': {
        'profile': {
          'userId': 1,
          'email': 'a@b.c',
          'fullName': 'A',
          'onboardingCompleted': true,
          'isPremium': false,
          'notificationsEnabled': true,
          'equipment': <dynamic>[],
          'injuries': <dynamic>[],
          'trainingDays': [1, 3, 5],
        },
      },
    });

    expect((await repo.setTrainingDays([1, 3, 5])).trainingDays, [1, 3, 5]);
  });

  test('a profile with no trainingDays key reads as none chosen', () async {
    // A server that predates the field must not throw. "None chosen" is the
    // state the week strip already renders correctly.
    final (repo, _) = _repoReturning({
      'data': {
        'profile': {
          'userId': 1,
          'email': 'a@b.c',
          'fullName': 'A',
          'onboardingCompleted': true,
          'isPremium': false,
          'notificationsEnabled': true,
          'equipment': <dynamic>[],
          'injuries': <dynamic>[],
        },
      },
    });

    expect((await repo.setTrainingDays(const [])).trainingDays, isEmpty);
  });

  test('sends the days to the training-days endpoint', () async {
    final (repo, captured) = _repoReturning({
      'data': {
        'profile': {
          'userId': 1,
          'email': 'a@b.c',
          'fullName': 'A',
          'onboardingCompleted': true,
          'isPremium': false,
          'notificationsEnabled': true,
          'equipment': <dynamic>[],
          'injuries': <dynamic>[],
          'trainingDays': <dynamic>[],
        },
      },
    });

    await repo.setTrainingDays([2, 4]);

    final seen = captured.requests.single;
    expect(seen.url.path, '/api/v1/profile/training-days');
    expect(jsonDecode(seen.body), {
      'trainingDays': [2, 4],
    });
  });

  test('completeOnboarding returns the profile and the plan', () async {
    final (repo, _) = _repoReturning({
      'data': {
        'profile': _fullProfileJson,
        'plan': {'planId': 42, 'name': 'Week 1'},
      },
    });

    final result = await repo.completeOnboarding();

    expect(result.profile.onboardingCompleted, isTrue);
    expect(result.plan!['planId'], 42);
  });

  test('a failed plan generation surfaces PLAN_GENERATION_FAILED', () async {
    final (repo, _) = _repoReturning({
      'error': {
        'code': 'PLAN_GENERATION_FAILED',
        'message': 'Could not build a plan right now.',
      },
    }, status: 502);

    await expectLater(
      repo.completeOnboarding(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          'PLAN_GENERATION_FAILED',
        ),
      ),
    );
  });

  test('equipment and injury lookups parse their option lists', () async {
    final (repo, _) = _repoReturning({
      'data': {
        'injuries': [
          {
            'injuryId': 5,
            'name': 'Shoulder',
            'isLateral': true,
            'regionGroup': 'Upper body',
          },
          {
            'injuryId': 11,
            'name': 'Lower back',
            'isLateral': false,
            'regionGroup': 'Back and core',
          },
        ],
      },
    });

    final options = await repo.injuryOptions();

    expect(options.first.isLateral, isTrue);
    expect(options.last.isLateral, isFalse);
    expect(options.last.regionGroup, 'Back and core');
  });

  group('bodyWeight', () {
    // The real shape GET /api/v1/profile/body-weight sends: one "data"
    // envelope, same as every other endpoint ApiClient talks to. ApiClient
    // itself strips that envelope (see its own doc comment), so a repository
    // method must not look for a second one -- `bodyWeight` used to index
    // `['data']` again here and threw a null cast on the first real fetch.
    test('parses a single weigh-in, not double-wrapped', () async {
      final (repo, _) = _repoReturning({
        'data': {
          'widened': false,
          'points': [
            {'loggedOn': '2026-09-16', 'weightKg': 71.4},
          ],
          'reference': {'kind': 'goal', 'weightKg': 68.0},
          'unit': 'kg',
        },
      });

      final series = await repo.bodyWeight('week');
      expect(series.points.single.weightKg, 71.4);
      expect(series.reference?.kind, 'goal');
      expect(series.unit, 'kg');
    });

    test('asks for the period it was given', () async {
      final (repo, captured) = _repoReturning({
        'data': {
          'widened': false,
          'points': [],
          'reference': null,
          'unit': 'kg',
        },
      });

      await repo.bodyWeight('month');
      expect(captured.requests.single.url.queryParameters['period'], 'month');
    });

    test('no entries yet is not an error', () async {
      final (repo, _) = _repoReturning({
        'data': {
          'widened': false,
          'points': [],
          'reference': null,
          'unit': 'kg',
        },
      });

      final series = await repo.bodyWeight('week');
      expect(series.points, isEmpty);
      expect(series.reference, isNull);
    });
  });

  group('logBodyWeight', () {
    // Same defect as bodyWeight() above, same fix: POST /profile/body-weight
    // answers with one "data" envelope holding the stored point directly, not
    // a second "data" key inside it.
    test('parses the stored entry, not double-wrapped', () async {
      final (repo, captured) = _repoReturning({
        'data': {'loggedOn': '2026-09-16', 'weightKg': 71.4},
      });

      final point = await repo.logBodyWeight(71.4);

      expect(point.weightKg, 71.4);
      expect(point.loggedOn, '2026-09-16');
      expect(jsonDecode(captured.requests.single.body), {'weightKg': 71.4});
    });
  });
}
