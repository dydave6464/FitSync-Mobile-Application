import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../plans/presentation/providers.dart';
import '../../recovery/presentation/providers.dart'
    show recoveryOverviewProvider;
import '../../recovery/presentation/widgets/checkin_sheet.dart'
    show showCheckinSheet;
import '../../sessions/domain/active_session.dart';
import '../../sessions/presentation/providers.dart'
    show
        activeSessionProvider,
        completedDaysProvider,
        homeSummaryProvider,
        trainingAnalyticsProvider;
import '../../sessions/presentation/session_logger_screen.dart';
import '../../profile/presentation/providers.dart';
import '../../plans/domain/workout_plan.dart';
import 'widgets/active_workout_card.dart';
import 'widgets/greeting.dart';
import 'widgets/plan_card.dart';
import 'widgets/profile_nudge.dart';
import 'widgets/progress_snapshot_card.dart';
import 'widgets/readiness_card.dart';

/// The signed-in landing screen.
///
/// Only sections with a live API are here. The design's routine checklist,
/// quick stats and ad each need a server slice that does not exist yet, and a
/// placeholder showing invented figures cannot be told apart from a real one
/// by anyone looking at the screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    this.onGoToTrain,
    this.onGoToProfile,
    this.onGoToProgress,
    this.onGoToRecovery,
  });

  final VoidCallback? onGoToTrain;
  final VoidCallback? onGoToProfile;
  final VoidCallback? onGoToProgress;
  final VoidCallback? onGoToRecovery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final plan = ref.watch(activePlanProvider);
    // Only to place the plan in its rotation -- see WorkoutPlan.todayDayNo.
    // An unread count is an empty week, which is day 1: the card names one
    // day either way, never the whole rotation.
    final completedDays =
        ref.watch(completedDaysProvider).value ?? const <String>{};
    // What is happening NOW outranks what was planned. A session left open is
    // otherwise invisible here, and Home is where a user looks first.
    final session = ref.watch(activeSessionProvider).value;

    return Scaffold(
      backgroundColor: context.fs.bg,
      body: SafeArea(
        child: profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Retry(
            message: describeError(error),
            onRetry: () => ref.invalidate(profileProvider),
          ),
          data: (p) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Greeting(profile: p, now: DateTime.now()),
              const SizedBox(height: 20),
              // The nudge renders nothing when the profile is complete, so
              // its spacing is conditional too — otherwise a complete profile
              // leaves a gap where the card would have been.
              if (profileNeedsFinishing(p)) ...[
                ProfileNudge(profile: p, onTap: () => onGoToProfile?.call()),
                const SizedBox(height: 14),
              ],
              _Readiness(onTap: () => onGoToRecovery?.call()),
              // The plan is not replaced while a workout runs, only
              // covered: finishing or discarding uncovers it with no reload,
              // because activePlanProvider was never touched.
              if (session != null)
                _ActiveWorkout(session: session, plan: plan.value)
              else
                plan.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, _) => _Retry(
                    message: describeError(error),
                    onRetry: () => ref.invalidate(activePlanProvider),
                  ),
                  data: (workoutPlan) => workoutPlan == null
                      ? const _NoPlan()
                      : PlanCard(
                          plan: workoutPlan,
                          weightKg: p.weightKg,
                          dayNo: workoutPlan.todayDayNo(completedDays.length),
                          onStart: () => onGoToTrain?.call(),
                        ),
                ),
              const SizedBox(height: 14),
              _Progress(onTap: () => onGoToProgress?.call()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Owns the discard flow, so HomeScreen itself stays a ConsumerWidget.
class _ActiveWorkout extends ConsumerStatefulWidget {
  const _ActiveWorkout({required this.session, required this.plan});

  final ActiveSession session;
  final WorkoutPlan? plan;

  @override
  ConsumerState<_ActiveWorkout> createState() => _ActiveWorkoutState();
}

class _ActiveWorkoutState extends ConsumerState<_ActiveWorkout> {
  bool _discarding = false;

  /// Asks first: this throws away every set already logged, and the tap sits
  /// on the first screen of the app where it is easy to hit by accident.
  Future<void> _discard() async {
    if (_discarding) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard this workout?'),
        content: const Text(
          'Everything logged in it is thrown away. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
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
    setState(() => _discarding = true);
    try {
      await ref.read(activeSessionProvider.notifier).abandon();
    } on StateError {
      // Already closed elsewhere -- the logger, or another device. The card
      // is about to disappear on its own, so there is nothing to report.
    } catch (error) {
      // The abandon did not land, so the workout is untouched and still
      // resumable. Say so rather than letting a destructive tap look like it
      // did nothing.
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
      }
    } finally {
      if (mounted) setState(() => _discarding = false);
    }
  }

  @override
  Widget build(BuildContext context) => ActiveWorkoutCard(
    session: widget.session,
    plan: widget.plan,
    discarding: _discarding,
    onContinue: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SessionLoggerScreen()),
    ),
    onDiscard: _discard,
  );
}

