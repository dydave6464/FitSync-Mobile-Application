import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/theme_controller.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../health/domain/health_answers.dart';
import '../../health/presentation/providers.dart';
import '../../onboarding/presentation/edit_scaffold.dart';
import '../../onboarding/presentation/steps/about_step.dart';
import '../../onboarding/presentation/steps/goal_step.dart';
import '../../onboarding/presentation/steps/health_step.dart';
import '../../onboarding/presentation/steps/injuries_step.dart';
import '../../onboarding/presentation/steps/level_step.dart';
import '../../plans/presentation/widgets/training_days_row.dart';
import '../../pro/presentation/pro_screen.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';
import '../../reminders/presentation/reminders_screen.dart';
import '../../streaks/presentation/streaks_screen.dart';
import '../../schedule/presentation/schedule_screen.dart';

/// FR-1.4: change any onboarding answer later.
///
/// Every row opens the same step widget the wizard used, wrapped in
/// [EditScaffold] instead of the wizard chrome. That is why this file is
/// wiring rather than four more screens.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final profile = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: const [_ThemeToggleButton()],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(describeError(error), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FsButton(
                  label: 'Retry',
                  small: true,
                  onPressed: () => ref.invalidate(profileProvider),
                ),
              ],
            ),
          ),
        ),
        data: (loaded) => _SettingsList(profile: loaded),
      ),
    );
  }
}

/// Dark/light in the header, where the prototype's Profile bar puts its one
/// icon button -- rather than a row the user has to scroll the whole screen
/// to reach. It is the only control for the setting: a second one in the App
/// card would be the same switch drawn twice.
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return IconButton(
      key: const Key('themeToggle'),
      // The icon the row used, kept so the meaning does not change with the
      // move: it names the mode you are in, not the one you would get.
      icon: Icon(isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
      tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
      onPressed: () => ref.read(themeModeProvider.notifier).setDark(!isDark),
    );
  }
}

/// The level as the level step words it. Capitalising the stored value read
/// fine for beginner and intermediate and as "New" for New to training.
String _levelLabel(String level) => switch (level) {
  'new' => 'New to training',
  'beginner' => 'Beginner',
  'intermediate' => 'Intermediate',
  _ => level,
};

class _SettingsList extends ConsumerWidget {
  const _SettingsList({required this.profile});

  final Profile profile;

