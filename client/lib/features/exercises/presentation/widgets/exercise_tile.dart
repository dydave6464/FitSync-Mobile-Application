import 'package:flutter/material.dart';

import '../../domain/exercise.dart';

class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    super.key,
    required this.exercise,
    required this.baseUrl,
    required this.onTap,
  });

  final ExerciseSummary exercise;
  final String baseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 56,
        height: 56,
        child: exercise.thumbnailUrl == null
            ? const _ThumbPlaceholder()
            : Image.network(
                '$baseUrl${exercise.thumbnailUrl}',
                fit: BoxFit.cover,
                // One unreachable thumbnail must not take the row down with it.
                errorBuilder: (_, _, _) => const _ThumbPlaceholder(),
              ),
      ),
      title: Text(exercise.name),
      subtitle: Text(
        [exercise.muscleGroup, if (exercise.equipment != null) exercise.equipment!]
            .join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.fitness_center, size: 20),
      );
}
