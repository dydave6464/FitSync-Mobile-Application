import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/providers.dart'
    show exerciseRepositoryProvider;
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../plans/domain/workout_plan.dart';
import '../../plans/presentation/providers.dart';
import '../../profile/presentation/providers.dart';
import '../domain/active_session.dart';
import 'in_session_exercise_screen.dart';
import 'providers.dart';
import 'widgets/exercise_jump_sheet.dart';
import 'widgets/exercise_log_panel.dart';
import 'widgets/rest_timer.dart';

/// The active workout, one exercise at a time: its set table, Continue to
/// the next, and the jump sheet for anything out of order.
class SessionLoggerScreen extends ConsumerStatefulWidget {
  const SessionLoggerScreen({super.key});

  @override
  ConsumerState<SessionLoggerScreen> createState() => _SessionLoggerScreenState();
}

class _SessionLoggerScreenState extends ConsumerState<SessionLoggerScreen> {
  static const _restDuration = Duration(seconds: 90);

  /// Which exercise is on screen.
  ///
  /// Read through a clamp rather than corrected on write: the active plan can
  /// change under a resumed session, and an index left past the end of a
  /// shortened plan would throw on the next build.
  int _index = 0;
  bool _resting = false;

  /// The session as last seen from the controller.
  ///
  /// complete() and abandon() clear the controller the moment the server
  /// confirms, but this screen stays mounted until its route pops -- with the
  /// summary dialog sitting over it. Falling back to the loading spinner in
  /// that gap would flash a loading screen behind the summary of a workout
  /// that has just finished, so the last session seen is kept and rendered
  /// until the route goes away.
  ActiveSession? _lastSeenSession;

  /// Guards Finish against a second tap landing while the first request is
  /// still in flight. Without it, a second call would reach the controller's
  /// complete() a second time -- either double-dispatching to the server, or,
  /// once the first has resolved and cleared the session, hitting the
  /// controller's _current getter and throwing a raw StateError.
  bool _finishing = false;

  /// Clamped, because [startedAt] is the SERVER's NOW() while [DateTime.now]
  /// is the phone's. A phone clock behind the server makes the difference
  /// negative, and POST /complete rejects a negative durationMin with
  /// 400 DURATION_INVALID -- the one failure mode where a session genuinely
  /// cannot be finished from the phone. The upper bound is the route's own.
  ///
  /// The clamp is a guard, not a correction, and it hid a real defect for a
  /// while: the server was sending startedAt eight hours in the future on a
  /// UTC+8 host, so every workout read "0 min elapsed" and every completed
  /// session stored durationMin 0. That was a server-side timezone bug --
  /// see SESSION_COLUMNS in src/db/sessions.js -- and is fixed there. A
  /// clamp that silently swallows a whole class of wrong answers is worth
  /// being suspicious of when the number it produces is always the bound.
  int _elapsedMinutes(DateTime? startedAt) {
    if (startedAt == null) return 0;
    return DateTime.now().difference(startedAt).inMinutes.clamp(0, 1440);
  }

