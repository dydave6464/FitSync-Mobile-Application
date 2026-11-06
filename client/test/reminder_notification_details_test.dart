import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/reminders/data/local_reminder_scheduler.dart';
import 'package:fitsync/features/reminders/domain/reminders.dart';

void main() {
  // P-14: the longer bodies ("Push Pull Legs at 6:00 PM — tap to get
  // started") ran past one collapsed line, so the phone could cut what to
  // do. Big-text style lets the shade show the whole body.
  test('a reminder shows its whole body, not one cut line', () {
    final reminder = PlannedReminder(
      id: 0,
      at: DateTime.utc(2026, 11, 6, 10),
      title: 'Workout today',
      body: 'Push Pull Legs at 6:00 PM — tap to get started',
      payload: 'routine',
    );

    final android = reminderNotificationDetails(reminder).android!;

    expect(android.channelId, 'reminders');
    expect(android.importance, Importance.defaultImportance);
    final style = android.styleInformation;
    expect(style, isA<BigTextStyleInformation>());
    expect(
      (style! as BigTextStyleInformation).bigText,
      'Push Pull Legs at 6:00 PM — tap to get started',
    );
  });
}
