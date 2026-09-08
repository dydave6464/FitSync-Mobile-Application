import 'package:flutter/material.dart';

import '../../domain/exercise.dart';
import '../equipment_icon.dart';

/// The animation, chips and "How to perform" list for one exercise.
///
/// Extracted from [ExerciseDetailScreen] (`../exercise_detail_screen.dart`)
/// unchanged, so it can also back the in-session view -- the only things
/// that differ mid-workout are what wraps it (app bar, loading/error
/// branches) and the optional [header] shown above the name.
class ExerciseDemoBody extends StatelessWidget {
  const ExerciseDemoBody({
    super.key,
    required this.exercise,
    this.baseUrl,
    this.header,
  });

  final ExerciseDetail exercise;
  final String? baseUrl;

  /// Rendered above the name -- e.g. the in-session position counter and
  /// prescription. Absent on the Browse tab's plain detail screen.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return ListView(
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
              errorBuilder: (_, _, _) => Center(
                child: Icon(equipmentIcon(exercise.equipment), size: 48),
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (header != null) ...[
          header!,
          const SizedBox(height: 8),
        ],
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
    );
  }
}
