import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/widgets/fs_kit.dart';
import 'providers.dart';
import 'widgets/exercise_demo_body.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});

  final int exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(exerciseDetailProvider(exerciseId));
    final baseUrl = ref.watch(exerciseRepositoryProvider).baseUrl;

    return Scaffold(
      // A static title, not the loaded exercise's name: the body already
      // shows the name once as a headline, and repeating it in the app bar
      // produced two "findsOneWidget" matches for the same text (see the
      // test file for the assertions this keeps satisfied).
      appBar: AppBar(title: const Text('Exercise')),
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
