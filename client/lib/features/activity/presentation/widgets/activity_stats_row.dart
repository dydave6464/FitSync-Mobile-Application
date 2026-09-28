import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../data/step_permission.dart';
import '../../domain/activity.dart';
import '../activation_screen.dart';
import '../activity_screen.dart';
import '../providers.dart';

/// Home's steps · kcal · km, or the one tile that turns counting on.
class ActivityStatsRow extends ConsumerWidget {
  const ActivityStatsRow({super.key, this.onGoToProfile});

  final VoidCallback? onGoToProfile;

  void _open(BuildContext context, Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(stepAccessProvider).when(
      loading: () => const SizedBox(height: 76),
      error: (_, _) => const SizedBox.shrink(),
      data: (access) => switch (access) {
        StepAccess.notAsked => _WideTile(
          key: const Key('home.activity.turnOn'),
          title: 'Count your steps',
          subtitle: 'Tap to start',
          onTap: () => _open(context, ActivationScreen(onGoToProfile: onGoToProfile)),
        ),
        StepAccess.refused => _WideTile(
          key: const Key('home.activity.off'),
          title: 'Step counting is off',
          subtitle: defaultTargetPlatform == TargetPlatform.iOS
              ? 'Allow Motion & Fitness in Settings'
              : 'Allow Physical activity in Settings',
          onTap: () async {
            // Ask again first: after a reinstall the OS may still be able to.
            final controller = ref.read(stepAccessProvider.notifier);
            if (await controller.request() != StepAccess.granted) {
              await controller.openSettings();
            }
          },
        ),
        StepAccess.granted => _Stats(
          onOpen: () => _open(context, ActivityScreen(onGoToProfile: onGoToProfile)),
        ),
      },
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(activityProvider).when(
      loading: () => const SizedBox(height: 76),
      error: (_, _) => _WideTile(
        key: const Key('home.activity.retry'),
        title: "Couldn't load your steps",
        subtitle: 'Tap to try again',
        onTap: () => ref.invalidate(activityProvider),
      ),
      data: (state) {
        final week = state.week;
        final today = week?.today;
        final noKm = week == null || week.missingHeight;
        final noKcal = week == null || week.missingHeight || week.missingWeight;
        return Row(
          children: [
            _StatTile(
              key: const Key('home.activity.steps'),
              icon: Icons.directions_walk,
              value: formatSteps(state.today.steps),
              label: 'steps',
              onTap: onOpen,
            ),
            const SizedBox(width: 10),
            _StatTile(
              key: const Key('home.activity.kcal'),
              icon: Icons.local_fire_department_outlined,
              value: noKcal ? '—' : '${today!.caloriesBurned ?? 0}',
              label: 'kcal',
              onTap: onOpen,
            ),
            const SizedBox(width: 10),
            _StatTile(
              key: const Key('home.activity.km'),
              icon: Icons.place_outlined,
              value: noKm ? '—' : (today!.distanceKm ?? 0).toStringAsFixed(1),
              label: 'km',
              onTap: onOpen,
            ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Expanded(
      child: FsCard(
        small: true,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: t.blue),
            const SizedBox(height: 6),
            Text(value, style: fsNum(t, size: 17)),
            Text(label, style: TextStyle(fontSize: 10, color: t.text3)),
          ],
        ),
      ),
    );
  }
}

class _WideTile extends StatelessWidget {
  const _WideTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return FsCard(
      onTap: onTap,
      child: Row(
        children: [
          const FsIconTile(icon: Icons.directions_walk),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: t.text2)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: t.text3),
        ],
      ),
    );
  }
}
