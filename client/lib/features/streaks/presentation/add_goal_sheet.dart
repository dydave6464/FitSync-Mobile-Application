import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../profile/presentation/providers.dart' show weightUnitProvider;
import '../domain/streaks.dart';
import 'goal_sheet.dart';
import 'providers.dart';

/// Adds a lift goal in two steps: choose the exercise, then the target.
/// Closes on a save that lands; stays open, saying why, on one that does not.
Future<void> showAddGoalSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    isScrollControlled: true,
    builder: (_) => const _AddGoalSheet(),
  );
}

/// The exercise chosen in step one, with the user's best when known.
typedef _Picked = ({int exerciseId, String name, double? bestKg});

class _AddGoalSheet extends ConsumerStatefulWidget {
  const _AddGoalSheet();

  @override
  ConsumerState<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends ConsumerState<_AddGoalSheet> {
  final _search = TextEditingController();
  final _target = TextEditingController();
  Timer? _debounce;
  String _query = '';
  _Picked? _picked;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _target.dispose();
    super.dispose();
  }

  /// The same 300 ms wait as the exercise catalogue's search, so each
  /// keystroke is not a request.
  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  /// A catalogue result carries no best of the user's; the lifted-before
  /// list does, so a lift found by search still gets it.
  void _pick(int exerciseId, String name, List<GoalOption> known) {
    double? best;
    for (final o in known) {
      if (o.exerciseId == exerciseId) best = o.bestKg;
    }
    setState(() {
      _picked = (exerciseId: exerciseId, name: name, bestKg: best);
      _error = null;
    });
  }

  /// A lift with an unreached goal can take no second one (the server
  /// answers GOAL_EXISTS), so its row opens that goal instead: this sheet
  /// closes and the goal's own sheet opens in its place.
  void _openGoal(LiftGoal goal) {
    final navigator = Navigator.of(context);
    final unit = ref.read(weightUnitProvider);
    navigator.pop();
    showGoalSheet(navigator.context, goal, unit);
  }

  /// The user's unreached goals by exercise, once the list has loaded.
  /// Until then, or if it fails, every row is offered as before and the
  /// server still refuses a second goal.
  Map<int, LiftGoal> _openGoals() => {
    for (final g in ref.watch(goalsProvider).value ?? const <LiftGoal>[])
      if (!g.reached) g.exerciseId: g,
  };

  /// A row's tap: its open goal when it has one, else step two.
  VoidCallback _onRow(
    Map<int, LiftGoal> open,
    int exerciseId,
    String name,
    List<GoalOption> known,
  ) {
    final goal = open[exerciseId];
    return goal == null
        ? () => _pick(exerciseId, name, known)
        : () => _openGoal(goal);
  }

  Future<void> _save() async {
    final picked = _picked!;
    final unit = ref.read(weightUnitProvider);
    // Capture the container before any await; the sheet can be dismissed
    // mid-save, making ref invalid. The container outlives the widget.
    final container = ProviderScope.containerOf(context, listen: false);
    final kg = parseWeight(_target.text, unit);
    if (kg == null) {
      setState(() => _error = 'Enter a target weight.');
      return;
    }
    // Rounded to what set_logs and the POST body actually carry (DECIMAL
    // 6,2): a target that only beats the best before rounding would pass
    // this check on the unrounded value, then be refused by the server on
    // the rounded one -- in kilograms, whatever the user's unit is.
    final sendKg = double.parse(kg.toStringAsFixed(2));
    if (sendKg <= 0) {
      setState(() => _error = 'Enter a target weight.');
      return;
    }
    if (sendKg < 0.5 || sendKg > 999.99) {
      setState(
        () => _error =
            'Enter a target between ${formatWeightWithUnit(0.5, unit)} and '
            '${formatWeightWithUnit(999.99, unit)}.',
      );
      return;
    }
    final best = picked.bestKg;
    if (best != null && sendKg <= best) {
      setState(
        () => _error =
            'Your best is already ${formatWeightWithUnit(best, unit)}.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(goalsRepositoryProvider)
          .add(exerciseId: picked.exerciseId, targetKg: sendKg);
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
    // Watched here, whichever step is showing, so the list is still loaded
    // when a search result needs its best.
    final options = ref.watch(goalOptionsProvider);
    final picked = _picked;
    final media = MediaQuery.of(context);
    // Calculate the space left above the keyboard, accounting for headroom
    // and padding. This ensures the sheet fits and the target field stays on screen.
    final roomAboveKeyboard =
        media.size.height - media.viewInsets.bottom - media.padding.top - 56; // Headroom kept above the keyboard, not an app bar -- the sheet has none.
    final height = math.max(
      160.0,
      math.min(media.size.height * 0.7, roomAboveKeyboard),
    );
    // The phone's back on the target step goes back a step, as the arrow
    // does, rather than closing the sheet and losing the chosen lift. Held
    // while a save is in flight, as the arrow is.
    return PopScope(
      canPop: picked == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        setState(() {
          _picked = null;
          _error = null;
        });
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + media.viewInsets.bottom),
        child: SizedBox(
          height: height,
          child: picked == null ? _chooseStep(options) : _targetStep(picked),
        ),
      ),
    );
  }