  void _open(BuildContext context, Widget editor) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => editor));

  String get _initials {
    final parts = profile.fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final theme = Theme.of(context);

    final subtitle = [
      if (profile.fitnessLevel != null) _levelLabel(profile.fitnessLevel!),
      if (profile.city != null) profile.city!,
      if (profile.fitnessLevel == null && profile.city == null) profile.email,
    ].join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        FsCard(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(FsRadius.md),
                  border: Border.all(color: t.line),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.fullName, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: t.text3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // The prototype's Profile screen carries this card, and it is the one
        // route to Pro that does not require meeting a lock first.
        FsCard(
          key: const Key('settings.goPro'),
          accent: true,
          onTap: () => openProScreen(context),
          child: Row(
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                size: 22,
                color: t.accentText,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FitSync Pro',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'See where your training volume goes',
                      style: TextStyle(fontSize: 11, color: t.text3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 17, color: t.accentText),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Training'),
        const SizedBox(height: 10),
        FsCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _SettingsRow(
                rowKey: const Key('edit.goal'),
                icon: Icons.flag_outlined,
                label: 'Goals',
                onTap: () => _open(context, const _GoalEditor()),
              ),
              _SettingsRow(
                rowKey: const Key('edit.about'),
                icon: Icons.straighten_outlined,
                label: 'Body metrics (height, weight)',
                onTap: () => _open(context, const _AboutEditor()),
              ),
              _SettingsRow(
                rowKey: const Key('edit.level'),
                icon: Icons.fitness_center_outlined,
                label: 'Equipment & location',
                onTap: () => _open(context, const _LevelEditor()),
              ),
              _SettingsRow(
                rowKey: const Key('edit.injuries'),
                icon: Icons.healing_outlined,
                label: 'Injuries',
                iconColor: t.red,
                onTap: () => _open(context, const _InjuriesEditor()),
              ),
              _SettingsRow(
                rowKey: const Key('edit.health'),
                icon: Icons.health_and_safety_outlined,
                label: 'Health',
                onTap: () => _open(context, const _HealthEditor()),
              ),
              _SettingsRow(
                rowKey: const Key('edit.trainingDays'),
                icon: Icons.event_available_outlined,
                label: 'Training days',
                onTap: () => _open(context, const _TrainingDaysEditor()),
              ),
              _SettingsRow(
                rowKey: const Key('edit.schedule'),
                icon: Icons.calendar_month_outlined,
                label: 'Schedule',
                onTap: () => _open(context, const ScheduleScreen()),
              ),
              _SettingsRow(
                rowKey: const Key('edit.streaks'),
                icon: Icons.emoji_events_outlined,
                label: 'Streaks & goals',
                onTap: () => _open(context, const StreaksScreen()),
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const FsEyebrow('App'),
        const SizedBox(height: 10),
        FsCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _SettingsRow(
                icon: Icons.monitor_weight_outlined,
                label: 'Weight unit',
                trailing: FsUnitToggle(
                  value: profile.weightUnit,
                  onChanged: (unit) => ref.read(profileProvider.notifier).patch(
                    {'weightUnit': unit.api},
                  ),
                ),
              ),
              _SettingsRow(
                rowKey: const Key('notifications'),
                icon: Icons.notifications_outlined,
                label: 'Notifications & reminders',
                onTap: () => _open(context, const RemindersScreen()),
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        FsButton(
          key: const Key('signOut'),
          label: 'Sign out',
          kind: FsButtonKind.ghost,
          danger: true,
          small: true,
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
        ),
      ],
    );
  }
}

/// The prototype's `SettRow`: square icon tile, label, trailing control, and a
/// hairline between rows.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.rowKey,
    this.onTap,
    this.trailing,
    this.iconColor,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final Key? rowKey;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return InkWell(
      key: rowKey,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: t.line)),
        ),
        child: Row(
          children: [
            FsIconTile(icon: icon, size: 32, color: iconColor),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: t.text,
                ),
              ),
            ),
            trailing ?? Icon(Icons.chevron_right, size: 16, color: t.text3),
          ],
        ),
      ),
    );
  }
}

