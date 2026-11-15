import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart'
    show
        exerciseRepositoryProvider,
        exerciseDetailProvider,
        exerciseListProvider;
import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';

Profile _profile({List<SelectedInjury> injuries = const []}) => Profile(
  userId: 7,
  email: 'juan@example.com',
  fullName: 'Juan Dela Cruz',
  onboardingCompleted: true,
  isPremium: false,
  notificationsEnabled: true,
  equipment: const [],
  injuries: injuries,
);

class _FakeProfileRepo implements ProfileRepository {
  Profile current = _profile();

  @override
  Future<Profile> load() async => current;

  @override
  Future<Profile> setInjuries(List<SelectedInjury> injuries) async {
    current = _profile(injuries: injuries);
    return current;
  }

  @override
  Future<Profile> setTrainingDays(List<int> weekdays) async => current;

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// Counts how many times the active plan was fetched, independent of what
/// it resolves to -- the tag staleness this test is about shows up as a
/// fetch count, not a payload difference.
class _FakePlanRepo implements PlanRepository {
  int fetchCount = 0;

  @override
  Future<WorkoutPlan?> activePlan() async {
    fetchCount += 1;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// Same reasoning as [_FakePlanRepo]: the logger watches this provider for
/// the in-progress session, and its `coaching` tags go stale the same way.
class _FakeSessionRepo implements SessionRepository {
  int fetchCount = 0;
  int analyticsCount = 0;

  @override
  Future<TrainingAnalytics> analytics(String period) async {
    analyticsCount += 1;
    return TrainingAnalytics.fromJson({
      'period': period,
      'volume': const [],
      'change': const {'totalKg': 0, 'previousKg': 0, 'changePct': null},
      'adherence': const {'done': 0, 'target': 3, 'weeks': 1},
      'muscles': const [],
    });
  }

  @override
  Future<ActiveSession?> active() async {
    fetchCount += 1;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// Counts exercise fetches: the detail's and each library row's
/// `contraindicated` flag is worked out on the server from the injury list,
/// so only a refetch can change it.
class _FakeExerciseRepo implements ExerciseRepository {
  int fetchCount = 0;
  int listCount = 0;

  @override
  Future<ExercisePage> list({
    List<String> muscleGroups = const [],
    String? equipment,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    listCount += 1;
    return const ExercisePage(items: [], page: 1, limit: 20, total: 0);
  }

  @override
  Future<ExerciseDetail> byId(int id) async {
    fetchCount += 1;
    return ExerciseDetail(
      exerciseId: id,
      name: 'Exercise $id',
      muscleGroup: 'chest',
      equipment: 'barbell',
      thumbnailUrl: null,
      animationUrl: null,
      cues: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

void main() {
  test('editing injuries refetches the active plan and session', () async {
    final profileRepo = _FakeProfileRepo();
    final planRepo = _FakePlanRepo();
    final sessionRepo = _FakeSessionRepo();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profileRepo),
        planRepositoryProvider.overrideWithValue(planRepo),
        sessionRepositoryProvider.overrideWithValue(sessionRepo),
      ],
    );
    addTearDown(container.dispose);

    // Listened, not just read: an unlistened FutureProvider is disposed as
    // soon as the read returns, so it would refetch on the next read whether
    // or not anything invalidated it -- and this test would pass vacuously.
    container.listen(activePlanProvider, (_, _) {});
    container.listen(activeSessionProvider, (_, _) {});
    await container.read(profileProvider.future);
    await container.read(activePlanProvider.future);
    await container.read(activeSessionProvider.future);
    expect(planRepo.fetchCount, 1);
    expect(sessionRepo.fetchCount, 1);

    await container.read(profileProvider.notifier).setInjuries(
      const [SelectedInjury(injuryId: 3)],
    );
    await container.read(activePlanProvider.future);
    await container.read(activeSessionProvider.future);

    // Their `coaching` tags were read under the old injury list; only a
    // fresh fetch can carry the new one.
    expect(planRepo.fetchCount, 2);
    expect(sessionRepo.fetchCount, 2);
  });

  // JR-1: an exercise opened before the edit kept its old "loads an injury
  // you reported" warning, or kept its absence.
  test('editing injuries refetches a loaded exercise detail', () async {
    final profileRepo = _FakeProfileRepo();
    final exerciseRepo = _FakeExerciseRepo();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profileRepo),
        planRepositoryProvider.overrideWithValue(_FakePlanRepo()),
        sessionRepositoryProvider.overrideWithValue(_FakeSessionRepo()),
        exerciseRepositoryProvider.overrideWithValue(exerciseRepo),
      ],
    );
    addTearDown(container.dispose);

    // Listened, so a refetch can only come from an invalidation.
    container.listen(exerciseDetailProvider(101), (_, _) {});
    await container.read(profileProvider.future);
    await container.read(exerciseDetailProvider(101).future);
    expect(exerciseRepo.fetchCount, 1);

    await container.read(profileProvider.notifier).setInjuries(
      const [SelectedInjury(injuryId: 3)],
    );
    await container.read(exerciseDetailProvider(101).future);

    expect(exerciseRepo.fetchCount, 2);
  });

  // The library list's rows carry the same per-user flag behind the tile
  // badge and the pick bar's warning, and the list is not autoDispose.
  test('editing injuries refetches the exercise library list', () async {
    final profileRepo = _FakeProfileRepo();
    final exerciseRepo = _FakeExerciseRepo();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profileRepo),
        planRepositoryProvider.overrideWithValue(_FakePlanRepo()),
        sessionRepositoryProvider.overrideWithValue(_FakeSessionRepo()),
        exerciseRepositoryProvider.overrideWithValue(exerciseRepo),
      ],
    );
    addTearDown(container.dispose);

    // Listened, so a refetch can only come from an invalidation.
    container.listen(exerciseListProvider, (_, _) {});
    await container.read(profileProvider.future);
    await container.read(exerciseListProvider.future);
    expect(exerciseRepo.listCount, 1);

    await container.read(profileProvider.notifier).setInjuries(
      const [SelectedInjury(injuryId: 3)],
    );
    await container.read(exerciseListProvider.future);

    expect(exerciseRepo.listCount, 2);
  });

