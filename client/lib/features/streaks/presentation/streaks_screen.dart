import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/manila_day.dart';
import '../../../core/theme.dart';
import '../../../core/units.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../profile/presentation/providers.dart' show weightUnitProvider;
import '../domain/streaks.dart';
import 'add_goal_sheet.dart';
import 'providers.dart';

/// The streak -- days in a row with a habit ticked or a workout finished --
/// and the user's lift goals. The two load separately, so one failing never
/// hides the other.
class StreaksScreen extends ConsumerWidget {
  const StreaksScreen({super.key, this.now = DateTime.now});

  /// The clock, so tests can fix "today". Only used to dim the week's later
  /// days and to decide whether a reached date needs its year.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final today = manilaDayOf(now());
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Streaks & goals')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _StreakSection(today: today),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(child: FsEyebrow('Goals')),
              IconButton(
                key: const Key('streaks.goals.add'),
                tooltip: 'Add a goal',
                icon: const Icon(Icons.add),
                onPressed: () => showAddGoalSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _GoalsSection(currentYear: int.parse(today.substring(0, 4))),
        ],
      ),
    );
  }
}

class _StreakSection extends ConsumerWidget {
  const _StreakSection({required this.today});

  final String today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(streakProvider)
        .when(
          loading: () => const SizedBox(
            height: 190,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _SectionError(
            message: "Couldn't load your streak",
            buttonKey: const Key('streaks.streak.retry'),
            onRetry: () => ref.invalidate(streakProvider),
          ),
          data: (streak) => _StreakCard(streak: streak, today: today),
        );
  }
}

const _weekLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak, required this.today});

  final Streak streak;
  final String today;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return FsCard(
      accent: true,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            const SizedBox(height: 6),
            Text(
              '${streak.current}',
              key: const Key('streaks.current'),
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                color: t.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              streak.best > 0
                  ? 'Day streak · best ${streak.best}'
                  : 'Day streak',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.text2,
              ),
            ),
            if (streak.current == 0) ...[
              const SizedBox(height: 8),
              Text(
                'Tick a habit or finish a workout to start one.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: t.text2),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < streak.week.length && i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.5),
                    child: _WeekDot(
                      day: streak.week[i],
                      label: _weekLetters[i],
                      today: today,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _WeekDot extends StatelessWidget {
  const _WeekDot({required this.day, required this.label, required this.today});

  final StreakDay day;
  final String label;
  final String today;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final isToday = day.date == today;
    final isFuture = day.date.compareTo(today) > 0;
    return Opacity(
      opacity: isFuture ? 0.4 : 1,
      child: Column(
        children: [
          Container(
            key: Key('streaks.day.${day.date}'),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: day.active ? t.accent : t.surface2,
              border: Border.all(
                color: day.active
                    ? Colors.transparent
                    : (isToday ? t.accent : t.line),
                width: isToday && !day.active ? 2 : 1,
              ),
            ),
            child: day.active
                ? Icon(Icons.check, size: 13, color: t.onAccent)
                : null,
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(fontSize: 9, color: t.text3)),
        ],
      ),
    );
  }
}

class _GoalsSection extends ConsumerWidget {
  const _GoalsSection({required this.currentYear});

  final int currentYear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(weightUnitProvider);
    return ref
        .watch(goalsProvider)
        .when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _SectionError(
            message: "Couldn't load your goals",
            buttonKey: const Key('streaks.goals.retry'),
            onRetry: () => ref.invalidate(goalsProvider),
          ),
          data: (goals) => goals.isEmpty
              ? const _NoGoals()
              : Column(
                  children: [
                    for (final goal in goals) ...[
                      _GoalCard(
                        goal: goal,
                        unit: unit,
                        currentYear: currentYear,
                        onTap: () => _showGoalSheet(context, goal, unit),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.unit,
    required this.currentYear,
    required this.onTap,
  });

  final LiftGoal goal;
  final WeightUnit unit;
  final int currentYear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final target = formatWeightWithUnit(goal.targetKg, unit);
    final best = goal.bestKg;
    return FsCard(
      key: Key('streaks.goal.${goal.goalId}'),
      small: true,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.exerciseName,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 6),
                if (goal.reached)
                  Text(
                    'Reached ${formatReachedOn(goal.reachedOn!, currentYear: currentYear)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: t.accent,
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: goal.progress,
                            minHeight: 6,
                            backgroundColor: t.line,
                            color: t.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        best == null
                            ? 'Not logged yet · 0 / $target'
                            : '${formatWeight(best, unit)} / $target',
                        style: TextStyle(fontSize: 10.5, color: t.text3),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (goal.reached) ...[
            const SizedBox(width: 12),
            Icon(Icons.check_circle, size: 20, color: t.accent),
          ],
        ],
      ),
    );
  }
}

Future<void> _showGoalSheet(
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
        _error = describeError(error);
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
            Text(_error!, style: TextStyle(fontSize: 13, color: t.red)),
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

class _NoGoals extends StatelessWidget {
  const _NoGoals();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text('No goals yet', style: TextStyle(fontSize: 14, color: t.text2)),
          const SizedBox(height: 12),
          FsButton(
            key: const Key('streaks.goals.empty.add'),
            label: 'Add a goal',
            onPressed: () => showAddGoalSheet(context),
          ),
        ],
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({
    required this.message,
    required this.buttonKey,
    required this.onRetry,
  });

  final String message;
  final Key buttonKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.fs.text2),
          ),
          const SizedBox(height: 8),
          FsButton(
            key: buttonKey,
            label: 'Retry',
            small: true,
            kind: FsButtonKind.secondary,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
