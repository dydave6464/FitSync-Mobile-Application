import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../domain/workout_plan.dart';

/// What the user chose to do with the finished workout.
///
/// [cancelled] is the whole reason this is a record rather than a bare
/// `int?`: "a new day at the end" and "never mind" are different answers,
/// and `dayNo: null` can only say one of them. "As a new day" is a row the
/// user taps, so dismissing the sheet -- swiping it down, tapping outside it
/// -- means none of the rows, the way dismissing any list of choices does.
/// Reading it as a new day mattered because it is not undoable: removing a
/// day from a custom plan is out of scope, so an accidental day stays.
///
/// [dayNo] is the day to replace, or null for a new day at the end. It is
/// null whenever [cancelled] is true, and the caller must write nothing at
/// all in that case rather than treating it as an append.
typedef AddToPlanChoice = ({bool cancelled, int? dayNo});

/// Where in the plan a finished workout should land, or that it should not.
Future<AddToPlanChoice> showAddToPlanSheet(
  BuildContext context,
  WorkoutPlan plan,
) async {
  final dayNumbers = <int>{for (final e in plan.exercises) e.dayNo}.toList()
    ..sort();

  final chosen = await showModalBottomSheet<AddToPlanChoice>(
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: t.text,
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
              onTap: () =>
                  Navigator.of(sheetContext)
                      .pop((cancelled: false, dayNo: null)),
            ),
            Divider(color: t.line2, height: 1),
            for (final dayNo in dayNumbers)
              Builder(
                builder: (_) {
                  final count = plan.exercises
                      .where((e) => e.dayNo == dayNo)
                      .length;
                  return ListTile(
                    key: Key('addToPlan.day.$dayNo'),
                    leading: Icon(Icons.swap_horiz, size: 20, color: t.text2),
                    title: Text('Day $dayNo'),
                    subtitle: Text(
                      'Replaces $count ${count == 1 ? 'exercise' : 'exercises'}',
                      style: TextStyle(fontSize: 12, color: t.text3),
                    ),
                    onTap: () =>
                        Navigator.of(sheetContext)
                            .pop((cancelled: false, dayNo: dayNo)),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  // A sheet closed without an answer -- the barrier, a swipe, the system back
  // gesture -- resolves null, and null is the dismissal.
  return chosen ?? const (cancelled: true, dayNo: null);
}
