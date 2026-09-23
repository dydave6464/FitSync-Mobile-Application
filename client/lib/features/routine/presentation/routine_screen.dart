import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_charts.dart' show FsRing;
import '../../../core/widgets/fs_kit.dart' hide FsRing;
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../domain/routine.dart';
import 'providers.dart';
import 'widgets/habit_sheet.dart';

/// Today's checklist: repeating habits, and the workout item that ticks
/// itself when a session is finished. Today only -- other days belong to the
/// Schedule screen, which does not exist yet.
class RoutineScreen extends ConsumerWidget {
  const RoutineScreen({super.key, this.onOpenPlan});

  /// The workout item's destination. Home passes one that returns to the
  /// shell and opens Train at Plan.
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Daily Routine'),
        actions: [
          IconButton(
            key: const Key('routine.add'),
            tooltip: 'Add a habit',
            icon: const Icon(Icons.add),
            onPressed: () => showHabitSheet(context),
          ),
        ],
      ),
      body: ref
          .watch(routineTodayProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(describeError(error), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FsButton(
                      key: const Key('routine.retry'),
                      label: 'Retry',
                      small: true,
                      kind: FsButtonKind.secondary,
                      onPressed: () => ref.invalidate(routineTodayProvider),
                    ),
                  ],
                ),
              ),
            ),
            data: (day) => day.entries.isEmpty
                ? _Empty(onAdd: () => showHabitSheet(context))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      _Header(day: day),
                      const SizedBox(height: 14),
                      for (final entry in day.entries) ...[
                        _Row(entry: entry, onOpenPlan: onOpenPlan),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.day});

  final RoutineDay day;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final left = day.total - day.done;
    return FsCard(
      accent: true,
      child: Row(
        children: [
          FsRing(
            value: day.total == 0 ? 0 : day.done / day.total,
            color: t.accent,
            size: 62,
            stroke: 7,
            child: Text(
              '${day.done}/${day.total}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              left == 0 ? 'All done for today' : '$left left today',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.entry, required this.onOpenPlan});

  final RoutineEntry entry;
  final VoidCallback? onOpenPlan;

  Future<void> _toggle(BuildContext context, WidgetRef ref, Habit habit) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(routineTodayProvider.notifier)
          .setDone(habit.habitId, !habit.done);
    } catch (error) {
      // Either code means the checklist on screen is no longer today's --
      // the day turned over, or this habit was never on the day that is now
      // current -- and the controller has already reloaded it by the time
      // this snackbar shows.
      final dayChanged =
          error is ApiException &&
          (error.code == 'DAY_CHANGED' || error.code == 'HABIT_NOT_TODAY');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            dayChanged
                ? 'A new day has started — your routine has refreshed.'
                : "Couldn't save that. Try again.",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final entry = this.entry;
    // Typed explicitly: a bare `() => showHabitSheet(...)` is a
    // Future-returning closure, and the record's LUB with the workout branch's
    // VoidCallback? would not be assignable to InkWell.onTap.
    final (IconData, String, VoidCallback?, Widget) parts = switch (entry) {
      HabitEntry(:final habit) => (
        Icons.self_improvement,
        habit.subtitle,
        () {
          showHabitSheet(context, existing: habit);
        },
        _TickBox(
          key: Key('routine.tick.${habit.habitId}'),
          done: habit.done,
          onTap: () => _toggle(context, ref, habit),
        ),
      ),
      WorkoutEntry(:final workout) => (
        Icons.fitness_center,
        workout.done ? 'Finished today' : 'Ticks itself when you finish',
        onOpenPlan,
        // No onTap: the workout is done by training, not by ticking.
        _TickBox(
          key: const Key('routine.workout.tick'),
          done: workout.done,
          onTap: null,
        ),
      ),
    };
    final (icon, subtitle, onOpen, box) = parts;

    return Opacity(
      opacity: entry.done ? 0.55 : 1,
      child: FsCard(
        small: true,
        child: Row(
          children: [
            FsIconTile(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                key: switch (entry) {
                  HabitEntry(:final habit) => Key(
                    'routine.habit.${habit.habitId}',
                  ),
                  WorkoutEntry() => const Key('routine.workout'),
                },
                onTap: onOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                        decoration: entry.done
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 10.5, color: t.text3),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            box,
          ],
        ),
      ),
    );
  }
}

class _TickBox extends StatelessWidget {
  const _TickBox({super.key, required this.done, required this.onTap});

  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: done ? t.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: done ? t.accent : t.line2, width: 2),
        ),
        child: done ? Icon(Icons.check, size: 14, color: t.onAccent) : null,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nothing on your routine today',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: t.text2),
            ),
            const SizedBox(height: 14),
            FsButton(
              key: const Key('routine.empty.add'),
              label: 'Add a habit',
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}
