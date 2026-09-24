import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy, exerciseRepositoryProvider;
import '../data/streaks_repository.dart';
import '../domain/streaks.dart';

final streakRepositoryProvider = Provider<StreakRepository>(
  (ref) => StreakRepository(ref.watch(apiClientProvider)),
);

final goalsRepositoryProvider = Provider<GoalsRepository>(
  (ref) => GoalsRepository(ref.watch(apiClientProvider)),
);

/// Home's streak tag and the streak card. Not autoDispose -- Home watches it
/// for the life of the app -- so it is on sign-out's list of per-user caches
/// (`_clearUserScopedCaches`). Refreshed by a landed tick, a finished
/// workout, and a resume on a new day.
final streakProvider = FutureProvider<Streak>(
  (ref) => ref.watch(streakRepositoryProvider).read(),
  retry: apiRetryPolicy,
);

/// The goals list; lives only while the Streaks & goals screen is open.
final goalsProvider = FutureProvider.autoDispose<List<LiftGoal>>(
  (ref) => ref.watch(goalsRepositoryProvider).list(),
  retry: apiRetryPolicy,
);

/// The add-goal sheet's "Lifted before" list.
final goalOptionsProvider = FutureProvider.autoDispose<List<GoalOption>>(
  (ref) => ref.watch(goalsRepositoryProvider).options(),
  retry: apiRetryPolicy,
);

/// The add-goal sheet's catalogue search, keyed on the query.
final goalSearchProvider = FutureProvider.autoDispose
    .family<List<ExerciseSummary>, String>(
      (ref, query) async =>
          (await ref.watch(exerciseRepositoryProvider).list(search: query))
              .items,
      retry: apiRetryPolicy,
    );
