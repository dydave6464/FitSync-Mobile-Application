import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../plans/presentation/providers.dart';
import '../domain/active_session.dart';
import 'in_session_exercise_screen.dart';
import 'providers.dart';
import 'widgets/exercise_log_card.dart';
import 'widgets/rest_timer.dart';

/// The active workout: every exercise on one scroll, the current one expanded.
class SessionLoggerScreen extends ConsumerStatefulWidget {
  const SessionLoggerScreen({super.key});

  @override
  ConsumerState<SessionLoggerScreen> createState() => _SessionLoggerScreenState();
}

class _SessionLoggerScreenState extends ConsumerState<SessionLoggerScreen> {
  static const _restDuration = Duration(seconds: 90);

  int? _expandedExerciseId;
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

  int _elapsedMinutes(DateTime? startedAt) {
    if (startedAt == null) return 0;
    return DateTime.now().difference(startedAt).inMinutes;
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('logger.summary'),
        title: const Text('Session complete'),
        content: Text(
          '${done.durationMin} min · ${done.completedSetCount} sets · '
          '${(done.totalVolumeKg ?? 0).toStringAsFixed(0)} kg lifted',
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
    if (live != null) _lastSeenSession = live;
    final session = live ?? _lastSeenSession;

    if (plan == null || session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final exercises = plan.exercises;
    final expandedId = _expandedExerciseId ??
        (exercises.isEmpty ? null : exercises.first.exerciseId);

    final targetSets =
        exercises.fold<int>(0, (total, exercise) => total + exercise.targetSets);
    final doneSets = session.completedSetCount;

    final last = ref
        .watch(lastPerformanceProvider(
          lastPerformanceKey(exercises.map((e) => e.exerciseId)),
        ))
        .value;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: Text(plan.name),
        actions: [
          TextButton(
            key: const Key('logger.discard'),
            onPressed: _discard,
            child: const Text('Discard session'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Text(
                  '$doneSets of $targetSets sets',
                  key: const Key('logger.progress'),
                  style: TextStyle(fontSize: 11.5, color: t.text2),
                ),
                const Spacer(),
                Text(
                  '${_elapsedMinutes(session.startedAt)} min',
                  style: TextStyle(
                    fontFamily: fsMonoFamily, fontSize: 11.5, color: t.text3,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              itemCount: exercises.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final exercise = exercises[index];
                return ExerciseLogCard(
                  exercise: exercise,
                  expanded: exercise.exerciseId == expandedId,
                  session: session,
                  last: last?[exercise.exerciseId],
                  onExpand: () =>
                      setState(() => _expandedExerciseId = exercise.exerciseId),
                  onCompleteSet: (setNumber, weightKg, reps) async {
                    await ref.read(activeSessionProvider.notifier).logSet(
                          exerciseId: exercise.exerciseId,
                          setNumber: setNumber,
                          weightKg: weightKg,
                          reps: reps,
                        );
                    // Only on success: a rest timer after a failed write would
                    // be counting down from a set that was never recorded.
                    if (mounted) setState(() => _resting = true);
                  },
                  onUndoSet: (setNumber) => ref
                      .read(activeSessionProvider.notifier)
                      .unlogSet(exerciseId: exercise.exerciseId, setNumber: setNumber),
                  onOpenDemo: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => InSessionExerciseScreen(
                        exercise: exercise,
                        position: index + 1,
                        total: exercises.length,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                children: [
                  if (_resting) ...[
                    RestTimer(
                      // A fresh key restarts the countdown on each new set.
                      key: ValueKey('rest-$doneSets'),
                      duration: _restDuration,
                      onDone: () => setState(() => _resting = false),
                      onSkip: () => setState(() => _resting = false),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FsButton(
                    key: const Key('logger.finish'),
                    label: 'Finish session',
                    onPressed: _finishing ? null : _finish,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
