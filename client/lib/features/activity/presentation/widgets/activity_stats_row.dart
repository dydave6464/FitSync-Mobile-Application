import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../data/step_permission.dart';
import '../../domain/activity.dart';
import '../activation_screen.dart';
import '../activity_screen.dart';
import '../providers.dart';

/// Home's steps · kcal · km. Before step counting is on, the same three
/// tiles show zeros and a tap on any of them is the way in: the activation
/// screen, or -- once refused -- the OS prompt again and then Settings.
class ActivityStatsRow extends ConsumerWidget {
  const ActivityStatsRow({super.key, this.onGoToProfile});

  final VoidCallback? onGoToProfile;

  void _open(BuildContext context, Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(stepAccessProvider).when(
      loading: () => const _Tiles.zero(onTap: null),
      error: (_, _) => const SizedBox.shrink(),
      data: (access) => switch (access) {
        StepAccess.notAsked => _Tiles.zero(
          hint: 'Tap to start counting your steps',
          onTap: () => _open(context, ActivationScreen(onGoToProfile: onGoToProfile)),
        ),
        StepAccess.refused => _Tiles.zero(
          hint: 'Step counting is off — tap to allow',
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
      loading: () => const _Tiles.zero(onTap: null),
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
        return _Tiles(
          steps: formatSteps(state.today.steps),
          kcal: noKcal ? '—' : '${today!.caloriesBurned ?? 0}',
          km: noKm ? '—' : (today!.distanceKm ?? 0).toStringAsFixed(1),
          onTap: onOpen,
        );
      },
    );
  }
}

/// The prototype's quick-stats row, with an optional hint under it.
class _Tiles extends StatelessWidget {
  const _Tiles({
    required this.steps,
    required this.kcal,
    required this.km,
    required this.onTap,
  }) : hint = null;

  /// Before counting is on (or while it loads): zeros, not dashes -- nothing
  /// is missing yet, there is simply nothing counted.
  const _Tiles.zero({required this.onTap, this.hint})
    : steps = '0',
      kcal = '0',
      km = '0.0';

  final String steps;
  final String kcal;
  final String km;
  final VoidCallback? onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _StatTile(
              key: const Key('home.activity.steps'),
              icon: Icons.directions_walk,
              value: steps,
              label: 'steps',
              onTap: onTap,
            ),
            const SizedBox(width: 10),
            _StatTile(
              key: const Key('home.activity.kcal'),
              icon: Icons.local_fire_department_outlined,
              value: kcal,
              label: 'kcal',
              onTap: onTap,
            ),
            const SizedBox(width: 10),
            _StatTile(
              key: const Key('home.activity.km'),
              icon: Icons.place_outlined,
              value: km,
              label: 'km',
              onTap: onTap,
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: t.text3),
          ),
        ],
      ],
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
  final VoidCallback? onTap;

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
