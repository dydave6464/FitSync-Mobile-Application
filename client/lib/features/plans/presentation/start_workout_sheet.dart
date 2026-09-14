import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/domain/exercise.dart';
import '../../sessions/presentation/providers.dart' show lastWorkoutProvider;
import '../../sessions/presentation/workout_draft.dart';
import '../../sessions/presentation/workout_review_screen.dart';
import '../../sessions/presentation/workout_setup_screen.dart';
import 'generator_screen.dart';

/// The "+" chooser: how a workout starts.
///
/// Two rows, as the design draws them, and both live: the generator
/// replaces the plan, while "Log a workout" opens the setup screen the
/// workout is described on before its exercises are picked. It was inert
/// while the exercise library was a later slice; the library and the sessions
/// endpoint that accepts a chosen list both exist now.
Future<void> showStartWorkoutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // A modal sheet is capped at 9/16 of the screen unless it is told
    // otherwise, and this one's content does not shrink: sideways on a
    // phone that cap lands "Log a workout" past the bottom edge, where debug
    // draws a stripe and release quietly clips it. Full height covers every
    // orientation; the scroll view inside covers the accessibility text
    // scales that no height can fit.
    isScrollControlled: true,
    builder: (_) => const _StartWorkoutSheet(),
  );
}

class _StartWorkoutSheet extends ConsumerWidget {
  const _StartWorkoutSheet();

  /// Loads the workout into the draft and hands it to the review screen.
  ///
  /// Review rather than straight into the logger, which is where the
  /// mockup's row pointed: a repeat is rarely identical, and the review
  /// screen already owns starting -- including the guard for a workout that
  /// is already open. Routing around it would mean a second copy of that.
  void _repeat(BuildContext context, WidgetRef ref, List<ExerciseSummary> exercises) {
    ref.read(workoutDraftProvider.notifier).replaceWith(exercises);
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WorkoutReviewScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    // Only the shortcut depends on this. A failure or an untrained account
    // simply leaves the row out -- the two rows that start a workout from
    // scratch must not depend on history loading.
    final last = ref.watch(lastWorkoutProvider).value;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: t.line2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Expanded, not bare: at a 2x text scale the title and
                  // the close button together are wider than a phone, and
                  // a Row hands an unflexed child unbounded width to
                  // overflow in. Wrapping to a second line is the same
                  // remedy FsButton and the eyebrow rows already use.
                  Expanded(
                    child: Text('Start a workout',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: t.text)),
                  ),
                  IconButton(
                    key: const Key('start.close'),
                    icon: const Icon(Icons.close, size: 18),
                    color: t.text3,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Row(
                rowKey: const Key('start.generator'),
                icon: Icons.auto_awesome,
                title: 'AI Workout Generator',
                body: 'Auto-build a plan from your profile, goals & recovery.',
                tag: 'Recommended',
                accent: true,
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const GeneratorScreen()),
                  );
                },
              ),
              const SizedBox(height: 10),
              _Row(
                rowKey: const Key('start.manual'),
                icon: Icons.fitness_center,
                title: 'Log a workout',
                body: 'Pick your own exercises. Keep it as part of your plan '
                    'when you finish, or just log it.',
                tag: 'Free',
                accent: false,
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WorkoutSetupScreen(),
                    ),
                  );
                },
              ),
              if (last != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: Divider(color: t.line2, height: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or pick up where you left off',
                        style: TextStyle(fontSize: 11, color: t.text3),
                      ),
                    ),
                    Expanded(child: Divider(color: t.line2, height: 1)),
                  ],
                ),
                const SizedBox(height: 10),
                InkWell(
                  key: const Key('start.repeat'),
                  onTap: () => _repeat(context, ref, last.exercises),
                  borderRadius: BorderRadius.circular(FsRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.history, size: 18, color: t.text2),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Repeat last workout',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${last.title} · ${last.describeCount}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: t.text3),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 16, color: t.text3),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.body,
    required this.tag,
    required this.accent,
    required this.onTap,
  });

  final Key rowKey;
  final IconData icon;
  final String title;
  final String body;
  final String tag;
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final dimmed = onTap == null;

    return Material(
      color: accent ? t.accentDim : t.surface,
      borderRadius: BorderRadius.circular(FsRadius.card),
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(FsRadius.card),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FsRadius.card),
            border: Border.all(color: accent ? t.accentLine : t.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: dimmed ? t.text3 : t.accent),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: dimmed ? t.text3 : t.text,
                        )),
                    const SizedBox(height: 3),
                    Text(body,
                        style: TextStyle(fontSize: 12, color: t.text3, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FsTag(tag),
            ],
          ),
        ),
      ),
    );
  }
}
