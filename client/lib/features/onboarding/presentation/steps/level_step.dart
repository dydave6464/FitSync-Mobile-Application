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
const _levels = <({String value, String label})>[
  (value: 'beginner', label: 'Beginner'),
  (value: 'intermediate', label: 'Intermediate'),
];

/// `training_location` ENUM values.
///
/// Behind a picker rather than on the step: the design gives location a single
/// row at the foot of the screen, so a second chip strip cannot compete with
/// the equipment set — the one place on this step where chips mean
/// "choose several".
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

  String get _locationLabel {
    for (final location in _locations) {
      if (location.value == value.trainingLocation) return location.label;
    }
    return 'Not set';
  }

  Future<void> _pickLocation(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final location in _locations)
              ListTile(
                key: Key('location.${location.value}'),
                // The app theme insets tile content by 4dp, which reads as
                // padding only inside a card that brings its own. In a sheet
                // flush with the screen it puts the labels against the edge,
                // so this matches the 20dp the swap sheet uses.
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(location.label),
                trailing: location.value == value.trainingLocation
                    ? Icon(Icons.check, size: 18, color: sheet.fs.accent)
                    : null,
                onTap: () => Navigator.of(sheet).pop(location.value),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(value.copyWith(trainingLocation: picked));
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
        Text('Your level & equipment', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 22),
        const FsEyebrow('Experience'),
        const SizedBox(height: 10),
        FsSegmented(
          options: _levels,
          selected: value.fitnessLevel,
          onSelected: (level) => onChanged(value.copyWith(fitnessLevel: level)),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(child: FsEyebrow('Available equipment')),
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
          data: (options) => options.isEmpty
              ? Text(
                  'No equipment options are available right now.',
                  style: TextStyle(fontSize: 11, color: t.text3),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in options)
                      FsChip(
                        key: Key('equipment.${option.equipmentId}'),
                        label: option.name,
                        selected: value.equipmentIds.contains(
                          option.equipmentId,
                        ),
                        showCheck: true,
                        onTap: () => _toggleEquipment(option.equipmentId),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 22),
        FsCard(
          key: const Key('trainingLocation'),
          small: true,
          onTap: () => _pickLocation(context),
          child: Row(
            children: [
              Icon(Icons.home_outlined, size: 18, color: t.text2),
              const SizedBox(width: 11),
              const Expanded(child: Text('Training location',
                  style: TextStyle(fontSize: 13.5))),
              Text(
                _locationLabel,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: value.trainingLocation == null ? t.text3 : t.text,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 16, color: t.text3),
            ],
          ),
        ),
      ],
    );
  }
}