/// Shared plumbing for the four editors: hold a working value, save it, pop.
///
/// [save] does the writing so each editor can use whichever endpoint its
/// answer belongs to — a profile patch for some, a replace-set for others.
abstract class _EditorState<W extends ConsumerStatefulWidget>
    extends ConsumerState<W> {
  bool _busy = false;
  String? _error;

  String get title;
  Widget buildStep(Profile profile);
  Future<void> save(ProfileNotifier notifier);

  Future<void> _onSave() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    // Captured before the await: this screen pops itself on success, and
    // ScaffoldMessenger.of() reads the nearest messenger, which by then is
    // gone. The app-level messenger outlives the pop, so the confirmation
    // lands on Settings rather than on a route being torn down.
    final messenger = ScaffoldMessenger.of(context);

    try {
      await save(ref.read(profileProvider.notifier));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _busy = false;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    // Named, not a bare "Saved": these editors all look alike once closed,
    // and returning to Settings was previously the only sign anything had
    // been written — indistinguishable from a screen that closed on its own.
    messenger.showSnackBar(SnackBar(content: Text('$title saved')));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return EditScaffold(
      title: title,
      busy: _busy,
      onSave: _onSave,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildStep(profile),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              key: const Key('error'),
              style: TextStyle(fontSize: 12.5, color: context.fs.red),
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalEditor extends ConsumerStatefulWidget {
  const _GoalEditor();

  @override
  ConsumerState<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends _EditorState<_GoalEditor> {
  GoalAnswers _value = const GoalAnswers();
  bool _seeded = false;

  @override
  String get title => 'Goals';

  @override
  Widget buildStep(Profile profile) {
    if (!_seeded) {
      _seeded = true;
      _value = GoalAnswers.fromProfile(profile);
    }
    return GoalStep(
      value: _value,
      onChanged: (v) => setState(() => _value = v),
    );
  }

  @override
  Future<void> save(ProfileNotifier notifier) async {
    if (_value.goals.isEmpty) return;
    await notifier.setGoals(_value.goals, _value.mainGoal!);
  }
}

class _AboutEditor extends ConsumerStatefulWidget {
  const _AboutEditor();

  @override
  ConsumerState<_AboutEditor> createState() => _AboutEditorState();
}

class _AboutEditorState extends _EditorState<_AboutEditor> {
  AboutAnswers _value = const AboutAnswers();
  bool _seeded = false;

  @override
  String get title => 'Body metrics';

  @override
  Widget buildStep(Profile profile) {
    if (!_seeded) {
      _seeded = true;
      _value = AboutAnswers(
        sex: profile.sex,
        dateOfBirth: profile.dateOfBirth,
        heightCm: profile.heightCm,
        weightKg: profile.weightKg,
        goalWeightKg: profile.goalWeightKg,
        activityLevel: profile.activityLevel,
      );
    }
    return AboutStep(
      value: _value,
      onChanged: (value) => _value = value,
      // Not part of the form's working value: it is a display preference, so
      // it saves on tap and survives a cancelled edit rather than sitting in
      // _value waiting for Save.
      unit: profile.weightUnit,
      onUnitChanged: (unit) =>
          ref.read(profileProvider.notifier).patch({'weightUnit': unit.api}),
    );
  }

  @override
  Future<void> save(ProfileNotifier notifier) async {
    final fields = {
      if (_value.sex != null) 'sex': _value.sex,
      if (_value.dateOfBirth != null) 'dateOfBirth': _value.dateOfBirth,
      if (_value.heightCm != null) 'heightCm': _value.heightCm,
      if (_value.weightKg != null) 'weightKg': _value.weightKg,
      if (_value.goalWeightKg != null) 'goalWeightKg': _value.goalWeightKg,
      if (_value.activityLevel != null) 'activityLevel': _value.activityLevel,
    };
    if (fields.isNotEmpty) await notifier.patch(fields);
  }
}

class _LevelEditor extends ConsumerStatefulWidget {
  const _LevelEditor();

  @override
  ConsumerState<_LevelEditor> createState() => _LevelEditorState();
}

class _LevelEditorState extends _EditorState<_LevelEditor> {
  LevelAnswers _value = const LevelAnswers();
  bool _seeded = false;

  @override
  String get title => 'Equipment & location';

  @override
  Widget buildStep(Profile profile) {
    if (!_seeded) {
      _seeded = true;
      _value = LevelAnswers(
        fitnessLevel: profile.fitnessLevel,
        trainingLocation: profile.trainingLocation,
        equipmentIds: profile.equipment
            .map((e) => e.equipmentId)
            .toList(growable: false),
      );
    }
    return LevelStep(
      value: _value,
      onChanged: (value) => setState(() => _value = value),
    );
  }

  @override
  Future<void> save(ProfileNotifier notifier) async {
    final fields = {
      if (_value.fitnessLevel != null) 'fitnessLevel': _value.fitnessLevel,
      if (_value.trainingLocation != null)
        'trainingLocation': _value.trainingLocation,
    };
    if (fields.isNotEmpty) await notifier.patch(fields);
    await notifier.setEquipment(_value.equipmentIds);
  }
}

class _InjuriesEditor extends ConsumerStatefulWidget {
  const _InjuriesEditor();

  @override
  ConsumerState<_InjuriesEditor> createState() => _InjuriesEditorState();
}

class _InjuriesEditorState extends _EditorState<_InjuriesEditor> {
  List<SelectedInjury> _value = const [];
  bool _seeded = false;

  @override
  String get title => 'Injuries';

  @override
  Widget buildStep(Profile profile) {
    if (!_seeded) {
      _seeded = true;
      _value = profile.injuries;
    }
    return InjuriesStep(
      value: _value,
      onChanged: (value) => setState(() => _value = value),
    );
  }

  @override
  Future<void> save(ProfileNotifier notifier) => notifier.setInjuries(_value);
}

/// The health check, edited outside onboarding.
///
/// Not an [_EditorState]: those seed from the profile, and the answers are
/// deliberately not part of the profile. Saving or deleting changes the next
/// plan built, not the plan the user has now.
class _HealthEditor extends ConsumerStatefulWidget {
  const _HealthEditor();

  @override
  ConsumerState<_HealthEditor> createState() => _HealthEditorState();
}

class _HealthEditorState extends ConsumerState<_HealthEditor> {
  HealthAnswers _value = const HealthAnswers();
  bool _seeded = false;
  bool _busy = false;
  String? _error;

  /// Runs a write, then closes with [done]; a refused write stays open and
  /// shows why, like the other editors.
  Future<void> _run(Future<void> Function() write, String done) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await write();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _busy = false;
      });
      return;
    }
    // No invalidate: healthProvider is autoDispose and only this editor
    // watches it, so closing the editor drops the cached answers anyway.
    // Invalidating here would flash the loading spinner before the pop.
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _save() => _run(
    () => ref.read(healthRepositoryProvider).setHealth(_value),
    'Health saved',
  );

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete your health answers?'),
        content: const Text(
          'Your next plan goes back to your usual sets and session length.',
        ),
        actions: [
          TextButton(
            key: const Key('health.delete.cancel'),
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('health.delete.confirm'),
            style: TextButton.styleFrom(foregroundColor: dialog.fs.red),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(healthRepositoryProvider).deleteHealth(),
      'Health answers deleted',
    );
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(healthProvider);

    return stored.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Health')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(describeError(error), textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (saved) {
        if (!_seeded) {
          _seeded = true;
          if (saved != null) _value = saved;
        }
        return EditScaffold(
          title: 'Health',
          busy: _busy,
          onSave: _value.isValid ? _save : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              HealthStep(
                value: _value,
                allowOptOut: false,
                onChanged: (v) => setState(() => _value = v),
              ),
              if (saved != null) ...[
                const SizedBox(height: 24),
                FsButton(
                  key: const Key('health.delete'),
                  label: 'Delete my health answers',
                  kind: FsButtonKind.ghost,
                  danger: true,
                  small: true,
                  onPressed: _busy ? null : _delete,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  key: const Key('error'),
                  style: TextStyle(fontSize: 12.5, color: context.fs.red),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TrainingDaysEditor extends ConsumerStatefulWidget {
  const _TrainingDaysEditor();

  @override
  ConsumerState<_TrainingDaysEditor> createState() =>
      _TrainingDaysEditorState();
}

class _TrainingDaysEditorState extends _EditorState<_TrainingDaysEditor> {
  List<int> _value = const [];
  bool _seeded = false;

  @override
  String get title => 'Training days';

  @override
  Widget buildStep(Profile profile) {
    // Seeded once, behind the flag the other editors use: re-reading the
    // profile on every rebuild would discard the taps made since opening.
    if (!_seeded) {
      _seeded = true;
      _value = profile.trainingDays;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FsEyebrow('Which days do you train?'),
        const SizedBox(height: 10),
        TrainingDaysRow(
          selected: _value,
          onChanged: (next) => setState(() => _value = next),
        ),
        const SizedBox(height: 12),
        Text(
          'Leave every day off if your week varies. Your plan is the same '
          'either way -- this only decides which days can be reported as '
          'missed.',
          style: TextStyle(fontSize: 12, color: context.fs.text3, height: 1.4),
        ),
      ],
    );
  }

  @override
  Future<void> save(ProfileNotifier notifier) =>
      notifier.setTrainingDays(_value);
}
