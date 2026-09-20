import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/equipment_icon.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../exercises/presentation/providers.dart';
import 'providers.dart';
import 'session_logger_screen.dart';
import 'workout_draft.dart';

/// What the user chose to do about a workout that was already open.
enum _Blocked { open, replace }

/// The last look at a manual workout before it becomes a session.
///
/// The library used to start the workout directly from its footer, which made
/// the picks reviewable only as ticks scattered down a 1,200-row catalogue --
/// there was no screen that showed the workout as a workout. Worse, the order
/// was already load-bearing (`order_no`, and the order the logger walks) and
/// was set by nothing more deliberate than which row happened to be tapped
/// first, with no way to see it, let alone change it.
///
/// So this screen owns starting now, and the library's footer only leads here.
class WorkoutReviewScreen extends ConsumerStatefulWidget {
  const WorkoutReviewScreen({super.key});

  @override
  ConsumerState<WorkoutReviewScreen> createState() =>
      _WorkoutReviewScreenState();
}

class _WorkoutReviewScreenState extends ConsumerState<WorkoutReviewScreen> {
  /// Guards the start button against a second tap while the first is in
  /// flight -- POST /sessions is idempotent, but a second logger pushed on
  /// top of the first is not something the server can undo.
  bool _starting = false;

  /// Starts the reviewed workout and opens the logger on it.
  ///
  /// A session already in progress blocks this. The server is idempotent
  /// here: it returns the running session and ignores the list entirely, so
  /// pushing the logger anyway would drop everything the user just picked and
  /// open a workout they did not choose.
  ///
  /// The block used to be a snack bar naming a workout the user often had no
  /// memory of starting -- one left open by backing out of the logger, which
  /// nothing else surfaced. It offered "Open" and nothing else, so the only
  /// way to actually start the workout just built was to go and close the old
  /// one from inside the logger's overflow menu. It asks now, and can clear
  /// the way itself.
  Future<void> _start() async {
    if (_starting) return;
    if (ref.read(workoutDraftProvider).isEmpty) return;

    if (ref.read(activeSessionProvider).value != null) {
      final choice = await _askAboutOpenWorkout();
      if (choice == null || !mounted) return;

      if (choice == _Blocked.open) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SessionLoggerScreen()),
        );
        return;
      }
      // Discarding is a write that can fail on its own. Only once it lands is
      // the way actually clear, so the start below waits for it.
      if (!await _discardOpenWorkout()) return;
    }

    await _createSession();
  }

  /// Names the workout in the way and offers the three honest answers.
  Future<_Blocked?> _askAboutOpenWorkout() => showDialog<_Blocked>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('You already have a workout open'),
      content: const Text(
        'Only one workout can be open at a time. Discarding throws away '
        'everything logged in the old one.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(_Blocked.open),
          child: const Text('Open it'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(_Blocked.replace),
          child: const Text('Discard it & start'),
        ),
      ],
    ),
  );

  /// True when the old workout is gone and this one may start.
  Future<bool> _discardOpenWorkout() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _starting = true);
    try {
      await ref.read(activeSessionProvider.notifier).abandon();
      return true;
    } on StateError {
      // Already closed elsewhere between the tap and here. The way is clear,
      // which is all this was for.
      return true;
    } catch (error) {
      // Nothing was thrown away and the old workout is still open, so this
      // one cannot start. Say so rather than failing silently.
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      return false;
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _createSession() async {
    final draft = ref.read(workoutDraftProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _starting = true);
    try {
      await ref
          .read(activeSessionProvider.notifier)
          .start(exerciseIds: draft.exerciseIds);
      // Cleared only once the session exists. A failed start leaves the picks
      // alone, so the user retries rather than choosing them all again.
      ref.read(workoutDraftProvider.notifier).clear();
      if (!mounted) return;
      // Replaced, not pushed: this screen reviews a workout that has not
      // started, so backing out of the logger onto it would offer to start a
      // workout that already is. The library underneath is the honest
      // destination -- it is where more exercises come from.
      await navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SessionLoggerScreen()),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final draft = ref.watch(workoutDraftProvider);
    final baseUrl = ref.watch(exerciseRepositoryProvider).baseUrl;
    // Watched, not read on demand: reading an unresolved AsyncNotifier hands
    // back null while its first fetch is still in flight, so a session that
    // IS running would look like none at the moment the user taps Start.
    ref.watch(activeSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Review workout')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FsButton(
          key: const Key('review.start'),
          label: 'Start workout',
          busy: _starting,
          // A workout of no exercises is not a workout.
          onPressed: draft.isEmpty ? null : _start,
        ),
      ),
      body: draft.isEmpty
          ? _EmptyReview(onAddMore: () => Navigator.of(context).pop())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    _summarise(draft),
                    key: const Key('review.summary'),
                    style: TextStyle(
                      fontSize: 13,
                      color: t.text2,
                      height: 1.35,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Drag to set the order you will train them in.',
                    style: TextStyle(
                      fontSize: 12,
                      color: t.text3,
                      height: 1.35,
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: draft.length,
                    onReorderItem: (oldIndex, newIndex) => ref
                        .read(workoutDraftProvider.notifier)
                        .reorder(oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      final exercise = draft[index];
                      return _ReviewRow(
                        // Keyed by exercise, not by index: a list keyed by
                        // position cannot tell a reorder from a rebuild, and
                        // ReorderableListView requires a stable child key.
                        key: ValueKey(exercise.exerciseId),
                        exercise: exercise,
                        position: index + 1,
                        index: index,
                        baseUrl: baseUrl,
                        onRemove: () => ref
                            .read(workoutDraftProvider.notifier)
                            .remove(exercise.exerciseId),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: TextButton.icon(
                    key: const Key('review.addMore'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add more exercises'),
                    // Pops rather than pushes: the library is already the
                    // route underneath, and pushing a second copy would leave
                    // two libraries and two ways back.
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
    );
  }
}

/// "3 exercises · quadriceps, pectorals".
///
/// The muscle groups are de-duplicated in the order they appear, so the line
/// reads as what the workout covers rather than as one word per row.
String _summarise(List<ExerciseSummary> draft) {
  final count = draft.length == 1 ? '1 exercise' : '${draft.length} exercises';
  final groups = <String>[];
  for (final exercise in draft) {
    if (!groups.contains(exercise.muscleGroup)) {
      groups.add(exercise.muscleGroup);
    }
  }
  return '$count · ${groups.join(', ')}';
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview({required this.onAddMore});

  final VoidCallback onAddMore;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rtl, size: 40, color: t.text3),
            const SizedBox(height: 12),
            Text(
              'Nothing in this workout yet.',
              style: TextStyle(fontSize: 14, color: t.text2),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              key: const Key('review.addMore'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add more exercises'),
              onPressed: onAddMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    super.key,
    required this.exercise,
    required this.position,
    required this.index,
    required this.baseUrl,
    required this.onRemove,
  });

  final ExerciseSummary exercise;

  /// Where this exercise sits in the workout, counting from 1.
  final int position;

  /// Where it sits in the list, counting from 0 -- what the drag listener
  /// needs, and deliberately not derived from [position] at the use site.
  final int index;

  final String baseUrl;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return ListTile(
      leading: SizedBox(
        width: 76,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // An explicit handle rather than long-press-anywhere: the row also
            // carries a remove button, and a long press that starts a drag
            // from the whole row makes mis-grabs easy on a list people are
            // about to commit to.
            ReorderableDragStartListener(
              key: Key('review.drag.${exercise.exerciseId}'),
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_indicator, size: 20, color: t.text3),
              ),
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: 44,
              height: 44,
              child: exercise.thumbnailUrl == null
                  ? _ThumbPlaceholder(equipment: exercise.equipment)
                  : Image.network(
                      '$baseUrl${exercise.thumbnailUrl}',
                      fit: BoxFit.cover,
                      // One unreachable thumbnail must not take the row down.
                      errorBuilder: (_, _, _) =>
                          _ThumbPlaceholder(equipment: exercise.equipment),
                    ),
            ),
          ],
        ),
      ),
      title: Text(
        exercise.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        [
          '$position',
          exercise.muscleGroup,
          if (exercise.equipment != null) exercise.equipment!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: t.text3),
      ),
      trailing: IconButton(
        key: Key('review.remove.${exercise.exerciseId}'),
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Remove ${exercise.name}',
        onPressed: onRemove,
      ),
    );
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder({this.equipment});

  final String? equipment;

  @override
  Widget build(BuildContext context) => Container(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Icon(equipmentIcon(equipment), size: 18),
  );
}
