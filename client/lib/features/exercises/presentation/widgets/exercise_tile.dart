import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

import '../equipment_icon.dart';

import '../../domain/exercise.dart';

class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    super.key,
    required this.exercise,
    required this.baseUrl,
    required this.onTap,
    this.selected,
  });

  final ExerciseSummary exercise;
  final String baseUrl;
  final VoidCallback onTap;

  /// Whether this exercise is in the workout being put together, or null when
  /// the list is being browsed rather than picked from.
  ///
  /// Nullable rather than defaulting to false: "not chosen" and "there is
  /// nothing to choose for" look different, and a tick on the Browse tab
  /// would promise a basket that does not exist there.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 56,
        height: 56,
        child: exercise.thumbnailUrl == null
            ? _ThumbPlaceholder(equipment: exercise.equipment)
            : Image.network(
                '$baseUrl${exercise.thumbnailUrl}',
                fit: BoxFit.cover,
                // One unreachable thumbnail must not take the row down with it.
                errorBuilder: (_, _, _) =>
                    _ThumbPlaceholder(equipment: exercise.equipment),
              ),
      ),
      title: Text(exercise.name),
      subtitle: Row(
        children: [
          if (exercise.contraindicated) ...[
            Icon(
              Icons.shield_outlined,
              key: Key('tile.risk.${exercise.exerciseId}'),
              size: 14,
              color: context.fs.red,
            ),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              [
                if (exercise.contraindicated) 'Loads an injury you reported',
                exercise.muscleGroup,
                if (exercise.equipment != null) exercise.equipment!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: selected == null
          ? const Icon(Icons.chevron_right)
          : _SelectMark(
              key: Key('tile.select.${exercise.exerciseId}'),
              selected: selected!,
            ),
    );
  }
}

/// The circular add/remove mark the prototype draws on a picked row.
class _SelectMark extends StatelessWidget {
  const _SelectMark({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.accent : t.surface2,
        border: Border.all(color: selected ? Colors.transparent : t.line2),
      ),
      child: Icon(
        selected ? Icons.check : Icons.add,
        size: 16,
        color: selected ? t.onAccent : t.text2,
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder({this.equipment});

  final String? equipment;

  @override
  Widget build(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(equipmentIcon(equipment), size: 20),
      );
}
