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
import 'goal_target.dart';
import 'providers.dart';

/// Adds a lift goal in two steps: choose the exercise, then the target.
/// Closes on a save that lands; stays open, saying why, on one that does not.
///
/// What [showModalBottomSheet] would push, but through [_AddGoalSheetRoute],
/// so a tap on the scrim closes the sheet on either step.
Future<void> showAddGoalSheet(BuildContext context) {
  final navigator = Navigator.of(context);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    _AddGoalSheetRoute(
      builder: (_) => const _AddGoalSheet(),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      // Material's 48 dp would push a sheet sized to the room above the keyboard off the top (PT-22).
      showDragHandle: false,
      backgroundColor: context.fs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      isScrollControlled: true,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    ),
  );
}

/// The sheet's route, whose scrim closes it outright.
///
/// The target step holds the phone's back in a [PopScope] to step back to
/// the list, and the stock scrim asks that same [PopScope] (it calls
/// `Navigator.maybePop`), so a tap outside the sheet stepped back rather
/// than closing it. The scrim here pops the route itself, as a drag down
/// already does, keeping everything else the stock scrim has: its colour
/// animation, label, tap hint and semantics clip.
class _AddGoalSheetRoute extends ModalBottomSheetRoute<void> {
  _AddGoalSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.shape,
    super.modalBarrierColor,
    super.showDragHandle,
  });

  /// What a drag down does (BottomSheet's onClosing): a pop that does not
  /// ask the [PopScope].
  void _close() {
    if (isCurrent) navigator?.pop();
  }

  @override
  Widget buildModalBarrier() {
    final barrier = super.buildModalBarrier();
    return switch (barrier) {
      AnimatedModalBarrier() => AnimatedModalBarrier(
        color: barrier.color,
        dismissible: barrier.dismissible,
        semanticsLabel: barrier.semanticsLabel,
        barrierSemanticsDismissible: barrier.barrierSemanticsDismissible,
        clipDetailsNotifier: barrier.clipDetailsNotifier,
        semanticsOnTapHint: barrier.semanticsOnTapHint,
        onDismiss: _close,
      ),
      ModalBarrier() => ModalBarrier(
        color: barrier.color,
        dismissible: barrier.dismissible,
        semanticsLabel: barrier.semanticsLabel,
        barrierSemanticsDismissible: barrier.barrierSemanticsDismissible,
        clipDetailsNotifier: barrier.clipDetailsNotifier,
        semanticsOnTapHint: barrier.semanticsOnTapHint,
        onDismiss: _close,
      ),
      _ => barrier,
    };
  }
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

  /// A marked row is reloading the goals to open its goal; a second tap
  /// waits rather than opening it twice.
  bool _finding = false;

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
  /// Until then, or if it fails, a row is marked only by its option's own
  /// hasOpenGoal, and the server still refuses a second goal.
  Map<int, LiftGoal> _openGoals() => {
    for (final g in ref.watch(goalsProvider).value ?? const <LiftGoal>[])
      if (!g.reached) g.exerciseId: g,
  };

  /// The open goal the options list names for [exerciseId], when the goals
  /// list has not (it failed, is loading, or is stale).
  int? _markedGoalId(List<GoalOption> known, int exerciseId) {
    for (final o in known) {
      if (o.exerciseId == exerciseId && o.hasOpenGoal) return o.goalId;
    }
    return null;
  }

  /// A row's tap: its open goal when it has one, else step two. A goal the
  /// options mark but the loaded list lacks is looked up afresh first.
  VoidCallback _onRow(
    Map<int, LiftGoal> open,
    int exerciseId,
    String name,
    List<GoalOption> known,
  ) {
    final goal = open[exerciseId];
    if (goal != null) return () => _openGoal(goal);
    final goalId = _markedGoalId(known, exerciseId);
    if (goalId == null) return () => _pick(exerciseId, name, known);
    return () async {
      if (_finding) return;
      _finding = true;
      final container = ProviderScope.containerOf(context, listen: false);
      final found = await _findOpenGoal(container, goalId);
      _finding = false;
      if (!mounted) return;
      found == null ? _pick(exerciseId, name, known) : _openGoal(found);
    };
  }

  /// Goal [goalId] from a fresh goals list, if it is there and unreached.
  static Future<LiftGoal?> _findOpenGoal(
    ProviderContainer container,
    int goalId,
  ) async {
    try {
      container.invalidate(goalsProvider);
      final goals = await container.read(goalsProvider.future);
      for (final g in goals) {
        if (g.goalId == goalId && !g.reached) return g;
      }
    } catch (_) {
      // Not found, as far as the sheet can tell; the caller falls back.
    }
    return null;
  }

  /// The open goal a GOAL_EXISTS refusal names, or null.
  static int? _existingGoalId(Object error) => switch (error) {
    ApiException(code: 'GOAL_EXISTS', :final details)
        when details.isNotEmpty && details.first['goalId'] is int =>
      details.first['goalId'] as int,
    _ => null,
  };

  Future<void> _save() async {
    final picked = _picked!;
    final unit = ref.read(weightUnitProvider);
    // Capture the container before any await; the sheet can be dismissed
    // mid-save, making ref invalid. The container outlives the widget.
    final container = ProviderScope.containerOf(context, listen: false);
    final (sendKg, invalid) = goalTargetError(
      _target.text,
      unit,
      picked.bestKg,
    );
    if (sendKg == null) {
      setState(() => _error = invalid);
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
      // The lift has a goal the sheet did not know of: open it instead.
      final existingId = _existingGoalId(error);
      if (existingId != null) {
        container.invalidate(goalOptionsProvider);
        final goal = await _findOpenGoal(container, existingId);
        if (!mounted) return;
        if (goal != null) {
          _openGoal(goal);
          return;
        }
      }
      // The server knew a best the sheet did not (or a newer one).
      final best = goalErrorBestKg(error);
      if (best != null) container.invalidate(goalOptionsProvider);
      setState(() {
        if (best != null) {
          _picked = (
            exerciseId: picked.exerciseId,
            name: picked.name,
            bestKg: best,
          );
        }
        _busy = false;
        _error = goalErrorMessage(error, unit);
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
    // does, rather than closing the sheet and losing the chosen lift. Only
    // back is held while a save is in flight, as the arrow is. The scrim
    // and a drag down close the sheet outright, even mid-save; the save
    // still finishes: one that lands refreshes goalsProvider, and one that
    // fails goes unseen (the accepted pops-while-busy rule).
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
      error: (error, _) => _LoadFailed(
        message: userMessage(error),
        buttonKey: const Key('goal.options.retry'),
        onRetry: () => ref.invalidate(goalOptionsProvider),
      ),
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
                    goalSet: open.containsKey(o.exerciseId) || o.hasOpenGoal,
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
          error: (error, _) => _LoadFailed(
            message: userMessage(error),
            buttonKey: const Key('goal.search.retry'),
            onRetry: () => ref.invalidate(goalSearchProvider(_query)),
          ),
          data: (items) => items.isEmpty
              ? _Hint('No exercises match "$_query".')
              : ListView(
                  children: [
                    for (final e in items)
                      _PickRow(
                        key: Key('goal.result.${e.exerciseId}'),
                        title: e.name,
                        subtitle: null,
                        goalSet:
                            open.containsKey(e.exerciseId) ||
                            _markedGoalId(known, e.exerciseId) != null,
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

/// A list that could not load, in the sheet's list area: the kit's
/// FsRetry, centred, and scrollable so large text never overflows.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({
    required this.message,
    required this.buttonKey,
    required this.onRetry,
  });

  final String message;
  final Key buttonKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: FsRetry(message: message, buttonKey: buttonKey, onRetry: onRetry),
    ),
  );
}
