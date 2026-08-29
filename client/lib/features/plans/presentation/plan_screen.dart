import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../exercises/presentation/exercise_detail_screen.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../exercises/presentation/providers.dart';
import '../../settings/presentation/settings_screen.dart';
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

/// Turns a `split_style` slug into something readable without pretending to
/// know every value the generator might produce.
String describeSplit(String slug) {
  if (slug.isEmpty) return '';
  return slug
      .split('_')
      .map((word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(activePlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your plan'),
        actions: [
          IconButton(
            key: const Key('settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: plan.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(describeError(error), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(activePlanProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (loaded) =>
            loaded == null ? const _NoPlanYet() : _PlanView(plan: loaded),
      ),
    );
  }
}

class _NoPlanYet extends StatelessWidget {
  const _NoPlanYet();

  @override
  Widget build(BuildContext context) => Center(
        key: const Key('noPlan'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fitness_center, size: 48),
              const SizedBox(height: 16),
              Text(
                'No plan yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Finish onboarding and one will be generated for you.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final baseUrl = ref.watch(planRepositoryProvider).baseUrl;

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(plan.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                [
                  describeSplit(plan.splitStyle),
                  '${plan.daysPerWeek} days a week',
                  '${plan.sessionLengthMin} min a session',
                ].where((part) => part.isNotEmpty).join(' · '),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const Divider(),
        for (final exercise in plan.exercises)
          _PlanExerciseTile(exercise: exercise, baseUrl: baseUrl),
      ],
    );
  }
}

/// Close to the catalogue's `ExerciseTile`, but its subtitle is fixed to
/// "muscle group · equipment" and this row has to carry the prescription
/// instead. Reusing it would mean adding a subtitle override to a widget that
/// has one job.
class _PlanExerciseTile extends StatelessWidget {
  const _PlanExerciseTile({required this.exercise, required this.baseUrl});

  final PlanExercise exercise;
  final String baseUrl;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: SizedBox(
          width: 56,
          height: 56,
          child: exercise.thumbnailUrl == null
              ? const _ThumbPlaceholder()
              : Image.network(
                  '$baseUrl${exercise.thumbnailUrl}',
                  fit: BoxFit.cover,
                  // One unreachable thumbnail must not take the row down.
                  errorBuilder: (_, _, _) => const _ThumbPlaceholder(),
                ),
        ),
        title: Text(exercise.name),
        subtitle: Text(
          '${exercise.muscleGroup} · '
          '${exercise.targetSets} × ${exercise.targetReps}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExerciseDetailScreen(exerciseId: exercise.exerciseId),
          ),
        ),
      );
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.fitness_center, size: 20),
      );
}
