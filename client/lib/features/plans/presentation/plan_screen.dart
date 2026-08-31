import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_detail_screen.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../domain/workout_plan.dart';
import 'providers.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final plan = ref.watch(activePlanProvider);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Your plan'),
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
                FsButton(
                  label: 'Retry',
                  small: true,
                  onPressed: () => ref.invalidate(activePlanProvider),
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
  Widget build(BuildContext context) {
    final t = context.fs;

    return Center(
      key: const Key('noPlan'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FsIconTile(icon: Icons.fitness_center, size: 56),
            const SizedBox(height: 16),
            Text('No plan yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Finish onboarding and one will be generated for you.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.plan});

  final WorkoutPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final theme = Theme.of(context);
    final baseUrl = ref.watch(planRepositoryProvider).baseUrl;

    final facts = [
      describeSplit(plan.splitStyle),
      '${plan.daysPerWeek} days a week',
      '${plan.sessionLengthMin} min a session',
    ].where((part) => part.isNotEmpty).join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        FsCard(
          accent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FsEyebrow('Week ${plan.weekNo}'),
              const SizedBox(height: 8),
              Text(plan.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(facts, style: TextStyle(fontSize: 12.5, color: t.text2)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Exercises'),
        const SizedBox(height: 10),
        for (final exercise in plan.exercises) ...[
          _PlanExerciseCard(exercise: exercise, baseUrl: baseUrl),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Close to the catalogue's `ExerciseTile`, but its subtitle is fixed to
/// "muscle group · equipment" and this row has to carry the prescription
/// instead. Reusing it would mean adding a subtitle override to a widget that
/// has one job.
class _PlanExerciseCard extends StatelessWidget {
  const _PlanExerciseCard({required this.exercise, required this.baseUrl});

  final PlanExercise exercise;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return FsCard(
      small: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExerciseDetailScreen(exerciseId: exercise.exerciseId),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(FsRadius.sm),
            child: SizedBox(
              width: 48,
              height: 48,
              child: exercise.thumbnailUrl == null
                  ? const _ThumbPlaceholder()
                  // `/plans/active` returns a bare relative path
                  // ("exercises/1460/thumb.jpg") while `/exercises` returns an
                  // absolute one ("/storage/exercises/0001/thumb.jpg"). Joining
                  // naively produced "http://host:3000exercises/...". This keeps
                  // the URL well formed; the server-side inconsistency (the
                  // plans path also omits the /storage mount) still needs
                  // fixing there, and until it is, errorBuilder shows the
                  // placeholder.
                  : Image.network(
                      '$baseUrl${exercise.thumbnailUrl!.startsWith('/') ? '' : '/'}'
                      '${exercise.thumbnailUrl}',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _ThumbPlaceholder(),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  '${exercise.muscleGroup} · '
                  '${exercise.targetSets} × ${exercise.targetReps}',
                  style: TextStyle(
                    fontFamily: fsMonoFamily,
                    fontSize: 11,
                    color: t.text3,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: t.text3),
        ],
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      color: t.surface2,
      child: Icon(Icons.fitness_center, size: 20, color: t.text3),
    );
  }
}
