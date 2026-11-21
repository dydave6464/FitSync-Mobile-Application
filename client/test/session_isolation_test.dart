import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/ads/data/ad_source.dart';
import 'package:fitsync/features/ads/presentation/ad_slot.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/domain/sign_in_outcome.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/exercises/data/exercise_repository.dart';
import 'package:fitsync/features/exercises/domain/exercise.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart';
import 'package:fitsync/features/pro/domain/pro_status.dart';
import 'package:fitsync/features/pro/presentation/providers.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/data/training_settings_repository.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/domain/session_detail.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/session_outcome.dart';
import 'package:fitsync/features/sessions/domain/shared_report.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/workout_draft.dart';

import 'helpers/fake_ad_source.dart';

/// Signing out must not leave one account's data readable by the next.
///
/// profileProvider is an AsyncNotifierProvider and activePlanProvider a
/// FutureProvider; neither is autoDispose, so both cache for the lifetime of
/// the app. Clearing the token alone leaves that cache intact, and the next
/// user to sign in is handed the previous user's profile.

/// A catalogue row as the library hands it to the draft.
ExerciseSummary _picked(int id) => ExerciseSummary(
  exerciseId: id,
  name: 'Exercise $id',
  muscleGroup: 'chest',
  equipment: 'barbell',
  thumbnailUrl: null,
);

Profile _profile({required int userId, required String email}) => Profile(
  userId: userId,
  email: email,
  fullName: 'User $userId',
  onboardingCompleted: true,
  isPremium: false,
  notificationsEnabled: true,
  equipment: const [],
  injuries: const [],
  heightCm: userId * 10.0,
);

/// Hands out a different profile on each call, so a cached value is
/// distinguishable from a freshly loaded one.
class SequenceProfileRepository implements ProfileRepository {
  SequenceProfileRepository(this._profiles);

  final List<Profile> _profiles;
  int loads = 0;

  @override
  Future<Profile> load() async {
    final p = _profiles[loads.clamp(0, _profiles.length - 1)];
    loads += 1;
    return p;
  }

  @override
  Future<Profile> patch(Map<String, dynamic> fields) =>
      throw UnimplementedError();
  @override
  Future<Profile> setEquipment(List<int> equipmentIds) =>
      throw UnimplementedError();
  @override
  Future<Profile> setInjuries(List<SelectedInjury> injuries) =>
      throw UnimplementedError();
  @override
  Future<Profile> setTrainingDays(List<int> weekdays) =>
      throw UnimplementedError();
  @override
  Future<Profile> setGoals(List<String> goals, String mainGoal) =>
      throw UnimplementedError();
  @override
  Future<CompletedOnboarding> completeOnboarding() =>
      throw UnimplementedError();
  @override
  Future<List<EquipmentOption>> equipmentOptions() async => const [];
  @override
  Future<List<InjuryOption>> injuryOptions() async => const [];
  @override
  Future<BodyWeightSeries> bodyWeight(String period) =>
      throw UnimplementedError();
  @override
  Future<BodyWeightPoint> logBodyWeight(double weightKg, {String? loggedOn}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteBodyWeight(String loggedOn) => throw UnimplementedError();
}

/// Hands out a different in-progress session on each call, so a cached one is
/// distinguishable from a freshly loaded one.
class SequenceSessionRepository implements SessionRepository {
  SequenceSessionRepository(this._sessions);

  final List<ActiveSession?> _sessions;
  int loads = 0;
  int weekLoads = 0;

  @override
  Future<ActiveSession?> active() async {
    final s = _sessions[loads.clamp(0, _sessions.length - 1)];
    loads += 1;
    return s;
  }

  @override
  Future<Set<String>> completedThisWeek() async {
    weekLoads += 1;
    return {'2026-09-0$weekLoads'};
  }

