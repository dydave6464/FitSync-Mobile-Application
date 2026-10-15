/// Local-notification ids that more than one feature has to agree on.
///
/// Reminders use small ids from 0 up (see plan_reminders.dart) and clear
/// their own before every reschedule; the rest alert sits far above them so
/// that clearing never takes it too.
const restAlertNotificationId = 990001;
