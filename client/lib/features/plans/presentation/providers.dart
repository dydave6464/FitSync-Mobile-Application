import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy;
import '../data/plan_repository.dart';
import '../domain/workout_plan.dart';

final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => PlanRepository(ref.watch(apiClientProvider)),
);

/// The user's current plan, or null when they have none.
final activePlanProvider = FutureProvider<WorkoutPlan?>(
  (ref) => ref.watch(planRepositoryProvider).activePlan(),
  retry: apiRetryPolicy,
);
