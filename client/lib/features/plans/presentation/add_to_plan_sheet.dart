import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../domain/workout_plan.dart';

/// Where in the plan a finished workout should land.
///
/// Resolves to the `dayNo` to replace, or null for "a new day at the end".
/// Dismissing resolves to null as well, which is the same as choosing a new
/// day -- deliberately: the caller reached this sheet by the user already
/// accepting "add to my plan", so a dismissal is a choice about WHERE, not a
/// change of mind about WHETHER. A caller that needs to distinguish them
/// should ask before opening this.
Future<int?> showAddToPlanSheet(BuildContext context, WorkoutPlan plan) async {
  final dayNumbers = <int>{for (final e in plan.exercises) e.dayNo}.toList()
    ..sort();

  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final t = sheetContext.fs;

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Add to ${plan.name}',
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: t.text,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('addToPlan.newDay'),
              leading: Icon(Icons.add, size: 20, color: t.accent),
              title: const Text('As a new day'),
              subtitle: Text(
                'Day ${dayNumbers.length + 1} of your plan',
                style: TextStyle(fontSize: 12, color: t.text3),
              ),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            Divider(color: t.line2, height: 1),
            for (final dayNo in dayNumbers)
              Builder(builder: (_) {
                final count =
                    plan.exercises.where((e) => e.dayNo == dayNo).length;
                return ListTile(
                  key: Key('addToPlan.day.$dayNo'),
                  leading: Icon(Icons.swap_horiz, size: 20, color: t.text2),
                  title: Text('Day $dayNo'),
                  subtitle: Text(
                    'Replaces $count ${count == 1 ? 'exercise' : 'exercises'}',
                    style: TextStyle(fontSize: 12, color: t.text3),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(dayNo),
                );
              }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
