import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
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
      return http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});
    }),
  );
  return (ProfileRepository(api), captured);
}

void main() {
  test('parses a fully populated profile', () {
    final profile = Profile.fromJson(Map<String, dynamic>.from(_fullProfileJson));

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

  test('parses a just-registered profile whose optional fields are all null',
      () {
    final profile =
        Profile.fromJson(Map<String, dynamic>.from(_emptyProfileJson));

    expect(profile.sex, isNull);
    expect(profile.dateOfBirth, isNull);
    expect(profile.heightCm, isNull);
    expect(profile.mainGoal, isNull);
    expect(profile.equipment, isEmpty);
    expect(profile.injuries, isEmpty);
    expect(profile.onboardingCompleted, isFalse);
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
    final (repo, captured) = _repoReturning({'data': {'profile': _fullProfileJson}});

    await repo.patch({'mainGoal': 'build_muscle'});

    expect(jsonDecode(captured.requests.single.body), {'mainGoal': 'build_muscle'});
    expect(captured.requests.single.method, 'PATCH');
  });

  test('setEquipment sends the complete id set', () async {
    final (repo, captured) = _repoReturning({'data': {'profile': _fullProfileJson}});

    await repo.setEquipment([3, 7]);

    expect(jsonDecode(captured.requests.single.body), {'equipmentIds': [3, 7]});
    expect(captured.requests.single.method, 'PUT');
  });

  test('setInjuries omits the side for a non-lateral injury', () async {
    final (repo, captured) = _repoReturning({'data': {'profile': _fullProfileJson}});

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
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'PLAN_GENERATION_FAILED')),
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
}