/// Plans are created only by `POST /profile/complete-onboarding`. There is no
/// on-demand generate endpoint, so this state deliberately offers no action —
/// a button that calls nothing is worse than a sentence that explains why.
class _NoPlan extends StatelessWidget {
  const _NoPlan();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      // Distinct from PlanScreen's own 'noPlan' key: both tabs build eagerly
      // once visited, so with no active plan both no-plan states exist in
      // the tree at once, and a shared key would leave any finder that uses
      // it ambiguous between the two screens.
      key: const Key('home.noPlan'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FsEyebrow("Today's plan"),
          const SizedBox(height: 8),
          Text(
            'You have no active plan yet.',
            style: TextStyle(fontSize: 12.5, color: t.text2),
          ),
        ],
      ),
    );
  }
}

/// Matches PlanScreen's failure treatment, so the two screens fail the same
/// way rather than each inventing their own.
class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry, this.buttonKey});

  final String message;
  final VoidCallback onRetry;

  /// Lets a caller keep a stable finder for the button itself, since keying
  /// this whole widget would make a tap land wherever its centre happens to
  /// fall -- the message above it, say -- rather than on the button.
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
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

/// Hidden entirely when the estimate cannot be read: the Recovery tab is
/// where that error belongs, and Home's first screen should not open on it.
class _Readiness extends ConsumerWidget {
  const _Readiness({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(recoveryOverviewProvider)
        .when(
          // The card's own height, so Home does not jump when it lands.
          loading: () => const SizedBox(height: 150),
          error: (_, _) => const SizedBox.shrink(),
          data: (overview) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ReadinessCard(
              estimate: overview.latestEstimate,
              todayCheckin: overview.todayCheckin,
              onCheckIn: () =>
                  showCheckinSheet(context, existing: overview.todayCheckin),
              onTap: onTap,
            ),
          ),
        );
  }
}

/// Needs both the 30-day summary and the month analytics; either failing is
/// one error line, since half a card would only raise the question of where
/// the other half went.
class _Progress extends ConsumerWidget {
  const _Progress({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(homeSummaryProvider);
    final analytics = ref.watch(trainingAnalyticsProvider('month'));

    if (summary.hasError || analytics.hasError) {
      return _Retry(
        message: "Couldn't load progress",
        buttonKey: const Key('home.progress.retry'),
        onRetry: () {
          ref.invalidate(homeSummaryProvider);
          ref.invalidate(trainingAnalyticsProvider('month'));
        },
      );
    }
    final s = summary.value;
    final a = analytics.value;
    // Each placeholder here matches its card's real, with-data height,
    // measured by pumping the card on its own and reading tester.getSize --
    // not guessed. A loading or empty state is free to differ from that by
    // design (it says less, so it can be shorter), only a placeholder
    // standing in for data about to replace it must match.
    if (s == null || a == null) return const SizedBox(height: 163);
    return ProgressSnapshotCard(summary: s, analytics: a, onTap: onTap);
  }
}
