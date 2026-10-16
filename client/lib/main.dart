import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'features/activity/data/step_permission.dart';
import 'features/activity/data/step_source.dart';
import 'features/activity/presentation/providers.dart';
import 'features/reminders/data/local_reminder_scheduler.dart';
import 'features/reminders/data/reminder_scheduler.dart';
import 'features/sessions/data/local_rest_alert_scheduler.dart';
import 'features/sessions/data/rest_alerts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scheduler = await LocalReminderScheduler.create();
  final iPhone = defaultTargetPlatform == TargetPlatform.iOS;
  final android = defaultTargetPlatform == TargetPlatform.android;
  runApp(
    ProviderScope(
      overrides: [
        reminderSchedulerProvider.overrideWithValue(scheduler),
        // After LocalReminderScheduler.create(): the rest alert uses the
        // plugin that call initialised, and asks permission through it.
        restAlertSchedulerProvider.overrideWithValue(
          LocalRestAlertScheduler(scheduler),
        ),
        if (iPhone || android) ...[
          stepSourceProvider.overrideWithValue(
            iPhone ? IosStepSource() : AndroidStepSource(),
          ),
          stepPermissionProvider.overrideWithValue(DeviceStepPermission()),
        ],
      ],
      child: const FitSyncApp(),
    ),
  );
}

class FitSyncApp extends ConsumerWidget {
  const FitSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    title: 'FitSync',
    debugShowCheckedModeBanner: false,
    theme: fsLightTheme(),
    darkTheme: fsDarkTheme(),
    // Never ThemeMode.system: the user picks explicitly in Settings, and
    // the stored choice is restored on launch.
    themeMode: ref.watch(themeModeProvider),
    home: const AppShell(),
  );
}
