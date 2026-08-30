import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
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
const _levels = <({String value, String label, String blurb, IconData icon})>[
  (
    value: 'beginner',
    label: 'Beginner',
    blurb: 'New to training, or coming back after a long break',
    icon: Icons.eco_outlined,
  ),
  (
    value: 'intermediate',
    label: 'Intermediate',
    blurb: 'Training consistently and comfortable with the basic lifts',
    icon: Icons.trending_up,
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
    final t = context.fs;
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
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
        const SizedBox(height: 20),
        for (final level in _levels) ...[
          FsCard(
            key: Key('level.${level.value}'),
            small: true,
            accent: value.fitnessLevel == level.value,
            onTap: () => onChanged(value.copyWith(fitnessLevel: level.value)),
            child: Row(
              children: [
                FsIconTile(
                  icon: level.icon,
                  selected: value.fitnessLevel == level.value,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(level.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        level.blurb,
                        style: TextStyle(fontSize: 11, color: t.text3),
                      ),
                    ],
                  ),
                ),
                FsRadioDot(selected: value.fitnessLevel == level.value),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 14),
        const FsEyebrow('Where do you train?'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final location in _locations)
              FsChip(
                key: Key('location.${location.value}'),
                label: location.label,
                selected: value.trainingLocation == location.value,
                onTap: () =>
                    onChanged(value.copyWith(trainingLocation: location.value)),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const FsEyebrow('Available equipment'),
            FsTag('${value.equipmentIds.length} selected'),
          ],
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
                FsButton(
                  label: 'Retry',
                  small: true,
                  kind: FsButtonKind.secondary,
                  onPressed: () => ref.invalidate(equipmentOptionsProvider),
                ),
              ],
            ),
          ),
          // The server now returns the curated list in display order, and
          // this step renders it verbatim.
          data: (options) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                FsChip(
                  key: Key('equipment.${option.equipmentId}'),
                  label: option.name,
                  selected: value.equipmentIds.contains(option.equipmentId),
                  showCheck: true,
                  onTap: () => _toggleEquipment(option.equipmentId),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
