import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/manila_day.dart';
import '../../exercises/presentation/providers.dart'
    show apiClientProvider, apiRetryPolicy;
import '../data/activity_repository.dart';
import '../data/step_permission.dart';
import '../data/step_source.dart';
import '../domain/activity.dart';
import '../domain/step_readings.dart';

/// No-op defaults; `main.dart` overrides both with the platform's own.
final stepSourceProvider = Provider<StepSource>((ref) => const NoStepSource());
final stepPermissionProvider = Provider<StepPermission>(
  (ref) => const NoStepPermission(),
);

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(apiClientProvider)),
);

/// Injectable for tests, like the screens' `now` parameters.
final activityClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Not autoDispose -- Home watches it for the life of the app -- so it is on
/// sign-out's list of per-user caches.
final stepAccessProvider =
    AsyncNotifierProvider<StepAccessController, StepAccess>(
      StepAccessController.new,
    );

class StepAccessController extends AsyncNotifier<StepAccess> {
  @override
  Future<StepAccess> build() => ref.watch(stepPermissionProvider).status();

  Future<StepAccess> request() async {
    final access = await ref.read(stepPermissionProvider).request();
    state = AsyncData(access);
    return access;
  }

  Future<void> openSettings() => ref.read(stepPermissionProvider).openSettings();
}

/// Today's count (from the phone, so it works offline) and the week (from
/// the server, with its estimates).
class ActivityState {
  const ActivityState({
    required this.today,
    required this.week,
    required this.offline,
  });

  final DaySteps today;

  /// Null only when the server has never been reached this session.
  final ActivityWeek? week;

  /// The last save did not reach the server; kcal/km are the last saved.
  final bool offline;
}

/// The most steps the server takes for a day; mirrors `MAX_STEPS` in
/// server/src/routes/activity.js. A count above it is saved as this.
const maxSavedSteps = 100000;

/// Not autoDispose -- see [stepAccessProvider].
final activityProvider =
    AsyncNotifierProvider<ActivityController, ActivityState>(
      ActivityController.new,
      retry: apiRetryPolicy,
    );

class ActivityController extends AsyncNotifier<ActivityState> {
  @override
  Future<ActivityState> build() => _load(null);

  /// Saves today (and, on iPhone, any earlier day the server has fewer
  /// steps for), then reads the week back. Offline, today still counts and
  /// the week stays as it was.
  Future<ActivityState> _load(ActivityWeek? previous) async {
    final now = ref.read(activityClockProvider)();
    final source = ref.read(stepSourceProvider);
    final repo = ref.read(activityRepositoryProvider);
    final today = await source.today(now);
    try {
      final known = previous ?? await repo.week();
      // A 0-step day is never saved: its row would count toward "usual"
      // (days with a row) and drag it down for a day with no data.
      if (today.steps > 0) await _save(repo, manilaDayOf(now), today.steps);
      final stored = {for (final d in known.days) d.date: d.steps ?? -1};
      for (final entry in (await source.earlierDays(now)).entries) {
        final steps = math.min(entry.value, maxSavedSteps);
        if (steps > 0 && steps > (stored[entry.key] ?? -1)) {
          await _save(repo, entry.key, steps);
        }
      }
      return ActivityState(today: today, week: await repo.week(), offline: false);
    } on ApiException catch (error) {
      if (error.code != 'NETWORK_ERROR') rethrow;
      return ActivityState(today: today, week: previous, offline: true);
    }
  }

  /// Saves one day, capped at [maxSavedSteps]. A day the server rejects
  /// (e.g. DATE_OUT_OF_RANGE when the phone's clock is off) is skipped so
  /// the rest still loads; NETWORK_ERROR goes on to [_load]'s offline branch.
  Future<void> _save(ActivityRepository repo, String date, int steps) async {
    try {
      await repo.saveDay(date, math.min(steps, maxSavedSteps));
    } on ApiException catch (error) {
      if (error.code == 'NETWORK_ERROR') rethrow;
    }
  }

  /// On resume, while Activity is open, and on leaving it. Never throws: a
  /// failed sync keeps what the screen already shows.
  Future<void> sync() async {
    final previous = state.value;
    try {
      state = AsyncData(await _load(previous?.week));
    } catch (error, stack) {
      if (previous == null) state = AsyncError(error, stack);
    }
  }
}

/// Today's running total while the Activity screen listens.
final liveStepsProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(stepSourceProvider).live(ref.read(activityClockProvider)()),
);
