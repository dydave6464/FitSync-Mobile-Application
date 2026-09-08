import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
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
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 40),
                const SizedBox(height: 12),
                Text(
                  error is ApiException ? error.message : 'Something went wrong.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(exerciseDetailProvider(exerciseId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (exercise) => ExerciseDemoBody(exercise: exercise, baseUrl: baseUrl),
      ),
    );
  }
}
