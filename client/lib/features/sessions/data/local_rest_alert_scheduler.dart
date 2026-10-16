import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/notification_ids.dart';
import '../../reminders/data/reminder_scheduler.dart';
import 'rest_alerts.dart';

/// The rest alert through the phone's local notifications.
///
/// Rides on the plugin LocalReminderScheduler.create() initialised in main:
/// FlutterLocalNotificationsPlugin() is one shared instance, and initialising
/// it a second time would replace the reminder tap handler. Permission is the
/// reminders' too -- an app has one notification permission -- so it is
/// asked through the same scheduler. Every call is guarded: an alert that
/// fails must never break a workout.
class LocalRestAlertScheduler implements RestAlertScheduler {
  LocalRestAlertScheduler(
    this._permissions, [
    FlutterLocalNotificationsPlugin? plugin,
  ]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final ReminderScheduler _permissions;
  final FlutterLocalNotificationsPlugin _plugin;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'rest',
      'Rest timer',
      channelDescription: 'Tells you when a rest between sets is over.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentSound: true),
  );

  @override
  Future<bool> permissionGranted() => _permissions.permissionGranted();

  @override
  Future<bool> requestPermission() => _permissions.requestPermission();

  @override
  Future<void> openSettings() async {
    try {
      await ph.openAppSettings();
    } catch (error) {
      debugPrint('Opening app settings failed: $error');
    }
  }

  @override
  Future<void> schedule({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    Future<void> using(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: restAlertNotificationId,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _details,
      androidScheduleMode: mode,
    );
    try {
      // Exact without asking: AndroidManifest declares USE_EXACT_ALARM. A
      // rest is 90 seconds, and an inexact alarm can land long after it.
      await using(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (error) {
      debugPrint('Exact rest alert refused, falling back: $error');
      try {
        await using(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (error) {
        debugPrint('Rest alert scheduling failed: $error');
      }
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _plugin.cancel(id: restAlertNotificationId);
    } catch (error) {
      debugPrint('Rest alert cancel failed: $error');
    }
  }
}
