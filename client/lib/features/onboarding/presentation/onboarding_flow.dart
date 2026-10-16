import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../health/domain/health_answers.dart';
import '../../health/presentation/providers.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/providers.dart';
import '../../reminders/data/reminder_prompt_store.dart';
import '../../reminders/data/reminder_scheduler.dart';
import 'generating_view.dart';
import 'onboarding_scaffold.dart';
import 'steps/about_step.dart';
import 'steps/goal_step.dart';
import 'steps/health_step.dart';
import 'steps/injuries_step.dart';
import 'steps/level_step.dart';
import 'steps/reminders_step.dart';

/// Sequences the six onboarding steps.
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
  static const _total = 6;

  /// The health check: no Skip, and Continue only once it is answered.
  static const _healthIndex = 4;

  int _index = 0;
  bool _busy = false;
  String? _error;
  bool _seeded = false;

  /// Whether the last attempt at building the plan failed. Turns the last
  /// step's Continue into "Try again": the reminder question was answered on
  /// the way in, so the build is the only thing left to repeat.
  bool _buildFailed = false;

  /// Whether the profile and injury writes have landed. Drives the first tick
  /// on the generating screen, which is why it is a separate flag from [_busy]
  /// — that one flips before anything has been written.
  bool _saved = false;
  bool _planReady = false;
  DateTime? _generatingSince;

  // The working answers. Seeded once from the loaded profile so a returning
  // user sees what they already chose.
  GoalAnswers _goals = const GoalAnswers();
  AboutAnswers _about = const AboutAnswers();
  LevelAnswers _level = const LevelAnswers();
  List<SelectedInjury> _injuries = const [];
  HealthAnswers _health = const HealthAnswers();

  void _seedFrom(Profile profile) {
    if (_seeded) return;
    _seeded = true;
    _goals = GoalAnswers.fromProfile(profile);
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
      equipmentIds: profile.equipment
          .map((e) => e.equipmentId)
          .toList(growable: false),
    );
    _injuries = profile.injuries;
  }

  /// Only the keys the user actually answered. The server reads an absent key
  /// as "leave alone" and an explicit null as "clear", so sending the whole
  /// object would wipe fields this step never asked about.
  Map<String, dynamic> _patchForCurrentStep() => switch (_index) {
    0 => const {},
    1 => {
      if (_about.sex != null) 'sex': _about.sex,
      if (_about.dateOfBirth != null) 'dateOfBirth': _about.dateOfBirth,
      if (_about.heightCm != null) 'heightCm': _about.heightCm,
      if (_about.weightKg != null) 'weightKg': _about.weightKg,
      if (_about.goalWeightKg != null) 'goalWeightKg': _about.goalWeightKg,
      if (_about.activityLevel != null) 'activityLevel': _about.activityLevel,
    },
    2 => {
      if (_level.fitnessLevel != null) 'fitnessLevel': _level.fitnessLevel,
      if (_level.trainingLocation != null)
        'trainingLocation': _level.trainingLocation,
    },
    _ => const {},
  };

  /// Skip's save: the answers already given on this step, and nothing else.
  ///
  /// Skip used to advance without saving, which threw away whatever had been
  /// typed before the user decided to move on. This sends the same patch as
  /// Continue -- [_patchForCurrentStep] already leaves out fields that are
  /// empty or did not parse -- plus the step's own lists when anything is
  /// picked in them. An empty list stays unsent here, unlike on Continue:
  /// skipping is not an answer of "none".
  Future<void> _saveTypedAnswers() async {
    final notifier = ref.read(profileProvider.notifier);

    // The server takes height and the two weights only as 0 < n < 1000, and
    // FsStatField's formatter already stops anything from 1000 up. A typed 0
    // is the one value left that it would reject, and a rejection would keep
    // Skip on the step, so it is dropped like any other unusable answer.
    final fields = {..._patchForCurrentStep()}
      ..removeWhere((_, value) => value is num && value <= 0);
    if (fields.isNotEmpty) await notifier.patch(fields);

    if (_index == 0 && _goals.goals.isNotEmpty) {
      await notifier.setGoals(_goals.goals, _goals.mainGoal!);
    }
    if (_index == 2 && _level.equipmentIds.isNotEmpty) {
      await notifier.setEquipment(_level.equipmentIds);
    }
    if (_index == 3 && _injuries.isNotEmpty) {
      await notifier.setInjuries(_injuries);
    }
  }

  /// Writes whatever the current step collected. Equipment is a separate
  /// endpoint from the profile patch, so step 3 makes two calls.
  Future<void> _saveCurrentStep() async {
    final notifier = ref.read(profileProvider.notifier);

    // Unlike Skip, a typed 0 is sent as it is. Continue is an explicit
    // answer, so the server's rejection is shown in plain words and the user
    // stays on the step to correct it, instead of the 0 being dropped while
    // the field still shows it.
    final fields = _patchForCurrentStep();
    if (fields.isNotEmpty) await notifier.patch(fields);

    // Goals replace the whole set on their own endpoint. Nothing ticked is
    // "not answered yet", not "no goals", so it writes nothing.
    if (_index == 0 && _goals.goals.isNotEmpty) {
      await notifier.setGoals(_goals.goals, _goals.mainGoal!);
    }

    // Both of these are replace-set writes on their own endpoints, sent
    // unconditionally and only on Continue. An empty list is a real answer —
    // "I own none of these", "nothing hurts" — and skipping the call when the
    // list is empty would make that unsavable.
    if (_index == 2) await notifier.setEquipment(_level.equipmentIds);
    if (_index == 3) await notifier.setInjuries(_injuries);

    // "Don't save my answers" means nothing stored, whether or not the
    // answers are positive -- including a row an earlier, non-opted-out save
    // on this same visit already put on the server. DELETE is idempotent
    // server-side (200 with no row), so it is safe to call even when nothing
    // was ever saved. Otherwise the current answers are saved as usual.
    // Either way, invalidate the cached answers so Settings reads what is
    // stored now.
    if (_index == _healthIndex) {
      if (_health.optedOut) {
        await ref.read(healthRepositoryProvider).deleteHealth();
      } else {
        await ref.read(healthRepositoryProvider).setHealth(_health);
      }
      ref.invalidate(healthProvider);
    }

    if (_index == _total - 1) {
      // Whatever is selected on the injuries step is saved here too, not
      // only when that step's own Continue already ran setInjuries: Skip on
      // that step advances without saving anything, so this is the only
      // write a pick made there and then skipped past would ever get. The
      // generating screen's "Avoiding …" line already reads from local
      // state regardless, so this only affects what reaches the server.
      await notifier.setInjuries(_injuries);
      // Everything the user answered is now on the server, which is what the
      // generating screen's first row claims — so it may only tick here.
      if (mounted) setState(() => _saved = true);
      // Either button on this step counts as answering the Home prompt.
      // Fired and forgotten, not awaited: a slow or failing secure-storage
      // write must never hold up -- or altogether block -- the plan the user
      // is actually here for. A write that never lands just means the Home
      // prompt asks again next time, which is a far smaller cost than a
      // stuck "Building your plan…" screen with no error and no retry.
      unawaited(
        ref.read(reminderPromptStoreProvider).markAnswered().catchError((
          Object error,
        ) {
          debugPrint('Reminder prompt flag not saved: $error');
        }),
      );
      // Generating the plan is the last thing that happens, and the server
      // leaves onboarding incomplete if it fails — so a failure here lands in
      // _save's catch, the user stays on this step, and Try again is a
      // genuine retry rather than a resubmission.
      await notifier.completeOnboarding();
      // The last row describes this call; it may tick now, and the hold below
      // is what gives the user time to see it do so.
      if (mounted) setState(() => _planReady = true);
      // Held before the hand-off, not after: the hand-off swaps this screen
      // out, so a wait on the far side of it would not be seen.
      await _holdGenerating();
      if (mounted) {
        ref.read(authControllerProvider.notifier).onOnboardingCompleted();
      }
    }
  }

  /// Holds the generating screen until its last row has ticked and been seen.
  ///
  /// The arithmetic lives on [GeneratingPace] because the generator screen
  /// holds its own reveal the same way, at its own pace.
  ///
  /// Only the success path waits. Holding an error back would delay the one
  /// thing the user actually needs to see.
  Future<void> _holdGenerating() async {
    final since = _generatingSince;
    if (since == null) return;

    await GeneratingPace.onboarding.hold(since);
  }

  /// The reported injuries, by name. [SelectedInjury] carries only an id, so
  /// the names come from the same options list the step rendered; an injury
  /// whose option is missing is dropped rather than shown as a number.
  List<String> _avoidingNames() {
    final options = ref.read(injuryOptionsProvider).value;
    if (options == null) return const [];
    final byId = {for (final o in options) o.injuryId: o.name};
    return [
      for (final injury in _injuries)
        if (byId[injury.injuryId] != null) byId[injury.injuryId]!,
    ];
  }

  Future<void> _continue() => _save(_saveCurrentStep);

  Future<void> _skip() => _save(_saveTypedAnswers);

  /// Runs one of the two saves, then moves on -- or, if it failed, stays put
  /// and says why.
  Future<void> _save(Future<void> Function() write) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
      _planReady = false;
    });
    _generatingSince = DateTime.now();

    try {
      await write();
    } catch (error) {
      if (!mounted) return;
      // Staying put is deliberate: advancing past a step whose answer the
      // server rejected would lose the answer with no way back to it. Any
      // failure is caught, not only the API's own, because one that escaped
      // would leave the flow busy -- on the last step, a "Building your
      // plan…" screen with no way off it.
      final message = _plainError(error);
      setState(() {
        _error = message;
        _busy = false;
        if (_index == _total - 1) _buildFailed = true;
      });
      // The message appears by the buttons, but someone not looking there,
      // or not looking at all, needs to hear that the tap did not work.
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    _advance();
  }

  /// A failure in words a user can act on. The client's own messages are
  /// written for whoever is running the server -- an address, an adb command
  /// -- so those are replaced. So are the server's rejections of a profile
  /// answer, which name the API field ("goalWeightKg must be ...") rather
  /// than anything on screen. Its other messages are already plain and kept.
  static String _plainError(Object error) => switch (error) {
    ApiException(code: 'NETWORK_ERROR') =>
      "Couldn't reach FitSync. Check your connection and try again.",
    ApiException(code: 'INVALID_PROFILE_FIELD') =>
      "One of these answers can't be saved as it is. Check it and try again.",
    ApiException(code: 'INVALID_RESPONSE' || 'UNKNOWN_ERROR') =>
      'Something went wrong on our side. Please try again.',
    ApiException() => describeError(error),
    _ => 'Something went wrong. Please try again.',
  };

  /// The last step's Continue: unlike every earlier step, this one has
  /// something to do before `_continue()` -- show the system permission
  /// prompt. `_continue()` still runs afterwards either way, since declining
  /// is not the same as Not now; only the button pressed decides that.
  Future<void> _turnOnReminders() async {
    await ref.read(reminderSchedulerProvider).requestPermission();
    // The system prompt this just awaited can outlive the flow -- the app
    // backgrounding, or the shell tearing this screen down -- so nothing
    // below may touch ref once it is gone.
    if (!mounted) return;
    await _continue();
  }

  void _advance() => setState(() {
    _error = null;
    if (_index < _total - 1) _index++;
  });

  void _back() => setState(() {
    _error = null;
    _buildFailed = false;
    if (_index > 0) _index--;
  });

  Widget _stepContent() => switch (_index) {
    0 => GoalStep(
      value: _goals,
      onChanged: (value) => setState(() => _goals = value),
    ),
    1 => AboutStep(
      value: _about,
      onChanged: (value) => _about = value,
      // Saved to the account as it is tapped rather than held with the
      // rest of the step: it changes what the two cards on screen say
      // right now, so it cannot wait for Continue.
      unit: ref.watch(weightUnitProvider),
      onUnitChanged: (unit) =>
          ref.read(profileProvider.notifier).patch({'weightUnit': unit.api}),
    ),
    2 => LevelStep(
      value: _level,
      onChanged: (value) => setState(() => _level = value),
    ),
    3 => InjuriesStep(
      value: _injuries,
      onChanged: (value) => setState(() => _injuries = value),
    ),
    _healthIndex => HealthStep(
      value: _health,
      onChanged: (value) => setState(() => _health = value),
    ),
    _ => const RemindersStep(),
  };

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);

    return profile.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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

        // The plan build takes over the whole screen: the wizard chrome would
        // offer a Back and a Skip that cannot be honoured mid-write.
        if (_busy && _index == _total - 1) {
          return GeneratingView(
            title: 'Building your plan…',
            subtitle:
                'Matching exercises to your goals, equipment, '
                'and injury history.',
            leadLabel: 'Profile saved',
            leadDone: _saved,
            avoiding: _avoidingNames(),
            planReady: _planReady,
          );
        }

        final onLastStep = _index == _total - 1;
        final onHealthStep = _index == _healthIndex;
        final retrying = onLastStep && _buildFailed;

        // Android's back goes where the header's back goes. Only the first
        // step lets it through to the system, as it always has; anywhere
        // later it used to leave the app, and coming back began at step 1.
        return PopScope<Object?>(
          key: const Key('onboarding.pop'),
          canPop: _index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || _busy) return;
            _back();
          },
          child: OnboardingScaffold(
            step: _index + 1,
            total: _total,
            busy: _busy,
            continueLabel: retrying
                ? 'Try again'
                : (onLastStep ? 'Turn on reminders' : 'Continue'),
            // The health step has no Skip, so Continue waits for a valid answer.
            onContinue: onHealthStep && !_health.isValid
                ? null
                : (onLastStep && !retrying ? _turnOnReminders : _continue),
            // The last step has no header Skip -- "Not now" is its own button
            // under Continue instead (see secondaryLabel below). The health
            // step also has no Skip: there is no innocuous answer to advance
            // past without one. Every earlier step keeps the header Skip,
            // which keeps what was typed and moves on.
            onSkip: onLastStep || onHealthStep ? null : (_busy ? null : _skip),
            // Not now still saves and builds the plan -- it only skips asking
            // for permission first -- so it routes through _continue rather
            // than the lighter save every earlier step's Skip uses. Once a
            // build has failed the question is answered, and Try again is the
            // only button left.
            secondaryLabel: onLastStep && !retrying ? 'Not now' : null,
            onSecondary: onLastStep && !retrying
                ? (_busy ? null : _continue)
                : null,
            onBack: _index == 0 ? null : _back,
            error: _error,
            // The only way out of step 1 short of finishing: someone signed in
            // with the wrong account should not have to onboard it first.
            onSignOut: _index == 0
                ? () => ref.read(authControllerProvider.notifier).signOut()
                : null,
            child: _stepContent(),
          ),
        );
      },
    );
  }
}