  Widget _chooseStep(AsyncValue<List<GoalOption>> options) {
    final t = context.fs;
    final known = options.value ?? const <GoalOption>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'New lift goal',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 12),
        FsField(
          controller: _search,
          hint: 'Search exercises',
          fieldKey: const Key('goal.search'),
          icon: Icons.search,
          onChanged: _onSearch,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _query.isEmpty
              ? _liftedBefore(options)
              : _searchResults(known),
        ),
      ],
    );
  }

  Widget _liftedBefore(AsyncValue<List<GoalOption>> options) {
    final unit = ref.watch(weightUnitProvider);
    final open = _openGoals();
    return options.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Hint(userMessage(error)),
      data: (list) => list.isEmpty
          ? const _Hint('Search for an exercise to set a goal.')
          : ListView(
              children: [
                const FsEyebrow('Lifted before'),
                const SizedBox(height: 4),
                for (final o in list)
                  _PickRow(
                    key: Key('goal.option.${o.exerciseId}'),
                    title: o.name,
                    subtitle: 'Best ${formatWeightWithUnit(o.bestKg, unit)}',
                    goalSet: open.containsKey(o.exerciseId),
                    onTap: _onRow(open, o.exerciseId, o.name, list),
                  ),
              ],
            ),
    );
  }

  Widget _searchResults(List<GoalOption> known) {
    final open = _openGoals();
    return ref
        .watch(goalSearchProvider(_query))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Hint(userMessage(error)),
          data: (items) => items.isEmpty
              ? _Hint('No exercises match "$_query".')
              : ListView(
                  children: [
                    for (final e in items)
                      _PickRow(
                        key: Key('goal.result.${e.exerciseId}'),
                        title: e.name,
                        subtitle: null,
                        goalSet: open.containsKey(e.exerciseId),
                        onTap: _onRow(open, e.exerciseId, e.name, known),
                      ),
                  ],
                ),
        );
  }

  Widget _targetStep(_Picked picked) {
    final t = context.fs;
    final unit = ref.watch(weightUnitProvider);
    final best = picked.bestKg;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('goal.back'),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _picked = null;
                        _error = null;
                      }),
              ),
              Expanded(
                child: Text(
                  picked.name,
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
          FsField(
            controller: _target,
            hint: 'Target',
            suffix: unit.api,
            fieldKey: const Key('goal.target'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          // A live region: a screen reader says why Save did not close the
          // sheet.
          if (_error != null) ...[
            const SizedBox(height: 10),
            FsErrorLine(_error!, key: const Key('goal.error')),
          ],
          const SizedBox(height: 16),
          FsButton(
            key: const Key('goal.save'),
            label: 'Save goal',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.goalSet = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// The lift already has an unreached goal; the row opens it.
  final bool goalSet;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    // One button per row, at least a thumb's 48 dp even with no subtitle.
    return Semantics(
      container: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 11.5, color: t.text3),
                        ),
                      ],
                    ],
                  ),
                ),
                if (goalSet) ...[
                  const SizedBox(width: 8),
                  const FsTag('Goal set'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.fs.text2),
        ),
      ),
    );
  }
}
