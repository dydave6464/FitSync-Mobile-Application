import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../onboarding/presentation/edit_scaffold.dart';
import '../../onboarding/presentation/steps/about_step.dart';
import '../../onboarding/presentation/steps/goal_step.dart';
import '../../onboarding/presentation/steps/injuries_step.dart';
import '../../onboarding/presentation/steps/level_step.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';

/// FR-1.4: change any onboarding answer later.
///
/// Every row opens the same step widget the wizard used, wrapped in
/// [EditScaffold] instead of the wizard chrome. That is why this file is
/// wiring rather than four more screens.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
                FilledButton(
                  onPressed: () => ref.invalidate(profileProvider),
                  child: const Text('Retry'),
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

class _SettingsList extends ConsumerWidget {
  const _SettingsList({required this.profile});

  final Profile profile;

  void _open(BuildContext context, Widget editor) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => editor),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(profile.fullName),
          subtitle: Text(
            [profile.email, if (profile.city != null) profile.city!].join(' · '),
          ),
        ),
        const Divider(),
        ListTile(
          key: const Key('edit.goal'),
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Goal'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const _GoalEditor()),
        ),
        ListTile(
          key: const Key('edit.about'),
          leading: const Icon(Icons.straighten_outlined),
          title: const Text('Body metrics'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const _AboutEditor()),
        ),
        ListTile(
          key: const Key('edit.level'),
          leading: const Icon(Icons.fitness_center_outlined),
          title: const Text('Experience & equipment'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const _LevelEditor()),
        ),
        ListTile(
          key: const Key('edit.injuries'),
          leading: const Icon(Icons.healing_outlined),
          title: const Text('Injuries'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const _InjuriesEditor()),
        ),
        const Divider(),
        SwitchListTile(
          key: const Key('notifications'),
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          value: profile.notificationsEnabled,
          onChanged: (value) => ref
              .read(profileProvider.notifier)
              .patch({'notificationsEnabled': value}),
        ),
        const Divider(),
        ListTile(
          key: const Key('signOut'),
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => ref.read(authControllerProvider.notifier).signOut(),
        ),
      ],
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
  String? _value;
  bool _seeded = false;

  @override
  String get title => 'Goal';

  @override
  Widget buildStep(Profile profile) {
    if (!_seeded) {
      _seeded = true;
      _value = profile.mainGoal;
    }
    return GoalStep(
      value: _value,
      onChanged: (value) => setState(() => _value = value),
    );
  }

  @override
  Future<void> save(ProfileNotifier notifier) async {
    if (_value == null) return;
    await notifier.patch({'mainGoal': _value});
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
    return AboutStep(value: _value, onChanged: (value) => _value = value);
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
  String get title => 'Experience & equipment';

  @override
  Widget buildStep(Profile profile) {
    if (!_seeded) {
      _seeded = true;
      _value = LevelAnswers(
        fitnessLevel: profile.fitnessLevel,
        trainingLocation: profile.trainingLocation,
        equipmentIds:
            profile.equipment.map((e) => e.equipmentId).toList(growable: false),
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
