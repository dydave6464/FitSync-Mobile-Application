import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/manila_day.dart' show manilaDayOf;
import '../../auth/presentation/auth_controller.dart'
    show AuthStatus, authControllerProvider;
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

  /// Chains every cancelAll/scheduleAll pair this widget issues onto the
  /// last one, so a cancel and the schedule that belongs to it are never
  /// interleaved with another pair -- `_running` already keeps two `_run`
  /// bodies from executing at once, but this holds even if that changes.
  Future<void> _schedulerChain = Future<void>.value();

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

  /// Whether [value] is usable input for a reschedule: present and not
  /// erroring. `isLoading` is deliberately not part of this -- an
  /// [AsyncValue] keeps its previous data while a refresh is in flight, so
  /// checking only `hasValue`/`hasError` would read that stale value as
  /// current. Most of this run's inputs settle together often enough that it
  /// does not matter in practice; [routineTodayProvider] is the one case
  /// this file has actually seen it matter for (see [_run]), so its own read
  /// checks `isLoading` too rather than relying on this helper alone.
  bool _ready(AsyncValue<Object?> value) => value.hasValue && !value.hasError;

  Future<void> _run() async {
    try {
      // A failure to read any input -- offline, a server error, or (for
      // routineTodayProvider) a fetch still in flight -- leaves whatever is
      // already on the phone in place rather than rebuilding the schedule
      // from an incomplete picture. "No active plan" is not a failure:
      // activePlanProvider holding AsyncData(null) is real data, and
      // planReminders already treats a null plan name as "no workout
      // reminders".
      final settingsAsync = ref.read(reminderSettingsProvider);
      final profileAsync = ref.read(profileProvider);
      final routineAsync = ref.read(routineTodayProvider);
      final recoveryAsync = ref.read(recoveryOverviewProvider);
      final planAsync = ref.read(activePlanProvider);
      if (!_ready(settingsAsync) || !_ready(profileAsync)) return;
      if (!_ready(routineAsync) || routineAsync.isLoading) return;
      if (!_ready(recoveryAsync) || !_ready(planAsync)) return;

      final settings = settingsAsync.value!;
      final profile = profileAsync.value!;
      final day = routineAsync.value!;
      final recovery = recoveryAsync.value;
      final plan = planAsync.value;

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

      // A day from any other date -- e.g. yesterday's, still sitting in
      // routineTodayProvider while today's fetch has not landed -- says
      // nothing about what is done today; reading its ticks as today's would
      // wrongly suppress a reminder that has not fired yet.
      final isToday = day.date == manilaDayOf(widget.now());
      final done = TodayDone(
        habitIds: {
          if (isToday)
            for (final h in day.habits)
              if (h.done) h.habitId,
        },
        workout: isToday && (day.workout?.done ?? false),
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
        await _enqueueScheduler(scheduler.cancelAll);
        // Sign-out can land while the two calls above/below are in flight
        // (it cancels directly, off this same chain) -- re-checked right
        // before reviving anything on the phone, so a reschedule already
        // underway can never outlive it.
        final signedIn =
            ref.read(authControllerProvider).value?.status == AuthStatus.ready;
        if (!mounted || !signedIn) return;
        await _enqueueScheduler(() => scheduler.scheduleAll(planned));
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

  /// Chains [op] onto [_schedulerChain] and returns its own result, so a
  /// cancelAll/scheduleAll pair from one run can never overlap on the
  /// scheduler with another pair from this widget. One step's failure is
  /// swallowed into the chain itself, not into [op]'s caller (which still
  /// sees the original error via the returned future), so it cannot wedge
  /// every later step.
  Future<void> _enqueueScheduler(Future<void> Function() op) {
    final started = _schedulerChain.then((_) => op());
    _schedulerChain = started.then((_) {}, onError: (_) {});
    return started;
  }

  @override
  void dispose() {
    _taps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
