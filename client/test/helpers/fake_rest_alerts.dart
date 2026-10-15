import 'package:fitsync/features/sessions/data/rest_alerts.dart';

/// Records what the logger asks of the phone's notifications.
class FakeRestAlertScheduler implements RestAlertScheduler {
  FakeRestAlertScheduler({this.granted = true, this.grantOnRequest = false});

  bool granted;
  final bool grantOnRequest;
  int requests = 0;
  int cancels = 0;
  int settingsOpened = 0;
  final scheduled = <({DateTime at, String title, String body})>[];

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<void> schedule({
    required DateTime at,
    required String title,
    required String body,
  }) async => scheduled.add((at: at, title: title, body: body));

  @override
  Future<void> cancel() async => cancels++;
}
