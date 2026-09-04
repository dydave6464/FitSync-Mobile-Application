import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy;
import '../data/plan_repository.dart';
import '../domain/exercise_alternative.dart';
import '../domain/workout_plan.dart';

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => PlanRepository(ref.watch(apiClientProvider)),
);

/// The user's current plan, or null when they have none.
final activePlanProvider = FutureProvider<WorkoutPlan?>(
  (ref) => ref.watch(planRepositoryProvider).activePlan(),
  retry: apiRetryPolicy,
);

typedef AlternativesQuery = ({int planExerciseId, String query});

/// Swap candidates for one plan row. Keyed on the query too, so typing does
/// not discard the unfiltered list Riverpod already holds.
final alternativesProvider =
    FutureProvider.family<List<ExerciseAlternative>, AlternativesQuery>(
  (ref, key) => ref
      .watch(planRepositoryProvider)
      .alternatives(key.planExerciseId, q: key.query.isEmpty ? null : key.query),
  retry: apiRetryPolicy,
);
