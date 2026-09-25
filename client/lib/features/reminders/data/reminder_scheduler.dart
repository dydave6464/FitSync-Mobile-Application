import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reminders.dart';

/// The seam between reminder planning and the phone's notification system.
abstract interface class ReminderScheduler {
  /// Whether this phone currently lets the app show notifications.
  Future<bool> permissionGranted();

  /// Shows the system prompt where the OS allows one; answers the result.
  Future<bool> requestPermission();

  Future<void> cancelAll();

  /// Schedules each reminder at its instant, Manila time zone.
  Future<void> scheduleAll(List<PlannedReminder> reminders);

  /// Payloads of tapped reminders ('routine' / 'recovery'), including the
  /// one that launched the app, delivered once to the first listener.
  Stream<String> get taps;
}

/// Does nothing; permission never granted. The provider's default, so tests
/// and any screen outside a real app run never touch the plugin.
class NoopReminderScheduler implements ReminderScheduler {
  @override
  Future<bool> permissionGranted() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> scheduleAll(List<PlannedReminder> reminders) async {}

  @override
  Stream<String> get taps => const Stream.empty();
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(
  (ref) => NoopReminderScheduler(),
);
