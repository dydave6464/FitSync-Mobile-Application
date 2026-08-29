import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';
import 'onboarding_scaffold.dart';
import 'steps/about_step.dart';
import 'steps/goal_step.dart';
import 'steps/level_step.dart';

/// Sequences the four onboarding steps.
///
/// Saves on every Continue rather than once at the end: a user who drops out
/// on step 3 keeps what they answered on steps 1 and 2, and comes back to a
/// partly-filled profile instead of a blank one.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  static const _total = 4;

  int _index = 0;
  bool _busy = false;
  String? _error;
  bool _seeded = false;

  // The working answers. Seeded once from the loaded profile so a returning
  // user sees what they already chose.
  String? _mainGoal;
  AboutAnswers _about = const AboutAnswers();
  LevelAnswers _level = const LevelAnswers();

  void _seedFrom(Profile profile) {
    if (_seeded) return;
    _seeded = true;
    _mainGoal = profile.mainGoal;
    _about = AboutAnswers(
      sex: profile.sex,
      dateOfBirth: profile.dateOfBirth,
      heightCm: profile.heightCm,
      weightKg: profile.weightKg,
      goalWeightKg: profile.goalWeightKg,
      activityLevel: profile.activityLevel,
    );
    _level = LevelAnswers(
      fitnessLevel: profile.fitnessLevel,
      trainingLocation: profile.trainingLocation,
      equipmentIds:
          profile.equipment.map((e) => e.equipmentId).toList(growable: false),
    );
  }

  /// Only the keys the user actually answered. The server reads an absent key
  /// as "leave alone" and an explicit null as "clear", so sending the whole
  /// object would wipe fields this step never asked about.
  Map<String, dynamic> _patchForCurrentStep() => switch (_index) {
        0 => {if (_mainGoal != null) 'mainGoal': _mainGoal},
        1 => {
            if (_about.sex != null) 'sex': _about.sex,
            if (_about.dateOfBirth != null) 'dateOfBirth': _about.dateOfBirth,
            if (_about.heightCm != null) 'heightCm': _about.heightCm,
            if (_about.weightKg != null) 'weightKg': _about.weightKg,
            if (_about.goalWeightKg != null) 'goalWeightKg': _about.goalWeightKg,
            if (_about.activityLevel != null)
              'activityLevel': _about.activityLevel,
          },
        2 => {
            if (_level.fitnessLevel != null) 'fitnessLevel': _level.fitnessLevel,
            if (_level.trainingLocation != null)
              'trainingLocation': _level.trainingLocation,
          },
        _ => const {},
      };

  /// Writes whatever the current step collected. Equipment is a separate
  /// endpoint from the profile patch, so step 3 makes two calls.
  Future<void> _saveCurrentStep() async {
    final notifier = ref.read(profileProvider.notifier);

    final fields = _patchForCurrentStep();
    if (fields.isNotEmpty) await notifier.patch(fields);

    if (_index == 2) {
      // Sent unconditionally, and only on Continue. It is a replace-set, so
      // an empty list is a real answer — "I own none of these" — and skipping
      // the call when the list is empty would make that unsavable.
      await notifier.setEquipment(_level.equipmentIds);
    }
  }

  Future<void> _continue() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _saveCurrentStep();
    } on ApiException catch (error) {
      if (!mounted) return;
      // Staying put is deliberate: advancing past a step whose answer the
      // server rejected would lose the answer with no way back to it.
      setState(() {
        _error = error.message;
        _busy = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    _advance();
  }

  void _advance() => setState(() {
        _error = null;
        if (_index < _total - 1) _index++;
      });

  void _back() => setState(() {
        _error = null;
        if (_index > 0) _index--;
      });

  Widget _stepContent() => switch (_index) {
        0 => GoalStep(
            value: _mainGoal,
            onChanged: (value) => setState(() => _mainGoal = value),
          ),
        1 => AboutStep(
            value: _about,
            onChanged: (value) => _about = value,
          ),
        2 => LevelStep(
            value: _level,
            onChanged: (value) => setState(() => _level = value),
          ),
        // Step 4 lands in Task 8 of this plan. Replace this case with
        // InjuriesStep when it arrives.
        _ => const _PendingStep(),
      };

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);

    return profile.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(
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
      ),
      data: (loaded) {
        _seedFrom(loaded);
        return OnboardingScaffold(
          step: _index + 1,
          total: _total,
          busy: _busy,
          onContinue: _continue,
          onSkip: _busy ? null : _advance,
          onBack: _index == 0 ? null : _back,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepContent(),
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
      },
    );
  }
}

class _PendingStep extends StatelessWidget {
  const _PendingStep();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('This step is not built yet.', textAlign: TextAlign.center),
      );
}
