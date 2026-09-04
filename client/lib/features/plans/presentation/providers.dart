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

typedef AlternativesQuery = ({int planExerciseId, String query, bool bodyweightOnly});

/// Swap candidates for one plan row. Keyed on the query and the filter too,
/// so neither discards the list Riverpod already holds for the other state.
final alternativesProvider =
    FutureProvider.family<List<ExerciseAlternative>, AlternativesQuery>(
  (ref, key) => ref.watch(planRepositoryProvider).alternatives(
        key.planExerciseId,
        q: key.query.isEmpty ? null : key.query,
        bodyweightOnly: key.bodyweightOnly,
      ),
  retry: apiRetryPolicy,
);
