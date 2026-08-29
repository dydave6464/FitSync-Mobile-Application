import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../../profile/presentation/providers.dart';

/// The answers step 3 collects.
class LevelAnswers {
  const LevelAnswers({
    this.fitnessLevel,
    this.equipmentIds = const [],
    this.trainingLocation,
  });

  final String? fitnessLevel;

  /// The complete set the user owns. The server replaces this wholesale, so
  /// it is never a delta.
  final List<int> equipmentIds;

  final String? trainingLocation;

  LevelAnswers copyWith({
    String? fitnessLevel,
    List<int>? equipmentIds,
    String? trainingLocation,
  }) =>
      LevelAnswers(
        fitnessLevel: fitnessLevel ?? this.fitnessLevel,
        equipmentIds: equipmentIds ?? this.equipmentIds,
        trainingLocation: trainingLocation ?? this.trainingLocation,
      );
}

/// `fitness_level` ENUM values. The schema offers two; there is no "advanced".
const _levels = <({String value, String label, String blurb})>[
  (
    value: 'beginner',
    label: 'Beginner',
    blurb: 'New to training, or coming back after a long break',
  ),
  (
    value: 'intermediate',
    label: 'Intermediate',
    blurb: 'Training consistently and comfortable with the basic lifts',
  ),
];

/// `training_location` ENUM values.
const _locations = <({String value, String label})>[
  (value: 'home_gym', label: 'Home gym'),
  (value: 'commercial_gym', label: 'Commercial gym'),
  (value: 'both', label: 'Both'),
  (value: 'other', label: 'Somewhere else'),
];

/// Step 3: experience, equipment and where the training happens.
///
/// Reads the equipment lookup because that list belongs to the server, not to
/// the design — but still saves nothing and knows nothing about its scaffold.
class LevelStep extends ConsumerWidget {
  const LevelStep({super.key, required this.value, required this.onChanged});

  final LevelAnswers value;
  final ValueChanged<LevelAnswers> onChanged;

  void _toggleEquipment(int equipmentId) {
    final next = [...value.equipmentIds];
    // remove() reports whether it was there, so this is one pass either way.
    if (!next.remove(equipmentId)) next.add(equipmentId);
    onChanged(value.copyWith(equipmentIds: next));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final equipment = ref.watch(equipmentOptionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Your experience', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Sets your starting volume and how quickly it climbs.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final level in _levels)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: Key('level.${level.value}'),
              selected: value.fitnessLevel == level.value,
              title: Text(level.label),
              subtitle: Text(level.blurb),
              trailing: value.fitnessLevel == level.value
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () => onChanged(value.copyWith(fitnessLevel: level.value)),
            ),
          ),
        const SizedBox(height: 24),
        Text('Where do you train?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final location in _locations)
              ChoiceChip(
                key: Key('location.${location.value}'),
                label: Text(location.label),
                selected: value.trainingLocation == location.value,
                onSelected: (_) =>
                    onChanged(value.copyWith(trainingLocation: location.value)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text('What equipment can you use?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Leave everything unticked if you are training with bodyweight only.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        equipment.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(describeError(error), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(equipmentOptionsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          // Rendered straight from the response. The catalogue seed decides
          // what is in the `equipment` table, and it does not necessarily
          // match the names in the design.
          data: (options) => Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in options)
                FilterChip(
                  key: Key('equipment.${option.equipmentId}'),
                  label: Text(option.name),
                  selected: value.equipmentIds.contains(option.equipmentId),
                  onSelected: (_) => _toggleEquipment(option.equipmentId),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
