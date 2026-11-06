import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/app_settings.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../plans/presentation/providers.dart' show activePlanProvider;
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

/// Shown wherever turning reminders on meets a notification permission the
/// phone has refused.
const remindersBlockedText =
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

  /// Re-checks permission on resume, so a grant made from the phone's own
  /// settings while this screen was left open behind it (the only way to
  /// grant it once refused -- the app cannot re-ask) clears the banner
  /// without needing the screen reopened.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _refreshGranted();
    _lifecycle = AppLifecycleListener(onResume: _refreshGranted);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refreshGranted() async {
    // Checked before touching `ref` at all, not only after the await below:
    // a caller that itself just resumed from an await (`_setEnabled` after
    // `requestPermission`) may already be unmounted by the time this runs,
    // and `ref.read` throws on a disposed widget rather than returning
    // stale data.
    if (!mounted) return;
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
          .showSnackBar(SnackBar(content: Text(userMessage(error))));
    }
  }

  /// The value each switch shows while its save is in flight, by field. The
  /// switch moves on the tap rather than after the round trip, and a field
  /// in here ignores further taps, so a slow network sends one PATCH, not
  /// one per impatient tap.
  final _pending = <String, bool>{};

  /// The lead time on its way to the server, the chips' [_pending]: the
  /// chip moves on the tap, and further taps wait until the answer.
  int? _pendingLead;

  /// Saves a new habit lead time. The selected chip, or any tap while one
  /// save is in flight, sends nothing.
  Future<void> _setLead(int minutes, int saved) async {
    if (_pendingLead != null || minutes == saved) return;
    setState(() => _pendingLead = minutes);
    try {
      await _save(
        () => ref.read(reminderSettingsProvider.notifier).patch({
          'habitLeadMin': minutes,
        }),
      );
    } finally {
      // The provider holds the saved value, or the old one after a failure.
      if (mounted) setState(() => _pendingLead = null);
    }
  }

  /// Turning a reminder off always saves. Turning one on asks for permission
  /// first when it is not already granted; a refusal saves nothing, and the
  /// switch goes back to off because [savePatch] never ran. A failed save
  /// goes back too, with the reason in a SnackBar.
  Future<void> _setEnabled(
    String field,
    bool value,
    Future<void> Function() savePatch,
  ) async {
    if (_pending.containsKey(field)) return;
    setState(() => _pending[field] = value);
    try {
      if (value && !_granted) {
        final granted = await ref
            .read(reminderSchedulerProvider)
            .requestPermission();
        // The system prompt this just awaited can outlive the screen -- a
        // pop (or the signed-in shell tearing down) while it is up leaves
        // `ref` unusable, so nothing below may touch it.
        if (!mounted) return;
        await _refreshGranted();
        if (!granted) return;
      }
      await _save(savePatch);
    } finally {
      // By now the provider holds the saved value, or the old one after a
      // refusal or failure: either way it is the truth to show.
      if (mounted) setState(() => _pending.remove(field));
    }
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
        error: (error, _) => FsRetry(
          fullScreen: true,
          message: userMessage(error),
          buttonKey: const Key('reminders.retry'),
          onRetry: () => ref.invalidate(reminderSettingsProvider),
        ),
        data: (loadedSettings) => profile.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => FsRetry(
            fullScreen: true,
            message: userMessage(error),
            buttonKey: const Key('reminders.retry'),
            onRetry: () => ref.invalidate(profileProvider),
          ),
          data: (loadedProfile) => _body(loadedSettings, loadedProfile),
        ),
      ),
    );
  }

  /// With the master switch off nothing below it is scheduled
  /// (`planReminders` returns nothing), so the three sections are shown
  /// dimmed and disabled, with a line that says why, rather than looking
  /// live.
  Widget _body(ReminderSettings settings, Profile profile) {
    // The master switch's value while its save is on its way, so turning it
    // on brings the sections to life at once, as the switch itself moves.
    final live =
        _pending['notificationsEnabled'] ?? profile.notificationsEnabled;
    // Only a plan known to be absent: while it loads, or if it failed, the
    // note would be a guess.
    final plan = ref.watch(activePlanProvider);
    final noPlan = plan.hasValue && plan.value == null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        _masterRow(profile.notificationsEnabled),
        if (!live) ...[
          const SizedBox(height: 8),
          _note(
            'Reminders are off. Turn this on to get any of the reminders '
            'below.',
          ),
        ],
        if (!_granted) ...[const SizedBox(height: 14), _blockedBanner()],
        const SizedBox(height: 22),
        _habitsSection(settings, enabled: live),
        const SizedBox(height: 22),
        _workoutSection(settings, enabled: live, noPlan: noPlan),
        const SizedBox(height: 22),
        _checkinSection(settings, enabled: live),
      ],
    );
  }

  /// A line of explanation under a row or section.
  Widget _note(String text) => Text(
    text,
    style: TextStyle(fontSize: 12, height: 1.4, color: context.fs.text2),
  );

  /// One section: its eyebrow, its card, and any notes under the card. A
  /// disabled section's card is dimmed as FsButton dims a disabled button;
  /// its controls are disabled by the caller, so a screen reader says so
  /// too. The notes stay at full strength: they say why.
  Widget _section({
    required String title,
    required bool enabled,
    required List<Widget> children,
    List<String> notes = const [],
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FsEyebrow(title),
      const SizedBox(height: 10),
      Opacity(
        opacity: enabled ? 1 : 0.45,
        child: FsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
      for (final note in notes) ...[const SizedBox(height: 8), _note(note)],
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

  /// A label and its switch, read as one control: "Remind me about habits,
  /// switch, on" rather than a bare "switch, on" beside a separate line of
  /// text.
  ///
  /// [field] names the setting for [_pending]; [saved] is its stored value
  /// and [save] writes a new one. A disabled row ([enabled] false) has no
  /// handler, so the switch reads as disabled.
  Widget _switchRow({
    required String label,
    required Key switchKey,
    required String field,
    required bool saved,
    required Future<void> Function(bool value) save,
    bool enabled = true,
    List<Widget> leading = const [],
  }) {
    return MergeSemantics(
      child: Row(
        children: [
          ...leading,
          _rowLabel(label),
          Switch(
            key: switchKey,
            value: _pending[field] ?? saved,
            onChanged: !enabled
                ? null
                : (value) => _setEnabled(field, value, () => save(value)),
          ),
        ],
      ),
    );
  }

  Widget _masterRow(bool notificationsEnabled) {
    return FsCard(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _switchRow(
        leading: [
          FsIconTile(icon: Icons.notifications_outlined, size: 32),
          const SizedBox(width: 13),
        ],
        label: 'Notifications & reminders',
        switchKey: const Key('reminders.master'),
        field: 'notificationsEnabled',
        saved: notificationsEnabled,
        save: (value) => ref.read(profileProvider.notifier).patch({
          'notificationsEnabled': value,
        }),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  remindersBlockedText,
                  style: TextStyle(fontSize: 12, color: t.text2, height: 1.4),
                ),
                const SizedBox(height: 8),
                // Once refused, the app cannot ask again: the phone's own
                // settings are the only way back. Returning here re-checks
                // (the resume listener) and clears this banner.
                FsButton(
                  key: const Key('reminders.openSettings'),
                  label: 'Open settings',
                  small: true,
                  kind: FsButtonKind.secondary,
                  onPressed: () => ref.read(appSettingsOpenerProvider)(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Time" and the clock, opening the time picker. [spokenAs] says which
  /// reminder's time it is: two sections show a row that reads just "Time".
  /// At least 48 dp tall, a thumb's target.
  Widget _timeRow(
    Key rowKey,
    String time, {
    required String spokenAs,
    required VoidCallback? onTap,
  }) {
    final t = context.fs;
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: '$spokenAs, ${formatClock(time)}',
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          // The label above says it all; the row's own words would only
          // repeat it.
          child: ExcludeSemantics(
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
        ),
      ),
    );
  }

  Widget _habitsSection(ReminderSettings settings, {required bool enabled}) =>
      _section(
        title: 'Habits',
        enabled: enabled,
        // planReminders skips any-time habits: there is no moment to remind.
        notes: const ['Only habits with a set time get a reminder.'],
        children: [
          _switchRow(
            label: 'Remind me about habits',
            switchKey: const Key('reminders.habits'),
            field: 'habitsEnabled',
            saved: settings.habitsEnabled,
            enabled: enabled,
            save: (value) => ref.read(reminderSettingsProvider.notifier).patch({
              'habitsEnabled': value,
            }),
          ),
          const SizedBox(height: 12),
          // Chips that wrap whole rather than a four-way segmented control,
          // which cut "before" short at large text. The 12 dp above and the
          // card's padding below are the room their 48 dp band reaches into.
          FsTapRoom(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _leadOptions)
                  FsChip(
                    key: Key('reminders.lead.${option.value}'),
                    label: option.label,
                    selected:
                        (_pendingLead ?? settings.habitLeadMin).toString() ==
                        option.value,
                    onTap: !enabled
                        ? null
                        : () => _setLead(
                            int.parse(option.value),
                            settings.habitLeadMin,
                          ),
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _workoutSection(
    ReminderSettings settings, {
    required bool enabled,
    required bool noPlan,
  }) => _section(
    title: 'Workout on training days',
    enabled: enabled,
    notes: [if (noPlan) 'Workout reminders need a plan.'],
    children: [
      _switchRow(
        label: 'Remind me before my workout',
        switchKey: const Key('reminders.workout'),
        field: 'workoutEnabled',
        saved: settings.workoutEnabled,
        enabled: enabled,
        save: (value) => ref.read(reminderSettingsProvider.notifier).patch({
          'workoutEnabled': value,
        }),
      ),
      _timeRow(
        const Key('reminders.workoutTime'),
        settings.workoutTime,
        spokenAs: 'Workout reminder time',
        onTap: !enabled
            ? null
            : () => _pickTime(
                initial: settings.workoutTime,
                field: 'workoutTime',
              ),
      ),
    ],
  );

  Widget _checkinSection(ReminderSettings settings, {required bool enabled}) =>
      _section(
        title: 'Morning check-in',
        enabled: enabled,
        children: [
          _switchRow(
            label: 'Remind me to check in',
            switchKey: const Key('reminders.checkin'),
            field: 'checkinEnabled',
            saved: settings.checkinEnabled,
            enabled: enabled,
            save: (value) => ref.read(reminderSettingsProvider.notifier).patch({
              'checkinEnabled': value,
            }),
          ),
          _timeRow(
            const Key('reminders.checkinTime'),
            settings.checkinTime,
            spokenAs: 'Check-in reminder time',
            onTap: !enabled
                ? null
                : () => _pickTime(
                    initial: settings.checkinTime,
                    field: 'checkinTime',
                  ),
          ),
        ],
      );
}
