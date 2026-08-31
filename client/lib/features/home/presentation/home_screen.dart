import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../plans/presentation/providers.dart';
import '../../profile/presentation/providers.dart';
import 'widgets/greeting.dart';
import 'widgets/plan_card.dart';
import 'widgets/profile_nudge.dart';

/// The signed-in landing screen.
///
/// Only sections with a live API are here. The design's readiness ring,
/// progress chart, routine checklist, quick stats and ad each need a server
/// slice that does not exist yet, and a placeholder showing invented figures
/// cannot be told apart from a real one by anyone looking at the screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.onGoToTrain, this.onGoToProfile});

  final VoidCallback? onGoToTrain;
  final VoidCallback? onGoToProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final plan = ref.watch(activePlanProvider);

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
                        onStart: () => onGoToTrain?.call(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      key: const Key('noPlan'),
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
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FsButton(
              label: 'Retry',
              small: true,
              kind: FsButtonKind.secondary,
              onPressed: onRetry,
            ),
          ],
        ),
      );
}
