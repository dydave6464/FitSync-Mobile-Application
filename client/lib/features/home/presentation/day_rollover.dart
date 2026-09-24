import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/manila_day.dart';
import '../../recovery/presentation/providers.dart'
    show recoveryOverviewProvider;
import '../../routine/presentation/providers.dart' show routineTodayProvider;
import '../../sessions/presentation/providers.dart'
    show
        completedDaysProvider,
        homeSummaryProvider,
        pendingOutcomeProvider,
        trainingAnalyticsProvider,
        trainingSummaryProvider;

/// Refetches everything dated "today" when the app comes back to the
/// foreground on a new Manila day.
///
/// Without it, an app left open overnight kept showing yesterday's routine,
/// check-in and week strip until the first tick was refused as stale
/// (`DAY_CHANGED`). Only on resume, not on a midnight timer: a screen someone
/// is looking at across midnight is rare, and the refused tick still covers
/// it.
///
/// Each provider is invalidated, not refreshed: one nothing is watching just
/// refetches the next time it is read.
class DayRollover extends ConsumerStatefulWidget {
  const DayRollover({super.key, required this.child, this.now = DateTime.now});

  final Widget child;

  /// The clock, so tests can move the day on.
  final DateTime Function() now;

  @override
  ConsumerState<DayRollover> createState() => _DayRolloverState();
}

class _DayRolloverState extends ConsumerState<DayRollover> {
  /// The day on screen. Set in initState, not by a lazy initialiser: a lazy
  /// one would first run inside [_onResume], after the clock had moved on,
  /// and every resume would look like the same day.
  late String _day;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _day = manilaDayOf(widget.now());
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  void _onResume() {
    final today = manilaDayOf(widget.now());
    if (today == _day) return;
    _day = today;
    ref
      ..invalidate(routineTodayProvider)
      ..invalidate(recoveryOverviewProvider)
      ..invalidate(homeSummaryProvider)
      ..invalidate(trainingSummaryProvider)
      ..invalidate(trainingAnalyticsProvider) // every period
      ..invalidate(completedDaysProvider)
      // Yesterday's session becomes askable about at midnight.
      ..invalidate(pendingOutcomeProvider);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
