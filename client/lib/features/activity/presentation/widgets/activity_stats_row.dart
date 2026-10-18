import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
  const ActivityStatsRow({super.key, this.onGoToProfile, this.bottomGap = 0});

  final VoidCallback? onGoToProfile;

  /// Space below the row, kept by the row itself so that when it shows
  /// nothing (step access cannot be read) it leaves no gap either.
  final double bottomGap;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(stepAccessProvider);
    if (access.hasError) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: _content(context, ref, access),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<StepAccess> access,
  ) {
    return access.when(
      loading: () => const _Tiles.zero(onTap: null),
      error: (_, _) => const SizedBox.shrink(),
      data: (access) => switch (access) {
        StepAccess.notAsked => _Tiles.zero(
          hint: 'Tap to start counting your steps',
          onTap: () =>
              _open(context, ActivationScreen(onGoToProfile: onGoToProfile)),
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
          onOpen: () =>
              _open(context, ActivityScreen(onGoToProfile: onGoToProfile)),
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
    return ref
        .watch(activityProvider)
        .when(
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
            final noKcal =
                week == null || week.missingHeight || week.missingWeight;
            return _Tiles(
              steps: formatSteps(state.today.steps),
              kcal: noKcal ? '—' : '${today!.caloriesBurned ?? 0}',
              km: noKm ? '—' : (today!.distanceKm ?? 0).toStringAsFixed(1),
              todaySteps: state.today.steps,
              usual: week?.usual,
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
    required this.todaySteps,
    required this.usual,
    required this.onTap,
  }) : hint = null;

  /// Before counting is on (or while it loads): zeros, not dashes -- nothing
  /// is missing yet, there is simply nothing counted.
  const _Tiles.zero({required this.onTap, this.hint})
    : steps = '0',
      kcal = '0',
      km = '0.0',
      todaySteps = 0,
      usual = null;

  final String steps;
  final String kcal;
  final String km;
  final int todaySteps;

  /// The user's usual day, or null until there is one to measure against.
  final int? usual;
  final VoidCallback? onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One height for all three, though only steps carries the bar.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatTile(
                key: const Key('home.activity.steps'),
                icon: FontAwesomeIcons.personWalking,
                color: t.blue,
                value: steps,
                label: 'steps',
                onTap: onTap,
                // The bar's room is kept with or without a usual, so its
                // arriving never moves the cards below the row.
                footer: switch (usual) {
                  final usual? when usual > 0 => _UsualBar(
                    today: todaySteps,
                    usual: usual,
                    color: t.blue,
                  ),
                  _ => const SizedBox(height: _UsualBar.height),
                },
              ),
              const SizedBox(width: 10),
              _StatTile(
                key: const Key('home.activity.kcal'),
                icon: FontAwesomeIcons.fire,
                color: t.amber,
                value: kcal,
                label: 'kcal',
                onTap: onTap,
              ),
              const SizedBox(width: 10),
              _StatTile(
                key: const Key('home.activity.km'),
                icon: FontAwesomeIcons.locationDot,
                color: t.violet,
                value: km,
                label: 'km',
                onTap: onTap,
              ),
            ],
          ),
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

/// One of the three: its kind in a small badge of its own colour, so the
/// tiles tell apart at a glance, and the word under the number says it too.
class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
    this.footer,
  });

  final FaIconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;
  final Widget? footer;

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
            _Badge(icon, color: color),
            const SizedBox(height: 8),
            // Shrunk to fit rather than wrapped: a third of a small phone at
            // large text broke "6,420" into "6," "42" "0".
            FsOneLine(value, style: fsNum(t, size: 17)),
            FsOneLine(label, style: TextStyle(fontSize: 12, color: t.text3)),
            if (footer case final footer?) ...[
              const SizedBox(height: 8),
              footer,
            ],
          ],
        ),
      ),
    );
  }
}

/// A kind's icon in a small badge tinted with its colour.
class _Badge extends StatelessWidget {
  const _Badge(this.icon, {required this.color, this.size = 30});

  final FaIconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(size / 3),
    ),
    child: FaIcon(icon, size: size * 0.47, color: color),
  );
}

/// Today's steps as a share of the usual day: a thin bar, full once the
/// usual is reached, and the share in words for a screen reader.
class _UsualBar extends StatelessWidget {
  const _UsualBar({
    required this.today,
    required this.usual,
    required this.color,
  });

  final int today;
  final int usual;
  final Color color;

  static const height = 4.0;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final share = today / usual;
    return Semantics(
      label:
          '${(share * 100).round()}% of your usual ${formatSteps(usual)} steps',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FsRadius.pill),
        child: Container(
          height: height,
          color: t.surface2,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            key: const Key('home.activity.usual'),
            widthFactor: share.clamp(0.0, 1.0),
            heightFactor: 1,
            child: ColoredBox(color: color),
          ),
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
          _Badge(FontAwesomeIcons.personWalking, color: t.blue, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
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