  @override
  String get baseUrl => '';
  @override
  Future<SessionHistoryPage> history({int page = 1, int limit = 20}) =>
      throw UnimplementedError();
  @override
  Future<SessionDetail> detail(int sessionId) => throw UnimplementedError();
  @override
  Future<TrainingSummary> summary({String period = 'week'}) =>
      throw UnimplementedError();
  @override
  Future<LastWorkout?> lastWorkout() => throw UnimplementedError();
  @override
  Future<PendingOutcome?> pendingOutcome() => throw UnimplementedError();
  @override
  Future<void> recordOutcome(
    int sessionId, {
    required String painLevel,
    int? injuryId,
  }) => throw UnimplementedError();
  @override
  Future<ActiveSession> start({List<int>? exerciseIds}) =>
      throw UnimplementedError();
  @override
  Future<LoggedSet> logSet(
    int sessionId, {
    required int exerciseId,
    required int setNumber,
    double? weightKg,
    int? reps,
  }) => throw UnimplementedError();
  @override
  Future<void> deleteSet(
    int sessionId, {
    required int exerciseId,
    required int setNumber,
  }) => throw UnimplementedError();
  @override
  Future<ActiveSession> complete(int sessionId, int durationMin) =>
      throw UnimplementedError();
  @override
  Future<void> abandon(int sessionId) => throw UnimplementedError();
  @override
  Future<Map<int, LastPerformance>> lastPerformance(List<int> exerciseIds) =>
      throw UnimplementedError();
  @override
  Future<TrainingAnalytics> analytics(String period) =>
      throw UnimplementedError();
  @override
  Future<SharedReport> shareReport({
    required String period,
    required Map<String, bool> include,
  }) => throw UnimplementedError();
}

/// Hands out a different weigh-in series on each call, so a cached one is
/// distinguishable from a freshly loaded one.
class SequenceBodyWeightRepository extends SequenceProfileRepository {
  SequenceBodyWeightRepository(this._series)
    : super([_profile(userId: 1, email: 'a@b.c')]);

  final List<BodyWeightSeries> _series;
  int weightLoads = 0;

  @override
  Future<BodyWeightSeries> bodyWeight(String period) async {
    final s = _series[weightLoads.clamp(0, _series.length - 1)];
    weightLoads += 1;
    return s;
  }
}

BodyWeightSeries _weighIn(String loggedOn, double weightKg) => BodyWeightSeries(
  widened: false,
  points: [BodyWeightPoint(loggedOn: loggedOn, weightKg: weightKg)],
  reference: null,
  unit: 'kg',
);

/// Hands out a different rest length on each call.
class SequenceTrainingSettingsRepository implements TrainingSettingsRepository {
  SequenceTrainingSettingsRepository(this._seconds);

  final List<int> _seconds;
  int loads = 0;

