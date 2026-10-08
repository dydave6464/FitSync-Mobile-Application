import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/workout_plan.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
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

  @override
  Future<ActiveSession?> active() async {
    fetchCount += 1;
    return null;
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
}
