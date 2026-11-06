import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../data/streaks_repository.dart';
import '../domain/streaks.dart';
import 'providers.dart';

/// One goal, opened from its card or from the add-goal sheet.
Future<void> showGoalSheet(
  BuildContext context,
  LiftGoal goal,
  WeightUnit unit,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _GoalSheet(goal: goal, unit: unit),
  );
}

/// One goal, with Delete. There is no editing yet: delete and add another.
/// An open goal goes at once, with Undo in a SnackBar; a reached one asks
/// first, because adding it back would be refused as already met.
class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({required this.goal, required this.unit});

  final LiftGoal goal;
  final WeightUnit unit;

  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  bool _busy = false;
  String? _error;

  Future<bool> _confirmDelete() async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this goal?'),
        content: const Text(
          "You've reached it, so it can't be set again once it's gone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: dialog.fs.red),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _delete() async {
    final goal = widget.goal;
    if (goal.reached && !await _confirmDelete()) return;
    if (!mounted) return;
    // Captured before the await so invalidation succeeds even if the sheet
    // is dismissed while the delete is in flight, and Undo still works
    // after the sheet has gone.
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(goalsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.remove(goal.goalId);
      container.invalidate(goalsProvider);
      if (!goal.reached) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Goal deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _undo(repo, container, messenger, goal),
            ),
          ),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userMessage(error);
      });
    }
  }

  /// Adds the deleted goal back with the same lift and target. Static, as
  /// the sheet is long gone by the time Undo is tapped.
  static Future<void> _undo(
    GoalsRepository repo,
    ProviderContainer container,
    ScaffoldMessengerState messenger,
    LiftGoal goal,
  ) async {
    try {
      await repo.add(exerciseId: goal.exerciseId, targetKg: goal.targetKg);
      container.invalidate(goalsProvider);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(userMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.goal.exerciseName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Target ${formatWeightWithUnit(widget.goal.targetKg, widget.unit)}',
            style: TextStyle(fontSize: 13, color: t.text2),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            FsErrorLine(_error!, key: const Key('goal.deleteError')),
          ],
          const SizedBox(height: 16),
          FsButton(
            key: const Key('goal.delete'),
            label: 'Delete goal',
            kind: FsButtonKind.secondary,
            danger: true,
            busy: _busy,
            onPressed: _busy ? null : _delete,
          ),
        ],
      ),
    );
  }
}