  @override
  Future<int> restSeconds() async {
    final s = _seconds[loads.clamp(0, _seconds.length - 1)];
    loads += 1;
    return s;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// Hands out the same exercise with a different `contraindicated` flag on
/// each call: the server works the flag out for whoever is signed in. The
/// detail ([byId]) and the library list ([list]) keep separate counts.
class SequenceExerciseRepository implements ExerciseRepository {
  SequenceExerciseRepository(this._contraindicated);

  final List<bool> _contraindicated;
  int loads = 0;
  int listLoads = 0;

  @override
  Future<ExercisePage> list({
    List<String> muscleGroups = const [],
    String? equipment,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    final flag =
        _contraindicated[listLoads.clamp(0, _contraindicated.length - 1)];
    listLoads += 1;
    return ExercisePage(
      items: [
        ExerciseSummary(
          exerciseId: 101,
          name: 'Exercise 101',
          muscleGroup: 'chest',
          equipment: 'barbell',
          thumbnailUrl: null,
          contraindicated: flag,
        ),
      ],
      page: page,
      limit: limit,
      total: 1,
    );
  }

  @override
  Future<ExerciseDetail> byId(int id) async {
    final flag = _contraindicated[loads.clamp(0, _contraindicated.length - 1)];
    loads += 1;
    return ExerciseDetail(
      exerciseId: id,
      name: 'Exercise $id',
      muscleGroup: 'chest',
      equipment: 'barbell',
      thumbnailUrl: null,
      animationUrl: null,
      cues: const [],
      contraindicated: flag,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.tokens);
  final TokenStore tokens;

  @override
  Future<AuthUser> me() => throw UnimplementedError();
  @override
  Future<void> signOut() => tokens.clear();
  @override
  Future<SignInOutcome> login(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) => throw UnimplementedError();
  @override
  Future<AuthUser> signInWithGoogle(String idToken) =>
      throw UnimplementedError();
  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();
  @override
  Future<void> resendVerification({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<void> verifyEmail({required String email, required String code}) =>
      throw UnimplementedError();
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteAccount({String? password, String? idToken}) =>
      throw UnimplementedError();

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) => throw UnimplementedError();
}

void main() {
  test('signing out drops the previous account\'s profile', () async {
    final first = _profile(userId: 1, email: 'juan@example.com');
    final second = _profile(userId: 2, email: 'maria@example.com');
    final profiles = SequenceProfileRepository([first, second]);
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');

    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
    );
    addTearDown(container.dispose);

    // Juan is signed in and his profile is loaded and cached.
    expect(
      (await container.read(profileProvider.future)).email,
      'juan@example.com',
    );
    expect(profiles.loads, 1);

    await container.read(authControllerProvider.notifier).signOut();

    // Maria signs in on the same device. She must not be shown Juan's profile.
    final afterSignOut = await container.read(profileProvider.future);
    expect(
      afterSignOut.email,
      'maria@example.com',
      reason: 'the next account got the previous account\'s cached profile',
    );
    expect(profiles.loads, 2, reason: 'the profile was not re-fetched');
  });

  // The session slice landed after this file was written, and brought two
  // more caches with it. An in-progress session carries its logged sets, so
  // the next account to sign in on the same device opened the logger onto
  // someone else's weights and reps already ticked into the table.
  test(
    "signing out drops the previous account's in-progress session",
    () async {
      final juan = ActiveSession(
        sessionId: 1,
        status: 'in_progress',
        sessionDate: '2026-09-09',
        startedAt: DateTime.now(),
        sets: const [
          LoggedSet(exerciseId: 101, setNumber: 1, weightKg: 60, reps: 8),
        ],
      );
      final sessions = SequenceSessionRepository([juan, null]);
      final tokens = TokenStore(backing: InMemorySecureStore());
      await tokens.write('token-for-juan');

      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
          profileRepositoryProvider.overrideWithValue(
            SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
          ),
          sessionRepositoryProvider.overrideWithValue(sessions),
        ],
      );
      addTearDown(container.dispose);

      expect(
        (await container.read(activeSessionProvider.future))!.sets,
        hasLength(1),
      );
      expect(sessions.loads, 1);

      await container.read(authControllerProvider.notifier).signOut();

      expect(
        await container.read(activeSessionProvider.future),
        isNull,
        reason: "the next account was handed the previous account's session",
      );
      expect(sessions.loads, 2, reason: 'the session was not re-fetched');
    },
  );

  test("signing out drops the previous account's completed days", () async {
    final sessions = SequenceSessionRepository([null]);
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');

    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(
          SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
        ),
        sessionRepositoryProvider.overrideWithValue(sessions),
      ],
    );
    addTearDown(container.dispose);

    // The week strip is per-user too: it marks which days THIS account trained.
    expect(await container.read(completedDaysProvider.future), {'2026-09-01'});

    await container.read(authControllerProvider.notifier).signOut();

    expect(await container.read(completedDaysProvider.future), {
      '2026-09-02',
    }, reason: "the next account kept the previous account's week strip");
  });

  // The manual picker landed after the caches above, and brought a third one
  // with it. The draft is not autoDispose, so exercises ticked in the library
  // and never started survive the sign-out: the next account opens "Log
  // manually" to someone else's picks already selected, an "N added" count
  // and a live Start button.
  test("signing out drops the previous account's unstarted picks", () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');

    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(
          SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Juan picks two exercises in the library and walks away without starting.
    container.read(workoutDraftProvider.notifier).toggle(_picked(101));
    container.read(workoutDraftProvider.notifier).toggle(_picked(202));
    expect(container.read(workoutDraftProvider), hasLength(2));

    await container.read(authControllerProvider.notifier).signOut();

    expect(
      container.read(workoutDraftProvider),
      isEmpty,
      reason: "the next account was handed the previous account's picks",
    );
  });

