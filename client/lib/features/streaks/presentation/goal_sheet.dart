import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../data/streaks_repository.dart';
import '../domain/streaks.dart';
import 'goal_sheet_route.dart';
import 'goal_target.dart';
import 'providers.dart';

/// One goal, opened from its card or from the add-goal sheet. It holds a
/// text field on its Change target step, so it is pushed as the add-goal
/// sheet is: sized for the keyboard, with no drag handle (PT-22), and a
/// scrim that closes it on either step.
Future<void> showGoalSheet(
  BuildContext context,
  LiftGoal goal,
  WeightUnit unit,
) => pushGoalSheet(context, (_) => _GoalSheet(goal: goal, unit: unit));

/// One goal, with Change target (an open goal only) and Delete.
///
/// Change target swaps the sheet in place for an edit step, checked as the
/// add-goal sheet checks a target. A reached goal cannot be changed: the
/// server refuses it (GOAL_REACHED), as raising it would reopen it beside a
/// newer goal for the same lift.
///
/// An open goal is deleted at once, with Undo in a SnackBar; a reached one
/// asks first, because adding it back would be refused as already met.
class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({required this.goal, required this.unit});

  final LiftGoal goal;
  final WeightUnit unit;

  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  final _target = TextEditingController();
  bool _busy = false;
  String? _error;

  /// On the Change target step, with the target it opened with as shown in
  /// the field.
  bool _editing = false;
  String _prefill = '';

  /// The best the edit step checks against: the goal's, or a newer one the
  /// server named in a GOAL_ALREADY_MET.
  late double? _bestKg = widget.goal.bestKg;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  void _startEdit() {
    _prefill = formatWeight(widget.goal.targetKg, widget.unit);
    _target.text = _prefill;
    setState(() {
      _editing = true;
      _error = null;
    });
  }

  void _endEdit() => setState(() {
    _editing = false;
    _error = null;
  });

  Future<void> _saveTarget() async {
    final unit = widget.unit;
    final navigator = Navigator.of(context);
    // The prefill is the target rounded into the user's unit; sent back as
    // it is, it would move the target (100 kg shows as 220.5 lb, which is
    // 100.02 kg). Unchanged, there is nothing to save.
    if (_target.text.trim() == _prefill) {
      navigator.pop();
      return;
    }
    final (sendKg, invalid) = goalTargetError(_target.text, unit, _bestKg);
    if (sendKg == null) {
      setState(() => _error = invalid);
      return;
    }
    // Captured before the await: the sheet can be dismissed mid-save.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(goalsRepositoryProvider)
          .changeTarget(goalId: widget.goal.goalId, targetKg: sendKg);
      container.invalidate(goalsProvider);
      if (mounted) navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Target changed')));
    } catch (error) {
      // Reached or gone since the card loaded: the card is stale.
      if (error case ApiException(code: 'GOAL_REACHED' || 'GOAL_NOT_FOUND')) {
        container.invalidate(goalsProvider);
      }
      if (!mounted) return;
      setState(() {
        _bestKg = goalErrorBestKg(error) ?? _bestKg;
        _busy = false;
        _error = goalErrorMessage(error, unit);
      });
    }
  }

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
    final media = MediaQuery.of(context);
    // The room above the keyboard, less headroom (not an app bar: the sheet
    // has none), as the add-goal sheet keeps; the steps scroll inside it.
    final maxHeight = math.max(
      160.0,
      media.size.height - media.viewInsets.bottom - media.padding.top - 56,
    );
    // The phone's back on the edit step returns to the goal, as the arrow
    // does; only back is held while a save is in flight. The scrim and a
    // drag down close the sheet outright.
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        _endEdit();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: _editing ? _editStep() : _viewStep(),
          ),
        ),
      ),
    );
  }

  Widget _viewStep() {
    final t = context.fs;
    final goal = widget.goal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          goal.exerciseName,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Target ${formatWeightWithUnit(goal.targetKg, widget.unit)}',
          style: TextStyle(fontSize: 13, color: t.text2),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          FsErrorLine(_error!, key: const Key('goal.deleteError')),
        ],
        const SizedBox(height: 16),
        if (!goal.reached) ...[
          FsButton(
            key: const Key('goal.changeTarget'),
            label: 'Change target',
            kind: FsButtonKind.secondary,
            onPressed: _busy ? null : _startEdit,
          ),
          const SizedBox(height: 10),
        ],
        FsButton(
          key: const Key('goal.delete'),
          label: 'Delete goal',
          kind: FsButtonKind.secondary,
          danger: true,
          busy: _busy,
          onPressed: _busy ? null : _delete,
        ),
      ],
    );
  }

  Widget _editStep() {
    final t = context.fs;
    final unit = widget.unit;
    final best = _bestKg;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('goal.edit.back'),
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: _busy ? null : _endEdit,
            ),
            Expanded(
              child: Text(
                widget.goal.exerciseName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          best == null
              ? 'Not logged yet'
              : 'Your best: ${formatWeightWithUnit(best, unit)}',
          style: TextStyle(fontSize: 13, color: t.text2),
        ),
        const SizedBox(height: 16),
        // Named for a screen reader: the field opens prefilled, so the
        // 'Target' placeholder never shows and cannot carry the name. A
        // Semantics label keeps the look of the add sheet's field.
        Semantics(
          label: 'Target',
          child: FsField(
            controller: _target,
            hint: 'Target',
            suffix: unit.api,
            fieldKey: const Key('goal.edit.target'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
        // A live region: a screen reader says why Save did not close the
        // sheet.
        if (_error != null) ...[
          const SizedBox(height: 10),
          FsErrorLine(_error!, key: const Key('goal.edit.error')),
        ],
        const SizedBox(height: 16),
        FsButton(
          key: const Key('goal.edit.save'),
          label: 'Save target',
          busy: _busy,
          onPressed: _busy ? null : _saveTarget,
        ),
      ],
    );
  }
}
