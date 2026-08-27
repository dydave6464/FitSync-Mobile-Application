import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import 'providers.dart';

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
        data: (exercise) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (exercise.animationUrl != null)
              AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  '$baseUrl${exercise.animationUrl}',
                  fit: BoxFit.contain,
                  // Flutter's Image plays animated GIFs natively — no package.
                  // flutter_lints (this SDK) flags __/___ as unnecessary now
                  // that repeated `_` is a valid wildcard for each parameter.
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.fitness_center, size: 48),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(exercise.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(exercise.muscleGroup)),
                if (exercise.equipment != null) Chip(label: Text(exercise.equipment!)),
              ],
            ),
            const SizedBox(height: 24),
            if (exercise.cues.isNotEmpty) ...[
              Text('How to perform', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < exercise.cues.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('${i + 1}. ${exercise.cues[i]}'),
                ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
