import 'package:flutter/material.dart';

import '../../../../core/widgets/fs_kit.dart';
import '../../domain/nutrition.dart';

/// The meal a food goes into, as a row of chips: the one way the log sheet,
/// Add manually and Snap a meal's confirm list draw this choice, as the
/// prototype does. A Wrap, so at large text a whole chip moves to the next
/// line instead of a segment breaking "Breakfast" mid-word. Each chip is
/// keyed by [keyPrefix] and its meal, e.g. `snap.meal.lunch`.
class MealChips extends StatelessWidget {
  const MealChips({super.key, required this.selected, required this.onSelected, required this.keyPrefix});

  final String selected;
  final ValueChanged<String> onSelected;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => FsTapRoom(
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in mealTypes)
          FsChip(
            key: Key('$keyPrefix.$m'),
            label: mealLabel(m),
            selected: selected == m,
            // One meal or another: heard as a radio group, not four toggles.
            exclusive: true,
            onTap: () => onSelected(m),
          ),
      ],
    ),
  );
}