  // PT-18: the server derives the plan's days a week from the chosen days,
  // and the Progress adherence target from the same count, so both refetch.
  test('choosing training days refetches the active plan and the analytics, '
      'every period', () async {
    final profileRepo = _FakeProfileRepo();
    final planRepo = _FakePlanRepo();
    final sessionRepo = _FakeSessionRepo();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profileRepo),
        planRepositoryProvider.overrideWithValue(planRepo),
        sessionRepositoryProvider.overrideWithValue(sessionRepo),
      ],
    );
    addTearDown(container.dispose);

    // Listened, so a refetch can only come from an invalidation.
    container.listen(activePlanProvider, (_, _) {});
    container.listen(trainingAnalyticsProvider('week'), (_, _) {});
    container.listen(trainingAnalyticsProvider('month'), (_, _) {});
    await container.read(profileProvider.future);
    await container.read(activePlanProvider.future);
    await container.read(trainingAnalyticsProvider('week').future);
    await container.read(trainingAnalyticsProvider('month').future);
    expect(planRepo.fetchCount, 1);
    expect(sessionRepo.analyticsCount, 2);

    await container.read(profileProvider.notifier).setTrainingDays(const [
      1,
      3,
      5,
      6,
    ]);
    await container.read(activePlanProvider.future);
    await container.read(trainingAnalyticsProvider('week').future);
    await container.read(trainingAnalyticsProvider('month').future);

    expect(planRepo.fetchCount, 2);
    expect(sessionRepo.analyticsCount, 4);
  });
}
