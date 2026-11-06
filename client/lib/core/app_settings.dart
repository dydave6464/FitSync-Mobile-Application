import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Opens FitSync's page in the phone's Settings, where a permission turned
/// down for good (the camera, notifications) can be turned back on.
///
/// Here rather than with any one feature: Snap a meal, Home's reminder
/// prompt and Reminders all send the user there. Injectable for tests,
/// which have no Settings app to open.
final appSettingsOpenerProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await ph.openAppSettings();
  },
);
