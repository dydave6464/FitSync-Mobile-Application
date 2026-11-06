import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/exercise.dart';
import '../../sessions/presentation/workout_draft.dart';
import 'providers.dart';
import 'widgets/exercise_demo_body.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId, this.pick});

  final int exerciseId;

  /// The library row this was opened from, when the library is picking a
  /// workout. Non-null adds a button to put it in the workout, or take it
  /// back out. Null -- the Plan tab -- shows the demo alone.
  final ExerciseSummary? pick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(exerciseDetailProvider(exerciseId));
    final baseUrl = ref.watch(exerciseRepositoryProvider).baseUrl;
    final t = context.fs;
    final picked = pick;
    final held =
        picked != null &&
        ref.watch(workoutDraftProvider).holds(picked.exerciseId);

    return Scaffold(
      // A static title, not the loaded exercise's name: the body already
      // shows the name once as a headline, and repeating it in the app bar
      // produced two "findsOneWidget" matches for the same text (see the
      // test file for the assertions this keeps satisfied).
      appBar: AppBar(title: const Text('Exercise')),
      bottomNavigationBar: picked == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The library row's warning, said again where the choice
                  // is made, so no path adds this exercise without it.
                  if (picked.contraindicated) ...[
                    _RiskLine(t: t),
                    const SizedBox(height: 10),
                  ],
                  FsButton(
                    key: const Key('detail.pick'),
                    label: held ? 'Remove from workout' : 'Add to workout',
                    kind: held ? FsButtonKind.secondary : FsButtonKind.primary,
                    onPressed: () =>
                        ref.read(workoutDraftProvider.notifier).toggle(picked),
                  ),
                ],
              ),
            ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FsRetry(
          fullScreen: true,
          message: userMessage(error),
          onRetry: () => ref.invalidate(exerciseDetailProvider(exerciseId)),
        ),
        data: (exercise) =>
            ExerciseDemoBody(exercise: exercise, baseUrl: baseUrl),
      ),
    );
  }
}

/// The library row's shield line: the same icon and words as ExerciseTile's.
class _RiskLine extends StatelessWidget {
  const _RiskLine({required this.t});

  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.shield_outlined,
          key: const Key('detail.risk'),
          size: 14,
          color: t.red,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'Loads an injury you reported',
            style: TextStyle(fontSize: 12.5, color: t.text2),
          ),
        ),
      ],
    );
  }
}
