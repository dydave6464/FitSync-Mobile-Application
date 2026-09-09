import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_thumb.dart';
import '../../exercises/presentation/exercise_detail_screen.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../sessions/presentation/providers.dart';
import '../../sessions/presentation/session_logger_screen.dart';
import '../domain/workout_plan.dart';
import 'exercise_swap_sheet.dart';
import 'providers.dart';
import 'widgets/session_card.dart';
import 'widgets/week_strip.dart';

/// The Plan tab's body. No longer brings its own `Scaffold`/`AppBar` — the
/// Training shell now supplies both, so this is what the shell's Plan tab
/// renders inside them.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key, this.onGoToProfile});

  /// Switches the shell to the Profile tab. Handed down to the swap sheet,
  /// whose equipment note is the only thing here that leaves this tab.
  final VoidCallback? onGoToProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(activePlanProvider);

    return plan.when(
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
      data: (loaded) => loaded == null
          ? const _NoPlanYet()
          : _PlanView(plan: loaded, onGoToProfile: onGoToProfile),
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

class _PlanView extends ConsumerStatefulWidget {
  const _PlanView({required this.plan, this.onGoToProfile});

  final WorkoutPlan plan;
  final VoidCallback? onGoToProfile;

  @override
  ConsumerState<_PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends ConsumerState<_PlanView> {
  /// True while a Start/Resume tap's request is in flight. Kept off the
  /// controller: it is purely this button's own affordance, not session
  /// state anything else needs to read.
  bool _starting = false;

  /// Starts a session (skipped when one is already in progress) and opens
  /// the logger on it. A session that fails to start must not leave the
  /// button stuck disabled -- `_starting` always clears in the `finally`,
  /// whether the attempt succeeded, failed, or the logger was already
  /// pushed.
  Future<void> _startOrResume() async {
    final controller = ref.read(activeSessionProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _starting = true);
    try {
      if (ref.read(activeSessionProvider).value == null) {
        await controller.start();
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const SessionLoggerScreen(),
      ));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final baseUrl = ref.watch(planRepositoryProvider).baseUrl;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        WeekStrip(
          daysPerWeek: plan.daysPerWeek,
          completedDates: ref.watch(completedDaysProvider).value ?? const {},
          today: DateTime.now(),
        ),
        const SizedBox(height: 14),
        SessionCard(
          plan: plan,
          hasActiveSession: ref.watch(activeSessionProvider).value != null,
          starting: _starting,
          onStart: _startOrResume,
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Exercises'),
        const SizedBox(height: 10),
        for (final exercise in plan.exercises) ...[
          _PlanExerciseCard(
            exercise: exercise,
            baseUrl: baseUrl,
            onGoToProfile: widget.onGoToProfile,
          ),
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
  const _PlanExerciseCard({
    required this.exercise,
    required this.baseUrl,
    this.onGoToProfile,
  });

  final PlanExercise exercise;
  final String baseUrl;
  final VoidCallback? onGoToProfile;

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
          ExerciseThumb(
            size: 48,
            baseUrl: baseUrl,
            thumbnailUrl: exercise.thumbnailUrl,
            equipment: exercise.equipment,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(exercise.name, style: theme.textTheme.titleMedium),
                    ),
                    TextButton(
                      key: Key('swap.open.${exercise.planExerciseId}'),
                      onPressed: () => showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => ExerciseSwapSheet(
                          planExerciseId: exercise.planExerciseId,
                          exerciseName: exercise.name,
                          onGoToProfile: onGoToProfile,
                        ),
                      ).then((swappedTo) {
                        if (swappedTo != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Swapped to $swappedTo')),
                          );
                        }
                      }),
                      child: const Text('Change'),
                    ),
                  ],
                ),
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

