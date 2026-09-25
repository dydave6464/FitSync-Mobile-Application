import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../plans/presentation/providers.dart' show activePlanProvider;
import '../../profile/presentation/providers.dart' show profileProvider;
import '../../recovery/presentation/providers.dart'
    show recoveryOverviewProvider;
import '../../routine/domain/routine.dart' show Habit;
import '../../routine/presentation/providers.dart'
    show routineRepositoryProvider, routineTodayProvider;
import '../data/reminder_scheduler.dart' show reminderSchedulerProvider;
import '../domain/plan_reminders.dart' show planReminders;
import '../domain/reminders.dart' show TodayDone;
import 'providers.dart' show reminderSettingsProvider;

/// Keeps the phone's reminders in step with everything they depend on, and
/// routes a tapped reminder.
///
/// Rather than every write path remembering to reschedule, this listens to
/// the providers those writes already refresh: the routine (habit writes and
/// ticks, a finished workout's item), the recovery overview (a check-in),
/// the profile (master switch, training days), the active plan, and the
/// reminder settings. DayRollover refreshes the routine on a new day, so a
/// resume on a new day reschedules too.
class ReminderSync extends ConsumerStatefulWidget {
  const ReminderSync({
    super.key,
    required this.child,
    required this.onOpenRoutine,
    required this.onOpenRecovery,
    this.now = DateTime.now,
  });

  final Widget child;
  final VoidCallback onOpenRoutine;
  final VoidCallback onOpenRecovery;

  /// The clock, so tests can fix "now" rather than race the real one.
  final DateTime Function() now;

  @override
  ConsumerState<ReminderSync> createState() => _ReminderSyncState();
}

class _ReminderSyncState extends ConsumerState<ReminderSync> {
  /// Whether a run is currently in flight -- scheduled, awaiting the habits
  /// fetch, or awaiting the scheduler.
  bool _running = false;

  /// Set when something relevant changes again while a run is already in
  /// flight, so that run's snapshot (taken before the change) is not the
  /// last word: one more run follows once it finishes.
  bool _dirty = false;

  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    // Each provider has its own AsyncValue<T> type, so these stay separate
    // calls rather than a loop over a shared-type list.
    ref.listenManual(
      reminderSettingsProvider,
      (_, _) => _queue(),
      fireImmediately: true,
    );
    ref.listenManual(
      profileProvider,
      (_, _) => _queue(),
      fireImmediately: true,
    );
    ref.listenManual(
      routineTodayProvider,
      (_, _) => _queue(),
      fireImmediately: true,
    );
    ref.listenManual(
      recoveryOverviewProvider,
      (_, _) => _queue(),
      fireImmediately: true,
    );
    ref.listenManual(
      activePlanProvider,
      (_, _) => _queue(),
      fireImmediately: true,
    );
    _taps = ref.read(reminderSchedulerProvider).taps.listen((payload) {
      switch (payload) {
        case 'routine':
          widget.onOpenRoutine();
        case 'recovery':
          widget.onOpenRecovery();
      }
    });
  }

  void _queue() {
    // Guards more than the common case of a listener still firing after
    // dispose (listenManual subscriptions close themselves by then): _run's
    // own finally calls back into this to replay a coalesced change, and
    // that call can land after dispose too -- the run it is finishing may
    // have been the one suspended on the habits fetch when this widget was
    // torn down. Either way, scheduling another _run here would read a ref
    // that is no longer safe to use.
    if (!mounted) return;
    if (_running) {
      _dirty = true;
      return;
    }
    _running = true;
    scheduleMicrotask(_run);
  }

  Future<void> _run() async {
    try {
      final settings = ref.read(reminderSettingsProvider).value;
      final profile = ref.read(profileProvider).value;
      if (settings == null || profile == null) return;

      final List<Habit> habits;
      try {
        habits = await ref.read(routineRepositoryProvider).all();
      } catch (_) {
        return;
      }
      // The fetch above was the run's only await before this point, and
      // widget disposal (e.g. sign-out tearing the shell down mid-fetch)
      // does not cancel it -- ref becomes unusable the moment that happens,
      // so every read past here must be guarded.
      if (!mounted) return;

      final day = ref.read(routineTodayProvider).value;
      final recovery = ref.read(recoveryOverviewProvider).value;
      final plan = ref.read(activePlanProvider).value;

      final done = TodayDone(
        habitIds: {
          for (final h in day?.habits ?? const [])
            if (h.done) h.habitId,
        },
        workout: day?.workout?.done ?? false,
        checkin: recovery?.todayCheckin != null,
      );

      final planned = planReminders(
        settings: settings,
        masterOn: profile.notificationsEnabled,
        habits: habits,
        trainingDays: profile.trainingDays,
        planName: plan?.name,
        done: done,
        now: widget.now(),
      );

      if (!mounted) return;
      final scheduler = ref.read(reminderSchedulerProvider);
      try {
        await scheduler.cancelAll();
        await scheduler.scheduleAll(planned);
      } catch (e) {
        // Whatever is on the phone now is stale, but there is nothing better
        // to fall back to -- the next trigger (another write, or this same
        // run re-queued by _dirty) tries again.
        debugPrint('ReminderSync: scheduling failed: $e');
      }
    } finally {
      _running = false;
      if (_dirty) {
        _dirty = false;
        _queue();
      }
    }
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