  test("signing out drops the previous account's catalogue filter", () async {
    // Not user data in the way a logged set is, but still a trace of the
    // previous account: the next one would open the library to a short list,
    // narrowed by a word someone else typed.
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');

    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(
          SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(selectedFiltersProvider.notifier).setSearch('bench');
    container.read(selectedFiltersProvider.notifier).setEquipment('barbell');

    await container.read(authControllerProvider.notifier).signOut();

    final filters = container.read(selectedFiltersProvider);
    expect(
      filters.search,
      isNull,
      reason: "the next account inherited a search term",
    );
    expect(
      filters.equipment,
      isNull,
      reason: "the next account inherited an equipment filter",
    );
  });

  test("signing out drops the previous account's unfinished payment", () async {
    // The Pro screen re-checks a remembered checkout each time it opens; the
    // next account would ask the server about someone else's payment.
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(
          SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(proPendingCheckoutProvider.notifier)
        .remember(
          ProCheckout(
            paymentId: 7,
            checkoutUrl: Uri.parse('https://checkout.example/cs_7'),
          ),
        );

    await container.read(authControllerProvider.notifier).signOut();

    expect(container.read(proPendingCheckoutProvider), isNull);
  });

  test(
    "signing out forgets the session's ad and the views it reported",
    () async {
      // The ad is kept for the session, and a view counted once per
      // placement in it; the next account starts both afresh.
      final tokens = TokenStore(backing: InMemorySecureStore());
      await tokens.write('token-for-juan');
      final source = FakeAdSource(ad: sampleHouseAd);
      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
          profileRepositoryProvider.overrideWithValue(
            SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
          ),
          adSourceProvider.overrideWithValue(source),
        ],
      );
      addTearDown(container.dispose);
      expect((await container.read(currentAdProvider.future))?.id, 7);
      container.read(adViewsReportedProvider).add(('home', 7));

      await container.read(authControllerProvider.notifier).signOut();
      source.ad = null;

      expect(await container.read(currentAdProvider.future), isNull);
      expect(container.read(adViewsReportedProvider), isEmpty);
    },
  );

  // JR-1: three more per-account caches outlived the sign-out. Each is
  // listened to, as a screen would, so a refetch can only come from the
  // sign-out clearing it.
  test("signing out drops the previous account's weigh-ins", () async {
    // Progress, the weigh-ins list and the coach report all read this. A
    // leftover list is worse than stale: its delete is keyed by day, so it
    // would remove the next account's own weigh-in for that date.
    final profiles = SequenceBodyWeightRepository([
      _weighIn('2026-11-01', 80),
      _weighIn('2026-11-02', 55),
    ]);
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
    );
    addTearDown(container.dispose);

    container.listen(bodyWeightProvider('month'), (_, _) {});
    expect(
      (await container.read(bodyWeightProvider('month').future))
          .points
          .single
          .weightKg,
      80,
    );
    expect(profiles.weightLoads, 1);

    await container.read(authControllerProvider.notifier).signOut();

    expect(
      (await container.read(bodyWeightProvider('month').future))
          .points
          .single
          .weightKg,
      55,
      reason: "the next account was shown the previous account's weigh-ins",
    );
    expect(
      profiles.weightLoads,
      2,
      reason: 'the weigh-ins were not re-fetched',
    );
  });

