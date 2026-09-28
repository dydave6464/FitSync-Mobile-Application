import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../domain/activity.dart';
import 'providers.dart';

/// Today's steps against the user's own usual -- no goal -- with the
/// estimates and the week. Opened from Home's steps tiles.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({
    super.key,
    this.onGoToProfile,
    this.syncEvery = const Duration(minutes: 5),
  });

  final VoidCallback? onGoToProfile;
  final Duration syncEvery;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  // Captured in initState and kept: ref may not be used in dispose. The
  // container is read fresh at sync time rather than caching the notifier
  // itself, so a periodic tick or the leaving-sync never calls into a
  // reference the provider has since replaced.
  late final ProviderContainer _container;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _timer = Timer.periodic(widget.syncEvery, (_) => _sync());
  }

  void _sync() => unawaited(_container.read(activityProvider.notifier).sync());

  @override
  void dispose() {
    _timer?.cancel();
    _sync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final live = ref.watch(liveStepsProvider).value;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Activity')),
      body: ref.watch(activityProvider).when(
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
                  label: 'Try again',
                  onPressed: () => ref.invalidate(activityProvider),
                ),
              ],
            ),
          ),
        ),
        data: (state) => _Body(
          state: state,
          steps: live ?? state.today.steps,
          onGoToProfile: widget.onGoToProfile == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  widget.onGoToProfile!();
                },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.steps, this.onGoToProfile});

  final ActivityState state;
  final int steps;
  final VoidCallback? onGoToProfile;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final week = state.week;
    final noKm = week == null || week.missingHeight;
    final noKcal = week == null || week.missingHeight || week.missingWeight;
    final today = week?.today;
    final notes = [
      if (state.today.sinceTurnedOn) 'Counting since you turned it on',
      if (state.today.includesEarlierDays)
        "Steps from days FitSync wasn't opened are added to the next day",
      if (state.offline) "Updates when you're online",
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        FsCard(
          child: Column(
            children: [
              Text(
                formatSteps(steps),
                key: const Key('activity.steps'),
                style: fsNum(t, size: 44),
              ),
              Text('steps today', style: TextStyle(fontSize: 13, color: t.text2)),
              const SizedBox(height: 18),
              _UsualBar(today: steps, usual: week?.usual),
              const SizedBox(height: 10),
              Text(
                usualLine(today: steps, usual: week?.usual),
                key: const Key('activity.usualLine'),
                style: TextStyle(fontSize: 13, color: t.text),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _Figure(
                    key: const Key('activity.kcal'),
                    value: noKcal ? '—' : '${today!.caloriesBurned ?? 0}',
                    label: 'kcal',
                  ),
                  _Figure(
                    key: const Key('activity.km'),
                    value: noKm ? '—' : (today!.distanceKm ?? 0).toStringAsFixed(2),
                    label: 'km',
                  ),
                  _Figure(
                    key: const Key('activity.minutes'),
                    value: today?.activeMinutes == null ? '—' : '${today!.activeMinutes}',
                    label: 'active min',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Estimates', style: TextStyle(fontSize: 11, color: t.text3)),
              if (week != null && (week.missingHeight || week.missingWeight))
                TextButton(
                  key: const Key('activity.addProfile'),
                  onPressed: onGoToProfile,
                  child: const Text('Add your height and weight in Profile'),
                ),
            ],
          ),
        ),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              note,
              key: note == "Updates when you're online" ? const Key('activity.offline') : null,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
          ),
        if (week != null) ...[
          const SizedBox(height: 14),
          FsCard(
            key: const Key('activity.week'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'This week',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.text),
                    ),
                    const Spacer(),
                    if (week.average != null)
                      Text(
                        'avg ${(week.average! / 1000).toStringAsFixed(1)}k/day',
                        style: TextStyle(fontSize: 11.5, color: t.text3),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _WeekBars(days: week.days, todaySteps: steps),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Today's steps filling toward a scale of 1.25 × the larger of today and
/// the usual, with a marker at the usual.
class _UsualBar extends StatelessWidget {
  const _UsualBar({required this.today, required this.usual});

  final int today;
  final int? usual;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final scale = math.max(1, math.max(today, usual ?? 0)) * 1.25;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return SizedBox(
          height: 28,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0, right: 0, top: 4,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(FsRadius.pill),
                  ),
                ),
              ),
              Positioned(
                left: 0, top: 4,
                child: Container(
                  width: width * today / scale,
                  height: 10,
                  decoration: BoxDecoration(
                    color: t.blue,
                    borderRadius: BorderRadius.circular(FsRadius.pill),
                  ),
                ),
              ),
              // A ▲ just under the bar, pointing up at the usual. The icon's
              // triangle spans y 9-14 of its 24px box, so top 6 puts it right
              // below the bar (which ends at 14) and centring the box centres
              // the tip on the usual.
              if (usual != null)
                Positioned(
                  key: const Key('activity.usualMarker'),
                  left: width * usual! / scale - 12,
                  top: 6,
                  child: Icon(Icons.arrow_drop_up, size: 24, color: t.text),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: fsNum(t, size: 17)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: t.text3)),
        ],
      ),
    );
  }
}

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Seven bars, today's highlighted and showing the live count.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days, required this.todaySteps});

  final List<ActivityDay> days;
  final int todaySteps;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final values = [
      for (var i = 0; i < days.length; i++)
        i == days.length - 1 ? todaySteps : (days[i].steps ?? 0),
    ];
    final top = math.max(1, values.reduce(math.max));
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 72 * values[i] / top,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: i == days.length - 1 ? t.blue : t.surface2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _weekdayLetters[DateTime.parse(days[i].date).weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      color: i == days.length - 1 ? t.text : t.text3,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
