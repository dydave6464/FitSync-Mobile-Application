import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';
import '../../routine/domain/routine.dart' show formatClock;
import '../data/reminder_scheduler.dart';
import '../domain/reminders.dart';
import 'providers.dart';

/// The real system picker, wrapped to match the seam's positional signature
/// -- `showTimePicker` itself takes named parameters.
Future<TimeOfDay?> _systemPickTime(BuildContext context, TimeOfDay initial) =>
    showTimePicker(context: context, initialTime: initial);

const _leadOptions = [
  (value: '0', label: 'At the time'),
  (value: '5', label: '5 min before'),
  (value: '15', label: '15 min before'),
  (value: '30', label: '30 min before'),
];

const _blockedText =
    "Notifications are blocked for FitSync. Allow them in your phone's "
    'settings to get reminders.';

/// What the phone reminds about: the master switch, and each of habits,
/// workout and morning check-in with its own on/off and time.
///
/// This screen only saves. `ReminderSync`, mounted higher in the signed-in
/// shell, is what reschedules the phone's notifications whenever the
/// settings or profile it watches change -- so every patch here reaches the
/// phone without this screen touching `ReminderScheduler.scheduleAll` itself.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key, this.pickTime});

  /// Seam for tests: called instead of the real system dialog when set, so a
  /// test can answer a time picker deterministically.
  final Future<TimeOfDay?> Function(BuildContext, TimeOfDay)? pickTime;

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  /// Whether the phone currently lets FitSync show notifications. Checked
  /// once when the screen opens and again after any permission request, so
  /// the blocked banner reflects the OS setting without polling it on every
  /// rebuild.
  bool _granted = true;

  @override
  void initState() {
    super.initState();
    _refreshGranted();
  }

  Future<void> _refreshGranted() async {
    final granted = await ref
        .read(reminderSchedulerProvider)
        .permissionGranted();
    if (!mounted) return;
    setState(() => _granted = granted);
  }

  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  /// Turning a reminder off always saves. Turning one on asks for permission
  /// first when it is not already granted; a refusal saves nothing, and the
  /// switch stays off because [savePatch] never ran.
  Future<void> _setEnabled(
    bool value,
    Future<void> Function() savePatch,
  ) async {
    if (value && !_granted) {
      final granted = await ref
          .read(reminderSchedulerProvider)
          .requestPermission();
      await _refreshGranted();
      if (!granted) return;
    }
    await _save(savePatch);
  }

  Future<void> _pickTime({
    required String initial,
    required String field,
  }) async {
    final current = TimeOfDay(
      hour: int.parse(initial.substring(0, 2)),
      minute: int.parse(initial.substring(3, 5)),
    );
    final pick = widget.pickTime ?? _systemPickTime;
    final picked = await pick(context, current);
    if (picked == null || !mounted) return;
    final hhmm =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    await _save(
      () => ref.read(reminderSettingsProvider.notifier).patch({field: hhmm}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final settings = ref.watch(reminderSettingsProvider);
    final profile = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Reminders')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(describeError(error))),
        data: (loadedSettings) => profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(describeError(error))),
          data: (loadedProfile) => _body(loadedSettings, loadedProfile),
        ),
      ),
    );
  }

  Widget _body(ReminderSettings settings, Profile profile) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      _masterRow(profile.notificationsEnabled),
      if (!_granted) ...[const SizedBox(height: 14), _blockedBanner()],
      const SizedBox(height: 22),
      _habitsSection(settings),
      const SizedBox(height: 22),
      _workoutSection(settings),
      const SizedBox(height: 22),
      _checkinSection(settings),
    ],
  );

  Widget _rowLabel(String label) {
    final t = context.fs;
    return Expanded(
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: t.text,
        ),
      ),
    );
  }

  Widget _masterRow(bool notificationsEnabled) {
    return FsCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          FsIconTile(icon: Icons.notifications_outlined, size: 32),
          const SizedBox(width: 13),
          _rowLabel('Notifications & reminders'),
          Switch(
            key: const Key('reminders.master'),
            value: notificationsEnabled,
            onChanged: (value) => _setEnabled(
              value,
              () => ref.read(profileProvider.notifier).patch({
                'notificationsEnabled': value,
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blockedBanner() {
    final t = context.fs;
    return FsCard(
      key: const Key('reminders.blocked'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notifications_off_outlined, color: t.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _blockedText,
              style: TextStyle(fontSize: 12, color: t.text2, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeRow(Key rowKey, String time, {required VoidCallback onTap}) {
    final t = context.fs;
    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _rowLabel('Time'),
            Text(
              formatClock(time),
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: t.text3),
          ],
        ),
      ),
    );
  }

  Widget _habitsSection(ReminderSettings settings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FsEyebrow('Habits'),
      const SizedBox(height: 10),
      FsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _rowLabel('Remind me about habits'),
                Switch(
                  key: const Key('reminders.habits'),
                  value: settings.habitsEnabled,
                  onChanged: (value) => _setEnabled(
                    value,
                    () => ref.read(reminderSettingsProvider.notifier).patch({
                      'habitsEnabled': value,
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FsSegmented(
              options: _leadOptions,
              selected: settings.habitLeadMin.toString(),
              onSelected: (value) => _save(
                () => ref.read(reminderSettingsProvider.notifier).patch({
                  'habitLeadMin': int.parse(value),
                }),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _workoutSection(ReminderSettings settings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FsEyebrow('Workout on training days'),
      const SizedBox(height: 10),
      FsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _rowLabel('Remind me before my workout'),
                Switch(
                  key: const Key('reminders.workout'),
                  value: settings.workoutEnabled,
                  onChanged: (value) => _setEnabled(
                    value,
                    () => ref.read(reminderSettingsProvider.notifier).patch({
                      'workoutEnabled': value,
                    }),
                  ),
                ),
              ],
            ),
            _timeRow(
              const Key('reminders.workoutTime'),
              settings.workoutTime,
              onTap: () => _pickTime(
                initial: settings.workoutTime,
                field: 'workoutTime',
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _checkinSection(ReminderSettings settings) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FsEyebrow('Morning check-in'),
      const SizedBox(height: 10),
      FsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _rowLabel('Remind me to check in'),
                Switch(
                  key: const Key('reminders.checkin'),
                  value: settings.checkinEnabled,
                  onChanged: (value) => _setEnabled(
                    value,
                    () => ref.read(reminderSettingsProvider.notifier).patch({
                      'checkinEnabled': value,
                    }),
                  ),
                ),
              ],
            ),
            _timeRow(
              const Key('reminders.checkinTime'),
              settings.checkinTime,
              onTap: () => _pickTime(
                initial: settings.checkinTime,
                field: 'checkinTime',
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
