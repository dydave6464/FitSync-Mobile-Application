import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/reminders/data/local_reminder_scheduler.dart';

void main() {
  // ReminderSync clears and reschedules reminders after every change it
  // watches -- including the routine refresh right after a set is logged --
  // and a rest alert scheduled the moment the phone locked must survive it.
  test('clearing reminders spares the rest alert', () {
    expect(reminderIdsToCancel([0, 1, 2, 990001, 7]), [0, 1, 2, 7]);
  });
}
