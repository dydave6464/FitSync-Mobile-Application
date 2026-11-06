import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
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

/// One goal, with Delete. There is no editing: delete and add another.
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

  Future<void> _delete() async {
    // Captured before the await so invalidation succeeds even if the sheet
    // is dismissed while the delete is in flight.
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = ref.read(goalsRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.remove(widget.goal.goalId);
      container.invalidate(goalsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userMessage(error);
      });
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
