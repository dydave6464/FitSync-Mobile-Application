import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart' show FsCard, FsEyebrow;
import '../../domain/nutrition.dart';

class MealSection extends StatelessWidget {
  const MealSection({
    super.key,
    required this.mealType,
    required this.entries,
    required this.onAdd,
    required this.onDelete,
    this.enabled = true,
  });

  final String mealType;
  final List<FoodEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<FoodEntry> onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final subtotal = entries.fold<int>(0, (a, e) => a + e.kcal);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: FsEyebrow(mealLabel(mealType).toUpperCase())),
              Text('$subtotal kcal', style: TextStyle(fontSize: 12, color: t.text3)),
              IconButton(
                key: Key('meal.add.$mealType'),
                tooltip: 'Log ${mealLabel(mealType).toLowerCase()}',
                onPressed: enabled ? onAdd : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          for (final e in entries)
            FsCard(
              small: true,
              padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          [if (e.servingDesc != null) e.servingDesc!, if (e.servings != 1) '× ${formatServings(e.servings)}'].join(' '),
                          style: TextStyle(fontSize: 12, color: t.text3),
                        ),
                      ],
                    ),
                  ),
                  Text('${e.kcal} kcal', style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(
                    key: Key('entry.delete.${e.id}'),
                    tooltip: 'Remove ${e.name}',
                    // A pending entry has no server id yet to delete.
                    onPressed: enabled && e.id > 0 ? () => onDelete(e) : null,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
