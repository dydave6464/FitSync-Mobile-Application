import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

import '../exercise_thumb.dart';

import '../../domain/exercise.dart';
import '../../domain/exercise_labels.dart';

class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    super.key,
    required this.exercise,
    required this.baseUrl,
    required this.onTap,
    required this.selected,
    required this.onInfo,
  });

  final ExerciseSummary exercise;
  final String baseUrl;
  final VoidCallback onTap;

  /// Whether this exercise is in the workout being put together.
  final bool selected;

  /// Opens the exercise's demo: the row's own tap means "pick".
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return ListTile(
      onTap: onTap,
      // Says "selected" to a screen reader, as the Recent cards do; the tick
      // alone was drawn, not said. ListTile would also recolour a selected
      // row's words and icons, but the tick is what shows a pick here, so
      // the icons and the line under the name keep their own colours.
      selected: selected,
      iconColor: WidgetStateColor.resolveWith((_) => t.text2),
      // The kit's thumb: rounded, with the themed equipment placeholder for
      // an exercise with no artwork or one that will not load.
      leading: ExerciseThumb(
        size: 56,
        baseUrl: baseUrl,
        thumbnailUrl: exercise.thumbnailUrl,
        equipment: exercise.equipment,
      ),
      title: Text(exerciseDisplayName(exercise.name)),
      // The warning gets a line of its own and is never cut: it is the
      // safety reason, and sharing one ellipsized line with the muscle and
      // equipment lost it at large text and pushed them out at any size.
      isThreeLine: exercise.contraindicated,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (exercise.contraindicated)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.shield_outlined,
                  key: Key('tile.risk.${exercise.exerciseId}'),
                  size: 14,
                  color: t.red,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Loads an injury you reported',
                    style: TextStyle(color: t.text3),
                  ),
                ),
              ],
            ),
          Text(
            [
              muscleLabel(exercise.muscleGroup),
              if (exercise.equipment != null)
                equipmentLabel(exercise.equipment!),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.text3),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('tile.info.${exercise.exerciseId}'),
            tooltip: 'About ${exerciseDisplayName(exercise.name)}',
            onPressed: onInfo,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(Icons.info_outline, color: t.text2),
          ),
          _SelectMark(
            key: Key('tile.select.${exercise.exerciseId}'),
            selected: selected,
          ),
        ],
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
