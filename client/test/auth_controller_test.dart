import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/auth/data/auth_repository.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/routine/data/routine_repository.dart';
import 'package:fitsync/features/routine/domain/routine.dart';
import 'package:fitsync/features/routine/presentation/providers.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/active_session.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/session_outcome.dart';
import 'package:fitsync/features/sessions/domain/shared_report.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/streaks/data/streaks_repository.dart';
import 'package:fitsync/features/streaks/domain/streaks.dart';
import 'package:fitsync/features/streaks/presentation/providers.dart';

AuthUser _user({bool onboardingCompleted = false}) => AuthUser(
  userId: 7,
  email: 'juan@example.com',
  fullName: 'Juan Dela Cruz',
  onboardingCompleted: onboardingCompleted,
  isPremium: false,
);

/// An auth repository double. `me()` is supplied per test; `signOut()` clears
/// the same token store the controller reads, so the test can assert on it.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.tokens, {this.onMe});

  final TokenStore tokens;
  final Future<AuthUser> Function()? onMe;

  @override
  Future<AuthUser> me() => onMe!();

  @override
  Future<void> signOut() => tokens.clear();

  @override
  Future<AuthUser> login(String email, String password) =>
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
}

ProviderContainer _containerWith(TokenStore tokens, FakeAuthRepository repo) {
  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Hands out a different routine day on each call, so a cached one is
/// distinguishable from a freshly loaded one.
class _SequenceRoutineRepository implements RoutineRepository {
  _SequenceRoutineRepository(this._days);

  final List<RoutineDay> _days;
  int loads = 0;

  @override
  Future<RoutineDay> today() async {
    final d = _days[loads.clamp(0, _days.length - 1)];
    loads += 1;
    return d;
  }

  @override
  Future<List<Habit>> all() => throw UnimplementedError();
  @override
  Future<Habit> add(HabitDraft draft) => throw UnimplementedError();
  @override
  Future<Habit> edit(int habitId, HabitDraft draft) =>
      throw UnimplementedError();
  @override
  Future<void> remove(int habitId) => throw UnimplementedError();
  @override
  Future<void> check(int habitId, {String? date}) => throw UnimplementedError();
  @override
  Future<void> uncheck(int habitId, {String? date}) =>
      throw UnimplementedError();
}

/// Hands out a different summary/pending-outcome on each call, so a cached
/// one is distinguishable from a freshly loaded one. Every other method is
/// unused by the providers these tests exercise.
class _SequenceSessionRepository implements SessionRepository {
  _SequenceSessionRepository({
    this._summaries = const [],
    this._outcomes = const [],
  });

  final List<TrainingSummary> _summaries;
  final List<PendingOutcome?> _outcomes;
  int summaryLoads = 0;
  int outcomeLoads = 0;

  @override
  Future<TrainingSummary> summary({String period = 'week'}) async {
    final s = _summaries[summaryLoads.clamp(0, _summaries.length - 1)];
    summaryLoads += 1;
    return s;
  }

  @override
  Future<PendingOutcome?> pendingOutcome() async {
    final o = _outcomes[outcomeLoads.clamp(0, _outcomes.length - 1)];
    outcomeLoads += 1;
    return o;
  }

  @override
  String get baseUrl => '';
  @override
  Future<ActiveSession?> active() => throw UnimplementedError();
  @override
  Future<SessionHistoryPage> history({int page = 1, int limit = 20}) =>
      throw UnimplementedError();
  @override
  Future<LastWorkout?> lastWorkout() => throw UnimplementedError();
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
  Future<Set<String>> completedThisWeek() => throw UnimplementedError();
  @override
  Future<TrainingAnalytics> analytics(String period) =>
      throw UnimplementedError();
  @override
  Future<SharedReport> shareReport({
    required String period,
    required Map<String, bool> include,
  }) => throw UnimplementedError();
}

/// Hands out a different streak on each call, so a cached one is
/// distinguishable from a freshly loaded one.
class _SequenceStreakRepository implements StreakRepository {
  _SequenceStreakRepository(this._streaks);

  final List<Streak> _streaks;
  int loads = 0;

  @override
  Future<Streak> read() async {
    final s = _streaks[loads.clamp(0, _streaks.length - 1)];
    loads += 1;
    return s;
  }
}

void main() {
  test('a launch with no stored token resolves to signedOut', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    final container = _containerWith(tokens, FakeAuthRepository(tokens));

    final state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.signedOut);
    expect(state.user, isNull);
  });

  test(
    'a stored token for an unfinished profile resolves to onboarding',
    () async {
      final tokens = TokenStore(backing: InMemorySecureStore());
      await tokens.write('tok');
      final container = _containerWith(
        tokens,
        FakeAuthRepository(
          tokens,
          onMe: () async => _user(onboardingCompleted: false),
        ),
      );

      final state = await container.read(authControllerProvider.future);

      expect(state.status, AuthStatus.onboarding);
      expect(state.user!.email, 'juan@example.com');
    },
  );

  test('a stored token for a finished profile resolves to ready', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final container = _containerWith(
      tokens,
      FakeAuthRepository(
        tokens,
        onMe: () async => _user(onboardingCompleted: true),
      ),
    );

    final state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.ready);
  });

  test('a rejected token resolves to signedOut and clears the token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('expired');
    final container = _containerWith(
      tokens,
      FakeAuthRepository(
        tokens,
        onMe: () async =>
            throw const ApiException('UNAUTHENTICATED', 'Sign in to continue.'),
      ),
    );

    final state = await container.read(authControllerProvider.future);

    expect(state.status, AuthStatus.signedOut);
    expect(
      await tokens.read(),
      isNull,
      reason:
          'an expired token must not strand the user on a screen that '
          'cannot load',
    );
  });

  test('signOut moves a ready session to signedOut', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final container = _containerWith(
      tokens,
      FakeAuthRepository(
        tokens,
        onMe: () async => _user(onboardingCompleted: true),
      ),
    );

    await container.read(authControllerProvider.future);
    await container.read(authControllerProvider.notifier).signOut();

    expect(
      container.read(authControllerProvider).value!.status,
      AuthStatus.signedOut,
    );
    expect(await tokens.read(), isNull);
  });

  test("signing out drops the previous account's routine", () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final routines = _SequenceRoutineRepository([
      const RoutineDay(date: '2026-09-24', habits: [], workout: null),
      RoutineDay(
        date: '2026-09-24',
        habits: const [
          Habit(
            habitId: 1,
            title: 'Stretch',
            time: null,
            durationMin: null,
            weekdays: [1, 2, 3, 4, 5],
            done: false,
          ),
        ],
        workout: null,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            tokens,
            onMe: () async => _user(onboardingCompleted: true),
          ),
        ),
        routineRepositoryProvider.overrideWithValue(routines),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    final before = await container.read(routineTodayProvider.future);
    expect(before.habits, isEmpty);
    expect(routines.loads, 1);

    await container.read(authControllerProvider.notifier).signOut();

    final after = await container.read(routineTodayProvider.future);
    expect(
      after.habits,
      hasLength(1),
      reason: "the next account was handed the previous account's routine",
    );
    expect(routines.loads, 2, reason: 'the routine was not re-fetched');
  });

  test("signing out drops the previous account's 30-day summary", () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final sessions = _SequenceSessionRepository(
      summaries: const [
        TrainingSummary(sessionCount: 9, setCount: 40, totalVolumeKg: 1000),
        TrainingSummary(sessionCount: 0, setCount: 0, totalVolumeKg: 0),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            tokens,
            onMe: () async => _user(onboardingCompleted: true),
          ),
        ),
        sessionRepositoryProvider.overrideWithValue(sessions),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    final before = await container.read(homeSummaryProvider.future);
    expect(before.sessionCount, 9);
    expect(sessions.summaryLoads, 1);

    await container.read(authControllerProvider.notifier).signOut();

    final after = await container.read(homeSummaryProvider.future);
    expect(
      after.sessionCount,
      0,
      reason: "the next account was handed the previous account's summary",
    );
    expect(sessions.summaryLoads, 2, reason: 'the summary was not re-fetched');
  });

  test("signing out drops the previous account's pending outcome", () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final sessions = _SequenceSessionRepository(
      outcomes: const [
        PendingOutcome(
          sessionId: 1,
          sessionDate: '2026-09-23',
          planName: 'Push day',
        ),
        null,
      ],
    );
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            tokens,
            onMe: () async => _user(onboardingCompleted: true),
          ),
        ),
        sessionRepositoryProvider.overrideWithValue(sessions),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    final before = await container.read(pendingOutcomeProvider.future);
    expect(before, isNotNull);
    expect(sessions.outcomeLoads, 1);

    await container.read(authControllerProvider.notifier).signOut();

    final after = await container.read(pendingOutcomeProvider.future);
    expect(
      after,
      isNull,
      reason:
          "the next account was handed the previous account's pending "
          'outcome',
    );
    expect(
      sessions.outcomeLoads,
      2,
      reason: 'the pending outcome was not re-fetched',
    );
  });

  test("signing out drops the previous account's streak", () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('tok');
    final streaks = _SequenceStreakRepository(const [
      Streak(current: 12, best: 18, todayActive: true, week: []),
      Streak(current: 0, best: 0, todayActive: false, week: []),
    ]);
    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            tokens,
            onMe: () async => _user(onboardingCompleted: true),
          ),
        ),
        streakRepositoryProvider.overrideWithValue(streaks),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    expect((await container.read(streakProvider.future)).current, 12);

    await container.read(authControllerProvider.notifier).signOut();

    expect(
      (await container.read(streakProvider.future)).current,
      0,
      reason: "the next account was handed the previous account's streak",
    );
    expect(streaks.loads, 2);
  });
}
