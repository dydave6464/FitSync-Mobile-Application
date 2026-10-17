import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/equipment_icon.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../exercises/presentation/providers.dart';
import '../../plans/presentation/providers.dart' show activePlanProvider;
import '../domain/active_session.dart';
import 'open_workout_summary.dart';
import 'providers.dart';
import 'session_logger_screen.dart';
import 'workout_draft.dart';

/// What the user chose to do about a workout that was already open.
enum _Blocked { open, replace }

/// What a review row's ⋮ menu offers.
enum _RowAction { moveUp, moveDown, remove }

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

  /// The Undo message for the last removal, while it is showing.
  ///
  /// It lives on the app's root messenger, so on its own it would follow the
  /// user to the library or the logger, where its Undo can do nothing --
  /// and with a screen reader on it never times out, so it would sit there
  /// holding back every message after it. [dispose] takes it down instead.
  ({
    ScaffoldMessengerState messenger,
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller,
  })?
  _undo;

  @override
  void dispose() {
    // Not hidden here and now: with a screen reader on, Flutter hides a
    // SnackBar instantly rather than animating it out, which rebuilds the
    // messenger on the spot -- and while this screen is being torn down the
    // widget tree is locked, so that throws and the dead Undo stays up. Right
    // after this frame the tree is free again.
    final undo = _undo;
    if (undo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (undo.messenger.mounted) undo.messenger.hideCurrentSnackBar();
      });
    }
    super.dispose();
  }

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

    final open = ref.read(activeSessionProvider).value;
    if (open != null) {
      final choice = await _askAboutOpenWorkout(open);
      if (choice == null || !mounted) return;

      if (choice == _Blocked.open) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            // Where it was left, the way Home's card and the Plan tab open
            // it, rather than back at its first exercise.
            builder: (_) => const SessionLoggerScreen(resume: true),
          ),
        );
        return;
      }
      // Discarding is a write that can fail on its own. Only once it lands is
      // the way actually clear, so the start below waits for it.
      if (!await _discardOpenWorkout()) return;
    }

    await _createSession();
  }

  /// Names the workout in the way and offers the three honest answers, with
  /// the likely one highlighted.
  ///
  /// Which one is likely depends on what the old workout holds. With nothing
  /// logged it is most often one left open by backing out of the logger:
  /// closing it loses nothing, and the user came here to start this one. With
  /// sets logged it is real work, so going back to it is the safe choice, and
  /// throwing it away is shown in red and kept apart from it.
  Future<_Blocked?> _askAboutOpenWorkout(ActiveSession open) {
    final plan = ref.read(activePlanProvider).value;
    final hasWork = open.completedSetCount > 0;
    final ago = openedAgo(open.startedAt, DateTime.now());

    return showDialog<_Blocked>(
      context: context,
      builder: (dialogContext) {
        final t = dialogContext.fs;
        void answer(_Blocked? choice) =>
            Navigator.of(dialogContext).pop(choice);

        // The highlighted choice first, then the other, then Cancel. Each
        // wraps rather than ending in an ellipsis: at the largest text sizes
        // "Discard it & start new" would otherwise read "Discard it &…".
        final choices = [
          if (hasWork) ...[
            FsButton(
              key: const Key('blocked.open'),
              label: 'Resume it',
              wrapLabel: true,
              onPressed: () => answer(_Blocked.open),
            ),
            FsButton(
              key: const Key('blocked.replace'),
              label: 'Discard it & start new',
              kind: FsButtonKind.ghost,
              danger: true,
              wrapLabel: true,
              onPressed: () => answer(_Blocked.replace),
            ),
          ] else ...[
            FsButton(
              key: const Key('blocked.replace'),
              label: 'Start new workout',
              wrapLabel: true,
              onPressed: () => answer(_Blocked.replace),
            ),
            FsButton(
              key: const Key('blocked.open'),
              label: 'Open the other one',
              kind: FsButtonKind.secondary,
              wrapLabel: true,
              onPressed: () => answer(_Blocked.open),
            ),
          ],
          FsButton(
            key: const Key('blocked.cancel'),
            label: 'Cancel',
            kind: FsButtonKind.ghost,
            wrapLabel: true,
            onPressed: () => answer(null),
          ),
        ];

        return AlertDialog(
          // At large text on a small phone the dialog is taller than the
          // screen. The title and message scroll; the choices, in `actions`,
          // stay in view below them.
          scrollable: true,
          // Half the default 40 a side: on a 320 dp phone that is the
          // difference between two-word lines and one-word ones in the
          // buttons. The cap keeps a tablet from stretching the pills 700 dp
          // wide.
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 400),
          title: Text(
            hasWork
                ? 'You have a workout in progress'
                : 'Start this workout instead?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                openWorkoutTitle(open, plan),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  openWorkoutFacts(open, plan),
                  if (ago != null) 'opened $ago',
                ].join(' · '),
                style: TextStyle(fontSize: 12.5, color: t.text2),
              ),
              const SizedBox(height: 12),
              Text(
                hasWork
                    ? 'Only one workout can be open at a time. Discarding '
                          'throws away the sets logged in it.'
                    // Sets, not "nothing": a hand-picked workout's list of
                    // exercises does go with it.
                    : 'Nothing is logged in it yet, so no sets are lost.',
              ),
            ],
          ),
          actions: [
            // Capped at half the screen, scrolling past that: at iOS's
            // largest text in landscape the wrapped choices alone are taller
            // than the dialog, and uncapped they would squeeze the question
            // above them down to nothing.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogContext).height / 2,
              ),
              child: SingleChildScrollView(
                // Not the route's primary scroller: the question's scroll
                // view already is, and a keyboard Page Down with two attached
                // cannot tell which to move.
                primary: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, choice) in choices.indexed) ...[
                      if (i > 0) const SizedBox(height: 8),
                      choice,
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

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

  /// Takes [exercise] out of the workout and offers to put it back.
  ///
  /// Removal used to be final: one tap on a small ✕ and the pick was gone,
  /// with the only way back being to find it again in the library -- where
  /// re-adding appends it to the end rather than where it was.
  void _remove(ExerciseSummary exercise, int index) {
    final draft = ref.read(workoutDraftProvider.notifier);
    draft.remove(exercise.exerciseId);

    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${exercise.name}'),
        // A SnackBar with an action stays up until dismissed by default,
        // which here would sit over the Start button indefinitely. A screen
        // reader is the exception: reaching Undo by swiping takes longer than
        // the four seconds a timed one gets, so for them it waits.
        persist: MediaQuery.accessibleNavigationOf(context),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Once this screen is gone the workout either started or was left
            // for the library; restoring a pick into either would be a surprise.
            if (!mounted) return;
            final current = ref.read(workoutDraftProvider);
            if (current.holds(exercise.exerciseId)) return;
            // Clamped, not trusted: other rows may have been removed since,
            // and the same slot is then as close as the list allows.
            draft.replaceWith(
              [...current]..insert(index.clamp(0, current.length), exercise),
            );
          },
        ),
      ),
    );
    _undo = (messenger: messenger, controller: controller);
    controller.closed.then((_) {
      // Only forget it if it is still the latest; a newer removal's message
      // has already taken its place.
      if (identical(_undo?.controller, controller)) _undo = null;
    });
  }

  void _onRowAction(_RowAction action, ExerciseSummary exercise, int index) {
    final draft = ref.read(workoutDraftProvider.notifier);
    switch (action) {
      case _RowAction.moveUp:
        draft.reorder(index, index - 1);
      case _RowAction.moveDown:
        draft.reorder(index, index + 1);
      case _RowAction.remove:
        _remove(exercise, index);
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
          // One scrolling list, header and footer included, rather than a
          // fixed header above a list: at large text on a small phone the
          // summary and hint alone can outgrow the screen, and a fixed block
          // has nowhere to put the overflow.
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              header: Column(
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
                      'Drag, or use ⋮, to set the order you will train them in.',
                      key: const Key('review.hint'),
                      style: TextStyle(
                        fontSize: 12,
                        // text2, not text3: this is the only place the screen
                        // says the order can be changed at all.
                        color: t.text2,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              footer: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
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
              ),
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
                  isLast: index == draft.length - 1,
                  baseUrl: baseUrl,
                  onAction: (action) => _onRowAction(action, exercise, index),
                );
              },
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
    required this.isLast,
    required this.baseUrl,
    required this.onAction,
  });

  final ExerciseSummary exercise;

  /// Where this exercise sits in the workout, counting from 1.
  final int position;

  /// Where it sits in the list, counting from 0 -- what the drag listener
  /// needs, and deliberately not derived from [position] at the use site.
  final int index;

  /// Whether this is the bottom row, which has nowhere further down to go.
  final bool isLast;

  final String baseUrl;
  final ValueChanged<_RowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return ListTile(
      // The handle's touch area is 48 wide but its icon still 20, so the
      // start padding gives back what the wider box takes: the icon sits
      // where it always did, and only the reach around it grew.
      contentPadding: const EdgeInsetsDirectional.only(start: 2, end: 8),
      leading: SizedBox(
        width: 94,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // An explicit handle rather than long-press-anywhere: the row also
            // carries a menu button, and a long press that starts a drag
            // from the whole row makes mis-grabs easy on a list people are
            // about to commit to.
            ReorderableDragStartListener(
              key: Key('review.drag.${exercise.exerciseId}'),
              index: index,
              // Its own node, so the row is still announced by its name
              // alone; the list's Move up/down actions sit on the row.
              child: Semantics(
                container: true,
                label: 'Reorder ${exercise.name}',
                // Painted, if invisibly, so the whole 48 dp box catches the
                // touch: the listener defers to its child, and an empty
                // SizedBox would leave only the 20 dp glyph to land on.
                child: ColoredBox(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Icon(
                        Icons.drag_indicator,
                        size: 20,
                        color: t.text3,
                      ),
                    ),
                  ),
                ),
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
        style: TextStyle(fontSize: 12, color: t.text2),
      ),
      // One ⋮ rather than a ✕ beside new arrow buttons: three icon buttons
      // would leave a 320 dp screen at large text almost no room for the
      // name, and dragging stays the quick way to move. Remove joins the
      // menu because its Undo makes the extra tap the only cost.
      trailing: PopupMenuButton<_RowAction>(
        key: Key('review.more.${exercise.exerciseId}'),
        icon: const Icon(Icons.more_vert),
        tooltip: 'More options for ${exercise.name}',
        onSelected: onAction,
        itemBuilder: (context) => [
          PopupMenuItem(
            key: Key('review.moveUp.${exercise.exerciseId}'),
            value: _RowAction.moveUp,
            enabled: index > 0,
            child: const Text('Move up'),
          ),
          PopupMenuItem(
            key: Key('review.moveDown.${exercise.exerciseId}'),
            value: _RowAction.moveDown,
            enabled: !isLast,
            child: const Text('Move down'),
          ),
          PopupMenuItem(
            key: Key('review.remove.${exercise.exerciseId}'),
            value: _RowAction.remove,
            child: const Text('Remove'),
          ),
        ],
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
