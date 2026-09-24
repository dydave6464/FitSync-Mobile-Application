import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../domain/routine.dart';
import 'providers.dart';
import 'widgets/habit_sheet.dart';

/// Every active habit, whatever day it repeats on: the place to find, edit or
/// delete one that is not on today's list. Nothing here is tickable -- a tick
/// belongs to a day, and this list is not about one.
class AllHabitsScreen extends ConsumerWidget {
  const AllHabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    // Each row already shows its habit's days, so the sheet's "Saved --
    // repeats ..." note would only repeat them.
    void open({Habit? existing}) =>
        showHabitSheet(context, existing: existing, announceRepeats: false);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('All habits'),
        actions: [
          IconButton(
            key: const Key('allHabits.add'),
            tooltip: 'Add a habit',
            icon: const Icon(Icons.add),
            onPressed: () => open(),
          ),
        ],
      ),
      body: ref
          .watch(allHabitsProvider)
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
                      key: const Key('allHabits.retry'),
                      label: 'Retry',
                      small: true,
                      kind: FsButtonKind.secondary,
                      onPressed: () => ref.invalidate(allHabitsProvider),
                    ),
                  ],
                ),
              ),
            ),
            data: (habits) => habits.isEmpty
                ? _Empty(onAdd: () => open())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      for (final habit in habits) ...[
                        _HabitRow(
                          habit: habit,
                          onTap: () => open(existing: habit),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  const _HabitRow({required this.habit, required this.onTap});

  final Habit habit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    // "Mon, Wed, Fri · 9:00 PM · 10 min", or just the days.
    final subtitle = [
      formatWeekdays(habit.weekdays),
      if (habit.subtitle.isNotEmpty) habit.subtitle,
    ].join(' · ');

    return FsCard(
      key: Key('allHabits.habit.${habit.habitId}'),
      small: true,
      onTap: onTap,
      child: Row(
        children: [
          const FsIconTile(icon: Icons.self_improvement),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10.5, color: t.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.chevron_right, size: 18, color: t.text3),
        ],
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
              'No habits yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: t.text2),
            ),
            const SizedBox(height: 14),
            FsButton(
              key: const Key('allHabits.empty.add'),
              label: 'Add a habit',
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}