  test("signing out drops the previous account's rest length", () async {
    final settings = SequenceTrainingSettingsRepository([150, 60]);
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(
          SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
        ),
        trainingSettingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);

    container.listen(restSecondsProvider, (_, _) {});
    expect(await container.read(restSecondsProvider.future), 150);
    expect(settings.loads, 1);

    await container.read(authControllerProvider.notifier).signOut();

    expect(
      await container.read(restSecondsProvider.future),
      60,
      reason: "the rest timer started from the previous account's length",
    );
    expect(settings.loads, 2, reason: 'the rest length was not re-fetched');
  });

  test("signing out drops the previous account's injury warning", () async {
    // `contraindicated` is worked out on the server for the signed-in user:
    // Juan's shoulder injury flags this exercise, Maria has none.
    final exercises = SequenceExerciseRepository([true, false]);
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(
          SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
        ),
        exerciseRepositoryProvider.overrideWithValue(exercises),
      ],
    );
    addTearDown(container.dispose);

    container.listen(exerciseDetailProvider(101), (_, _) {});
    expect(
      (await container.read(exerciseDetailProvider(101).future))
          .contraindicated,
      isTrue,
    );
    expect(exercises.loads, 1);

    await container.read(authControllerProvider.notifier).signOut();

    expect(
      (await container.read(exerciseDetailProvider(101).future))
          .contraindicated,
      isFalse,
      reason: "the next account was shown the previous account's warning",
    );
    expect(exercises.loads, 2, reason: 'the exercise was not re-fetched');
  });

  test(
    "signing out drops the previous account's exercise library rows",
    () async {
      // Each library row carries the same per-user `contraindicated` flag as
      // the detail. Juan leaves the filters at their default, so resetting
      // the filters changes nothing a dependent could notice: the list
      // itself has to be dropped.
      final exercises = SequenceExerciseRepository([true, false]);
      final tokens = TokenStore(backing: InMemorySecureStore());
      await tokens.write('token-for-juan');
      final container = ProviderContainer(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
          profileRepositoryProvider.overrideWithValue(
            SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
          ),
          exerciseRepositoryProvider.overrideWithValue(exercises),
        ],
      );
      addTearDown(container.dispose);

      container.listen(exerciseListProvider, (_, _) {});
      expect(container.read(selectedFiltersProvider).isEmpty, isTrue);
      final before = await container.read(exerciseListProvider.future);
      expect(before.items.single.contraindicated, isTrue);
      expect(exercises.listLoads, 1);

      await container.read(authControllerProvider.notifier).signOut();

      // The library screen draws `listing.when(...)` with its defaults. A
      // plain refresh keeps Juan's rows as the data branch until the next
      // page arrives; a reload shows the loading branch instead.
      final first = container.read(exerciseListProvider);
      expect(
        first.when(
          data: (page) => 'data',
          loading: () => 'loading',
          error: (_, _) => 'error',
        ),
        'loading',
        reason: "the next account's first frame drew the previous rows",
      );
      expect(first.isReloading, isTrue);

      final after = await container.read(exerciseListProvider.future);
      expect(
        after.items.single.contraindicated,
        isFalse,
        reason: "the next account was shown the previous account's badges",
      );
      expect(exercises.listLoads, 2, reason: 'the list was not re-fetched');
    },
  );

  // The same flash on the other screens: Home draws `profile.when(...)` and
  // Progress `bodyWeight.when(...)`, both with their defaults. A plain
  // refresh hands the next account the previous name and weigh-ins as the
  // data branch until its own arrive; a reload shows the loading branch.
  String branch<T>(AsyncValue<T> value) => value.when(
    data: (_) => 'data',
    loading: () => 'loading',
    error: (_, _) => 'error',
  );

  test("the next account's first frame of the profile is loading, not the "
      "previous account's", () async {
    final profiles = SequenceProfileRepository([
      _profile(userId: 1, email: 'juan@example.com'),
      _profile(userId: 2, email: 'maria@example.com'),
    ]);
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
    );
    addTearDown(container.dispose);

    container.listen(profileProvider, (_, _) {});
    expect(
      (await container.read(profileProvider.future)).email,
      'juan@example.com',
    );

    await container.read(authControllerProvider.notifier).signOut();

    final first = container.read(profileProvider);
    expect(
      branch(first),
      'loading',
      reason: "the next account's first frame drew the previous profile",
    );
    expect(first.isReloading, isTrue);
    expect(
      (await container.read(profileProvider.future)).email,
      'maria@example.com',
    );
  });

  test("the next account's first frame of the weigh-ins is loading, not the "
      "previous account's", () async {
    final profiles = SequenceBodyWeightRepository([
      _weighIn('2026-11-01', 80),
      _weighIn('2026-11-02', 55),
    ]);
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(profiles),
      ],
    );
    addTearDown(container.dispose);

    container.listen(bodyWeightProvider('month'), (_, _) {});
    expect(
      (await container.read(bodyWeightProvider('month').future))
          .points
          .single
          .weightKg,
      80,
    );

    await container.read(authControllerProvider.notifier).signOut();

    final first = container.read(bodyWeightProvider('month'));
    expect(
      branch(first),
      'loading',
      reason: "the next account's first frame drew the previous weigh-ins",
    );
    expect(first.isReloading, isTrue);
    expect(
      (await container.read(bodyWeightProvider('month').future))
          .points
          .single
          .weightKg,
      55,
    );
  });

  test('signing out clears the stored token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('token-for-juan');
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(tokens)),
        profileRepositoryProvider.overrideWithValue(
          SequenceProfileRepository([_profile(userId: 1, email: 'a@b.c')]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.notifier).signOut();
    expect(await tokens.read(), isNull);
  });
}
