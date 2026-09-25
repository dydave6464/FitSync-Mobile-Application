/// What the phone reminds about, from GET /reminders/settings. The master
/// switch is the profile's notificationsEnabled, not a field here.
class ReminderSettings {
  const ReminderSettings({
    required this.habitsEnabled,
    required this.habitLeadMin,
    required this.workoutEnabled,
    required this.workoutTime,
    required this.checkinEnabled,
    required this.checkinTime,
  });

  final bool habitsEnabled;

  /// 0, 5, 15 or 30 minutes before a timed habit.
  final int habitLeadMin;
  final bool workoutEnabled;

  /// `HH:MM`, 24-hour, Manila.
  final String workoutTime;
  final bool checkinEnabled;
  final String checkinTime;

  static const defaults = ReminderSettings(
    habitsEnabled: true,
    habitLeadMin: 15,
    workoutEnabled: false,
    workoutTime: '07:00',
    checkinEnabled: false,
    checkinTime: '07:00',
  );

  factory ReminderSettings.fromJson(Map<String, dynamic> json) =>
      ReminderSettings(
        habitsEnabled: json['habitsEnabled'] as bool,
        habitLeadMin: json['habitLeadMin'] as int,
        workoutEnabled: json['workoutEnabled'] as bool,
        workoutTime: json['workoutTime'] as String,
        checkinEnabled: json['checkinEnabled'] as bool,
        checkinTime: json['checkinTime'] as String,
      );
}

/// One notification to schedule.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// 0.. in time order; the whole set is replaced on every reschedule.
  final int id;

  /// A UTC instant.
  final DateTime at;
  final String title;
  final String body;

  /// Where a tap opens: `routine` or `recovery`.
  final String payload;
}

/// What is already done today, so today's reminder for it is skipped.
class TodayDone {
  const TodayDone({
    required this.habitIds,
    required this.workout,
    required this.checkin,
  });

  final Set<int> habitIds;
  final bool workout;
  final bool checkin;

  static const none = TodayDone(habitIds: {}, workout: false, checkin: false);
}
