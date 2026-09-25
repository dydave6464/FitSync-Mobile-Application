import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminders.dart';
import 'reminder_scheduler.dart';
import 'tap_relay.dart';

const _channelId = 'reminders';
const _channelName = 'Reminders';

/// Schedules reminders through the phone's local notifications.
///
/// Every plugin call is wrapped so a platform exception is logged and
/// swallowed: a reminder failure must never break the app.
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  /// Assigned once, in [create], after the launch payload (if any) is known.
  late final TapRelay _relay;

  static Future<LocalReminderScheduler> create() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));

    final plugin = FlutterLocalNotificationsPlugin();
    final scheduler = LocalReminderScheduler._(plugin);

    const androidSettings = AndroidInitializationSettings('ic_notification');
    // Permission is requested explicitly through requestPermission(), not
    // here, so the user isn't prompted before they've opted in.
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    try {
      await plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            scheduler._relay.add(payload);
          }
        },
      );
    } catch (error) {
      debugPrint('Reminder plugin failed to initialise: $error');
    }

    String? launchPayload;
    try {
      final launchDetails = await plugin.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final payload = launchDetails.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          launchPayload = payload;
        }
      }
    } catch (error) {
      debugPrint('Reminder launch details lookup failed: $error');
    }

    scheduler._relay = TapRelay(launchPayload: launchPayload);
    return scheduler;
  }

  @override
  Future<bool> permissionGranted() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final enabled = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled();
        return enabled ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final status = await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.checkPermissions();
        return status?.isEnabled ?? false;
      }
      return false;
    } catch (error) {
      debugPrint('Reminder permissionGranted failed: $error');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: false, sound: true);
      }
    } catch (error) {
      debugPrint('Reminder requestPermission failed: $error');
    }
    return permissionGranted();
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('Reminder cancelAll failed: $error');
    }
  }

  @override
  Future<void> scheduleAll(List<PlannedReminder> reminders) async {
    for (final reminder in reminders) {
      try {
        await _plugin.zonedSchedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          payload: reminder.payload,
          scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              importance: Importance.defaultImportance,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (error) {
        debugPrint('Reminder scheduling failed for id ${reminder.id}: $error');
      }
    }
  }

  @override
  Stream<String> get taps => _relay.stream;
}