  /// The session was closed by someone/something else -- another device, an
  /// earlier tap whose response was lost, or a second Finish/Discard racing
  /// the first and hitting the controller's _current getter after the first
  /// already cleared it. Staying here would leave a screen editing a session
  /// that accepts no writes, so refetch and get out.
  void _handleAlreadyClosed(ScaffoldMessengerState messenger) {
    ref.invalidate(activeSessionProvider);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('This session was already finished.')),
    );
  }

  /// A set write the server refused because the session is no longer in
  /// progress. Spec section 8: the logger closes and the Plan tab refetches,
  /// rather than leaving a screen editing a session that accepts no writes.
  ///
  /// [SetRow]'s own blanket catch would otherwise turn the 409 into an inline
  /// Retry that can never succeed -- a session closed on another device would
  /// leave the user tapping it forever. Nothing is rethrown once this handles
  /// it: SetRow clears its busy flag as the route pops.
  bool _handledSetWriteClosure(
    ApiException error,
    ScaffoldMessengerState messenger,
  ) {
    if (error.code != 'SESSION_NOT_IN_PROGRESS') return false;
    if (mounted) _handleAlreadyClosed(messenger);
    return true;
  }

  /// Opens the jump sheet and moves to whatever it returns.
  ///
  /// [current] is the clamped index, so the row highlighted as current is
  /// always one that exists.
  /// Saves the unit chosen on the set table's header.
  ///
  /// A preference, not a session mode: nobody wants to re-pick this every
  /// workout, so it goes to the account. A failed write leaves the display on
  /// the old unit, which is honest -- the toggle reflects stored state rather
  /// than optimistically flipping and silently reverting.
  Future<void> _setUnit(WeightUnit unit) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profileProvider.notifier).patch({'weightUnit': unit.api});
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    }
  }

  Future<void> _jumpTo(
    List<PlanExercise> exercises,
    ActiveSession? session,
    int current,
  ) async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.fs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => ExerciseJumpSheet(
        exercises: exercises,
        session: session,
        currentIndex: current,
      ),
    );
    if (chosen != null && mounted) setState(() => _index = chosen);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final session = ref.read(activeSessionProvider).value;
    if (session == null) return;

    setState(() => _finishing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final done = await ref
          .read(activeSessionProvider.notifier)
          .complete(_elapsedMinutes(session.startedAt));
      if (!mounted) return;
      await _showSummary(done);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'SESSION_NOT_IN_PROGRESS') {
        // Closed somewhere else -- another device, or an earlier tap whose
        // response was lost. Staying here would leave a screen editing a
        // session that accepts no writes, so refetch and get out.
        _handleAlreadyClosed(messenger);
        return;
      }
      // Anything else: the session stays in progress and remains resumable,
      // so nothing is lost -- the worst case is finishing it on next launch.
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } on StateError {
      // The controller's _current contract: state was already null by the
      // time this call reached it (e.g. a first Finish tap already resolved,
      // or an in-flight completion beat this one to the punch). Same
      // resolution as the 409 above -- never let the raw error through.
      if (!mounted) return;
      _handleAlreadyClosed(messenger);
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _showSummary(ActiveSession done) async {
    final unit = ref.read(weightUnitProvider);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('logger.summary'),
        title: const Text('Session complete'),
        content: Text(
          '${done.durationMin} min · ${done.completedSetCount} sets · '
          // Whole numbers: a session's total volume runs to hundreds, where
          // formatWeight's decimal place would be noise rather than precision.
          '${convertFromKg(done.totalVolumeKg ?? 0, unit).toStringAsFixed(0)} '
          '${unit.api} lifted',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this session?'),
        content: const Text('Sets you have already logged will not be kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(activeSessionProvider.notifier).abandon();
      if (mounted) Navigator.of(context).pop();
    } on StateError {
      // Same _current contract as _finish: already closed elsewhere by the
      // time this reached the controller. Same resolution as the 409 path.
      if (!mounted) return;
      _handleAlreadyClosed(messenger);
    } catch (error) {
      // The abandon did not land, so the session is untouched and still in
      // progress -- nothing was thrown away and it stays resumable. Say so
      // rather than letting a destructive tap look like it did nothing.
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final plan = ref.watch(activePlanProvider).value;
    final live = ref.watch(activeSessionProvider).value;
    final unit = ref.watch(weightUnitProvider);
    if (live != null) _lastSeenSession = live;
    final session = live ?? _lastSeenSession;

    if (plan == null || session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final exercises = plan.exercisesForDay(session.planDayNo);
    if (exercises.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final index = _index.clamp(0, exercises.length - 1);
    final exercise = exercises[index];
    final isLast = index == exercises.length - 1;

    final targetSets =
        exercises.fold<int>(0, (total, exercise) => total + exercise.targetSets);
    final doneSets = session.completedSetCount;

    final last = ref
        .watch(lastPerformanceProvider(
          lastPerformanceKey(exercises.map((e) => e.exerciseId)),
        ))
        .value;

    // Back steps through the workout before it leaves it. PopScope
    // rather than an AppBar leading override, because the Android system
    // back gesture arrives the same way -- two routes back that disagreed
    // about what "back" means would be worse than either alone. At the
    // first exercise it pops for real, leaving the session in progress and
    // resumable, exactly as it did before paging.
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() => _index = index - 1);
      },
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
          // The mockup's 38px rounded-square icon button, not Material's bare
          // arrow. Tooltipped 'Back' so the platform affordance -- and
          // tester.pageBack -- still finds it, and maybePop routes it through
          // the PopScope above, which is what steps an exercise back.
          leadingWidth: 58,
          leading: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Tooltip(
              message: 'Back',
              child: InkWell(
                key: const Key('logger.back'),
                onTap: () => Navigator.maybePop(context),
                borderRadius: BorderRadius.circular(FsRadius.sm),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(FsRadius.sm),
                    border: Border.all(color: t.line),
                  ),
                  child: Icon(Icons.chevron_left, size: 19, color: t.text),
                ),
              ),
            ),
          ),
          titleSpacing: 10,
          title: Text(
            'Logging',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.74,
              color: t.text,
            ),
          ),
          actions: [
            // The rest countdown is a tag up here rather than a card over the
            // content, so ticking a set does not shove the set table down.
            if (_resting) ...[
              RestTimer(
                // A fresh key restarts the countdown on each new set.
                key: ValueKey('rest-$doneSets'),
                duration: _restDuration,
                onDone: () => setState(() => _resting = false),
                onSkip: () => setState(() => _resting = false),
              ),
              const SizedBox(width: 6),
            ],
            // Finish lives here as well as on the footer button, so stopping a
            // workout early does not mean paging to the end of it first.
            PopupMenuButton<String>(
              key: const Key('logger.menu'),
              onSelected: (value) => value == 'finish' ? _finish() : _discard(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  key: Key('logger.finish'),
                  value: 'finish',
                  child: Text('Finish session'),
                ),
                PopupMenuItem(
                  key: Key('logger.discard'),
                  value: 'discard',
                  child: Text('Discard session'),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          key: const Key('logger.position'),
                          onTap: () => _jumpTo(exercises, session, index),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Exercise ${index + 1} / ${exercises.length}'
                                  ' · ${plan.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: t.text3),
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 16,
                                color: t.text3,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_elapsedMinutes(session.startedAt)} min elapsed',
                        style: TextStyle(
                          fontFamily: fsMonoFamily,
                          fontSize: 11,
                          color: t.text3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // The mockup carries no set count in the meta row -- the bar
                  // is the whole story there. Kept as a semantic label, since
                  // a bar is the one thing a screen reader cannot read.
                  Semantics(
                    key: const Key('logger.progress'),
                    label: '$doneSets of $targetSets sets',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: targetSets == 0 ? 0 : doneSets / targetSets,
                        minHeight: 8,
                        backgroundColor: t.surface2,
                        valueColor: AlwaysStoppedAnimation<Color>(t.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: ExerciseLogPanel(
                  exercise: exercise,
                  session: session,
                  last: last?[exercise.exerciseId],
                  unit: unit,
                  onUnitChanged: _setUnit,
                  baseUrl: ref.watch(exerciseRepositoryProvider).baseUrl,
                  onCompleteSet: (setNumber, weightKg, reps) async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ref.read(activeSessionProvider.notifier).logSet(
                            exerciseId: exercise.exerciseId,
                            setNumber: setNumber,
                            weightKg: weightKg,
                            reps: reps,
                          );
                    } on ApiException catch (error) {
                      // Every other failure still rethrows, so the row keeps
                      // its own retry -- that one CAN succeed.
                      if (!_handledSetWriteClosure(error, messenger)) rethrow;
                      return;
                    }
                    // Only on success: a rest timer after a failed write would
                    // be counting down from a set that was never recorded.
                    if (mounted) setState(() => _resting = true);
                  },
                  onUndoSet: (setNumber) async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ref
                          .read(activeSessionProvider.notifier)
                          .unlogSet(
                            exerciseId: exercise.exerciseId,
                            setNumber: setNumber,
                          );
                    } on ApiException catch (error) {
                      if (!_handledSetWriteClosure(error, messenger)) rethrow;
                    }
                  },
                  onOpenDemo: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => InSessionExerciseScreen(
                        exercise: exercise,
                        position: index + 1,
                        total: exercises.length,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: FsButton(
                  key: const Key('logger.primary'),
                  label: isLast ? 'Finish session' : 'Continue',
                  icon: Icon(isLast ? Icons.check : Icons.arrow_forward),
                  onPressed: isLast
                      ? (_finishing ? null : _finish)
                      : () => setState(() => _index = index + 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
