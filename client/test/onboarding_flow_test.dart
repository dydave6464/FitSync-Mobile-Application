import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart' show InMemorySecureStore;
import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/health/domain/health_answers.dart';
import 'package:fitsync/features/health/presentation/providers.dart';
import 'package:fitsync/features/home/presentation/plan_ready.dart';
import 'package:fitsync/features/onboarding/domain/daily_targets.dart';
import 'package:fitsync/features/onboarding/presentation/generating_view.dart';
import 'package:fitsync/features/onboarding/presentation/onboarding_flow.dart';
import 'package:fitsync/features/onboarding/presentation/onboarding_scaffold.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/reminders/data/reminder_prompt_store.dart';
import 'package:fitsync/features/reminders/data/reminder_repository.dart';
import 'package:fitsync/features/reminders/data/reminder_scheduler.dart';
import 'package:fitsync/features/reminders/domain/reminders.dart'
    show PlannedReminder, ReminderSettings;
import 'package:fitsync/features/reminders/presentation/providers.dart'
    show reminderRepositoryProvider;

import 'helpers/fake_health.dart';

Profile _emptyProfile() => const Profile(
  userId: 7,
  email: 'juan@example.com',
  fullName: 'Juan Dela Cruz',
  onboardingCompleted: false,
  isPremium: false,
  notificationsEnabled: true,
  equipment: [],
  injuries: [],
);

// The curated list the server now returns, in display order.
const _equipment = [
  EquipmentOption(equipmentId: 1, name: 'Barbell', key: 'barbell'),
  EquipmentOption(equipmentId: 2, name: 'Dumbbells', key: 'dumbbell'),
  EquipmentOption(equipmentId: 3, name: 'Bench', key: 'bench'),
  EquipmentOption(equipmentId: 4, name: 'Pull-up bar', key: 'pull-up bar'),
  EquipmentOption(equipmentId: 5, name: 'Kettlebell', key: 'kettlebell'),
  EquipmentOption(equipmentId: 6, name: 'Bands', key: 'band'),
  EquipmentOption(equipmentId: 7, name: 'Machines', key: 'machines'),
  EquipmentOption(equipmentId: 8, name: 'Bodyweight', key: 'body weight'),
];
const _injuries = [
  InjuryOption(
    injuryId: 1,
    name: 'Shoulder',
    isLateral: true,
    regionGroup: 'upper_body',
  ),
];

class FakeProfileNotifier extends ProfileNotifier {
  FakeProfileNotifier(
    this.patches, {
    this.onPatch,
    this.equipmentWrites,
    this.injuryWrites,
    this.completions,
    this.onComplete,
    this.goalWrites,
    this.onSetGoals,
    this.seedGoals = const [],
    this.seedMainGoal,
  });

  final List<Map<String, dynamic>> patches;
  final Future<void> Function()? onPatch;
  final List<List<int>>? equipmentWrites;
  final List<List<SelectedInjury>>? injuryWrites;
  final List<int>? completions;
  final List<({List<String> goals, String mainGoal})>? goalWrites;

  /// Lets a test fail the goals write the way [onPatch] fails a patch.
  final Future<void> Function()? onSetGoals;

  /// Called before each completion resolves, so a test can fail the first
  /// attempt and succeed on the retry.
  final Future<void> Function(int attempt)? onComplete;

  /// Seeds the loaded profile's goals and main focus, the way a returning
  /// user's saved answers would -- without this, a test can never see
  /// `_seedFrom` work from anything but an empty profile.
  final List<String> seedGoals;
  final String? seedMainGoal;

  @override
  Future<Profile> build() async => Profile(
    userId: 7,
    email: 'juan@example.com',
    fullName: 'Juan Dela Cruz',
    onboardingCompleted: false,
    isPremium: false,
    notificationsEnabled: true,
    equipment: const [],
    injuries: const [],
    goals: seedGoals,
    mainGoal: seedMainGoal,
  );

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
    patches.add(fields);
    if (onPatch != null) await onPatch!();
    // The unit is a display preference the step reads back at once, as the
    // real notifier's refreshed profile would give it.
    if (fields['weightUnit'] case final String unit) {
      final loaded = state.value!;
      state = AsyncData(
        Profile(
          userId: loaded.userId,
          email: loaded.email,
          fullName: loaded.fullName,
          onboardingCompleted: loaded.onboardingCompleted,
          isPremium: loaded.isPremium,
          notificationsEnabled: loaded.notificationsEnabled,
          equipment: loaded.equipment,
          injuries: loaded.injuries,
          goals: loaded.goals,
          mainGoal: loaded.mainGoal,
          weightUnit: WeightUnit.fromApi(unit),
        ),
      );
    }
  }

  @override
  Future<void> setEquipment(List<int> equipmentIds) async {
    equipmentWrites?.add(equipmentIds);
  }

  @override
  Future<void> setInjuries(List<SelectedInjury> injuries) async {
    injuryWrites?.add(injuries);
  }

  @override
  Future<void> setGoals(List<String> goals, String mainGoal) async {
    goalWrites?.add((goals: goals, mainGoal: mainGoal));
    if (onSetGoals != null) await onSetGoals!();
  }

  @override
  Future<CompletedOnboarding> completeOnboarding() async {
    final attempt = completions?.length ?? 0;
    completions?.add(attempt);
    if (onComplete != null) await onComplete!(attempt);
    return (profile: _emptyProfile(), plan: const {'planId': 42});
  }
}

/// A profile that cannot load until [fail] is cleared, counting attempts.
class _FailingProfileNotifier extends FakeProfileNotifier {
  _FailingProfileNotifier(this.attempts) : super([]);

  final List<int> attempts;
  static bool fail = true;

  @override
  Future<Profile> build() async {
    attempts.add(attempts.length);
    if (fail) {
      throw const ApiException(
        'NETWORK_ERROR',
        'Could not reach http://10.0.2.2:3000. Check the server is running.',
      );
    }
    return super.build();
  }
}

/// Records the shell hand-off so a test can prove onboarding actually ends.
class RecordingAuthController extends AuthController {
  RecordingAuthController(this.completed);

  final List<bool> completed;

  @override
  Future<AuthState> build() async => AuthState(
    AuthStatus.onboarding,
    const AuthUser(
      userId: 7,
      email: 'juan@example.com',
      fullName: 'Juan Dela Cruz',
      onboardingCompleted: false,
      isPremium: false,
    ),
  );

  @override
  void onOnboardingCompleted() {
    completed.add(true);
    super.onOnboardingCompleted();
  }

  /// Counted rather than run: the real sign-out reaches the token store and
  /// the notification plugin, neither of which a widget test has.
  int signOuts = 0;

  @override
  Future<void> signOut() async {
    signOuts += 1;
  }
}

/// Records `requestPermission` calls for the reminders step's tests.
/// `permissionGranted` is never watched by this flow, so it does not need to
/// answer anything in particular.
class _FakeScheduler implements ReminderScheduler {
  int requestPermissionCalls = 0;

  @override
  Future<bool> permissionGranted() async => false;

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls += 1;
    return true;
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> scheduleAll(List<PlannedReminder> reminders) async {}

  @override
  Stream<String> get taps => const Stream.empty();
}

/// Records the reminder choices onboarding saves. [onPatch] runs inside each
/// patch -- a test passes one that throws, never finishes, or notes how many
/// permission prompts came first.
class _FakeReminderRepository implements ReminderRepository {
  _FakeReminderRepository({this.onPatch});

  final Future<void> Function()? onPatch;
  final patches = <Map<String, dynamic>>[];

  @override
  Future<ReminderSettings> patch(Map<String, dynamic> fields) async {
    patches.add(fields);
    await onPatch?.call();
    return ReminderSettings.defaults;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// `markAnswered` fails every time -- a secure-storage write that genuinely
/// cannot land, e.g. a locked keychain. `answered()` is left to the real
/// in-memory backing, unused by these tests but harmless either way.
class _ThrowingReminderPromptStore extends ReminderPromptStore {
  _ThrowingReminderPromptStore() : super(backing: InMemorySecureStore());

  @override
  Future<void> markAnswered() =>
      Future<void>.error(PlatformException(code: 'unavailable'));
}

/// `markAnswered` never completes -- the write is sent but the platform
/// never answers. Onboarding must not sit around waiting for it either.
class _HangingReminderPromptStore extends ReminderPromptStore {
  _HangingReminderPromptStore() : super(backing: InMemorySecureStore());

  @override
  Future<void> markAnswered() => Completer<void>().future;
}

/// Both lookup providers are always stubbed, even for tests that never reach
/// steps 3 and 4. Leaving one live means the first `pumpAndSettle` after
/// arriving at that step waits forever on its loading spinner.
///
/// `reminderPromptStoreProvider` is stubbed with an in-memory backing for the
/// same reason -- unlike `reminderSchedulerProvider`, whose provider default
/// is already a safe no-op, this one's default reaches the real secure
/// storage plugin, which never answers in a widget test. [store] defaults to
/// a fresh in-memory one, but a caller can pass its own -- and keep the
/// reference -- to prove `markAnswered()` actually lands, or to pass a fake
/// that throws or hangs without ever reaching real storage.
Future<void> _pumpFlow(
  WidgetTester tester, {
  required List<Map<String, dynamic>> patches,
  Future<void> Function()? onPatch,
  List<List<int>>? equipmentWrites,
  List<List<SelectedInjury>>? injuryWrites,
  List<int>? completions,
  Future<void> Function(int attempt)? onComplete,
  List<bool>? completed,
  ReminderScheduler? scheduler,
  ReminderPromptStore? store,
  List<({List<String> goals, String mainGoal})>? goalWrites,
  Future<void> Function()? onSetGoals,
  List<String> seedGoals = const [],
  String? seedMainGoal,
  FakeHealthRepository? health,
  RecordingAuthController? auth,
  ReminderRepository? reminders,
  ProfileNotifier Function()? profile,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith(
          profile ??
              () => FakeProfileNotifier(
                patches,
                onPatch: onPatch,
                equipmentWrites: equipmentWrites,
                injuryWrites: injuryWrites,
                completions: completions,
                onComplete: onComplete,
                goalWrites: goalWrites,
                onSetGoals: onSetGoals,
                seedGoals: seedGoals,
                seedMainGoal: seedMainGoal,
              ),
        ),
        authControllerProvider.overrideWith(
          () => auth ?? RecordingAuthController(completed ?? []),
        ),
        equipmentOptionsProvider.overrideWith((ref) async => _equipment),
        injuryOptionsProvider.overrideWith((ref) async => _injuries),
        healthRepositoryProvider.overrideWithValue(
          health ?? FakeHealthRepository(),
        ),
        if (scheduler != null)
          reminderSchedulerProvider.overrideWithValue(scheduler),
        reminderPromptStoreProvider.overrideWithValue(
          store ?? ReminderPromptStore(backing: InMemorySecureStore()),
        ),
        reminderRepositoryProvider.overrideWithValue(
          reminders ?? _FakeReminderRepository(),
        ),
      ],
      child: const MaterialApp(home: OnboardingFlow()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

/// What the flow says when the server rejects one of the step's answers.
const _rejectedAnswer =
    "One of these answers can't be saved as it is. Check it and try again.";

Future<void> _skip(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('skip')));
  await tester.pumpAndSettle();
}

/// Answers the health step with nothing to report and continues. The health
/// step has no Skip, so every test that reaches the reminders step passes
/// through here.
Future<void> _passHealthClear(WidgetTester tester) async {
  await _tapKey(tester, const Key('health.none'));
  for (final q in healthQuestions) {
    await _tapKey(tester, Key('health.${q.field}.no'));
  }
  await _tapKey(tester, const Key('continue'));
}

/// Skips the four skippable steps and answers the health step: the
/// reminders step is on screen afterwards.
Future<void> _toRemindersStep(WidgetTester tester) async {
  await _skip(tester);
  await _skip(tester);
  await _skip(tester);
  await _skip(tester);
  await _passHealthClear(tester);
}

void main() {
  testWidgets('starts on step 1 of 6', (tester) async {
    await _pumpFlow(tester, patches: []);

    expect(find.text('STEP 1 / 6'), findsOneWidget);
    expect(find.byKey(const Key('goal.lose_weight')), findsOneWidget);
  });

  // Step 2 asks for goal weight outright only when step 1's goals include
  // losing weight; building muscle gets it as an optional button.
  for (final (goals, asked) in [
    (['build_muscle'], false),
    (['build_muscle', 'lose_weight'], true),
  ]) {
    testWidgets(
      'step 2 ${asked ? 'asks' : 'offers'} goal weight after ${goals.join(' + ')}',
      (tester) async {
        await _pumpFlow(tester, patches: [], goalWrites: []);

        for (final goal in goals) {
          await tester.tap(find.byKey(Key('goal.$goal')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('continue')));
        await tester.pumpAndSettle();

        expect(find.text('STEP 2 / 6'), findsOneWidget);
        expect(
          find.byKey(const Key('goalWeightKg')),
          asked ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('goalWeight.add')),
          asked ? findsNothing : findsOneWidget,
        );
      },
    );
  }

  // Going back to step 1 rebuilds step 2 from the goals as they are now, and
  // a goal weight already typed is never hidden behind the button.
  testWidgets(
    'a typed goal weight stays in view after losing weight is untaken',
    (tester) async {
      await _pumpFlow(tester, patches: [], goalWrites: []);
      await tester.tap(find.byKey(const Key('goal.lose_weight')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('goalWeightKg')),
          matching: find.byType(EditableText),
        ),
        '64',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('goal.lose_weight')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('goal.build_muscle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('goalWeight.add')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('goalWeightKg')),
          matching: find.text('64'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'adding losing weight on the way back asks goal weight outright',
    (tester) async {
      await _pumpFlow(tester, patches: [], goalWrites: []);
      await tester.tap(find.byKey(const Key('goal.build_muscle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('goalWeight.add')), findsOneWidget);

      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('goal.lose_weight')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('goalWeightKg')), findsOneWidget);
      expect(find.byKey(const Key('goalWeight.add')), findsNothing);
    },
  );

  testWidgets('Continue saves the goals and advances', (tester) async {
    final patches = <Map<String, dynamic>>[];
    final goalWrites = <({List<String> goals, String mainGoal})>[];
    await _pumpFlow(tester, patches: patches, goalWrites: goalWrites);

    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal.lose_weight')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(goalWrites.single.goals, ['build_muscle', 'lose_weight']);
    expect(goalWrites.single.mainGoal, 'build_muscle');
    expect(patches, isEmpty, reason: 'goals have their own endpoint now');
    expect(find.text('STEP 2 / 6'), findsOneWidget);
  });

  testWidgets('Skip with nothing typed advances without saving', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpFlow(tester, patches: patches);

    await _skip(tester);

    expect(patches, isEmpty);
    expect(find.text('STEP 2 / 6'), findsOneWidget);
  });

  testWidgets('Continue with nothing chosen saves nothing but still advances', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpFlow(tester, patches: patches);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(
      patches,
      isEmpty,
      reason: 'an empty patch is a pointless round trip',
    );
    expect(find.text('STEP 2 / 6'), findsOneWidget);
  });

  testWidgets('Continue on step 1 with nothing ticked writes no goals', (
    tester,
  ) async {
    final goalWrites = <({List<String> goals, String mainGoal})>[];
    await _pumpFlow(tester, patches: [], goalWrites: goalWrites);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(
      goalWrites,
      isEmpty,
      reason: 'nothing ticked is "not answered yet", not "no goals"',
    );
    expect(find.text('STEP 2 / 6'), findsOneWidget);
  });

  testWidgets('a failed save shows the message and stays on the step', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      patches: [],
      onSetGoals: () async => throw const ApiException(
        'INVALID_PROFILE_FIELD',
        'That goal is not one we recognise.',
      ),
    );

    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    // The server's own wording names API fields, so a rejected answer is
    // always shown in the flow's plain sentence instead.
    expect(find.text(_rejectedAnswer), findsOneWidget);
    expect(
      find.text('STEP 1 / 6'),
      findsOneWidget,
      reason: 'advancing past a step whose answer was rejected would lose it',
    );
  });

  testWidgets(
    'a profile seeded with goals but no focus does not crash Continue',
    (tester) async {
      final goalWrites = <({List<String> goals, String mainGoal})>[];
      await _pumpFlow(
        tester,
        patches: [],
        goalWrites: goalWrites,
        seedGoals: const ['lose_weight', 'build_muscle'],
      );

      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // build_muscle comes before lose_weight in card order, so a null
      // focus falls back to it.
      expect(goalWrites.single.goals, ['build_muscle', 'lose_weight']);
      expect(goalWrites.single.mainGoal, 'build_muscle');
      expect(find.text('STEP 2 / 6'), findsOneWidget);
    },
  );

  testWidgets('step 3 saves the level fields and the equipment set', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    final equipmentWrites = <List<int>>[];
    await _pumpFlow(tester, patches: patches, equipmentWrites: equipmentWrites);

    await _skip(tester);
    await _skip(tester);
    expect(find.text('STEP 3 / 6'), findsOneWidget);

    await _tapKey(tester, const Key('segment.beginner'));
    await _tapKey(tester, const Key('equipment.3'));
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(patches.single, {'fitnessLevel': 'beginner'});
    expect(equipmentWrites.single, [
      3,
    ], reason: 'equipment is a replace-set write, not part of the patch');
    expect(find.text('STEP 4 / 6'), findsOneWidget);
  });

  testWidgets('step 3 saves New to training and the home gym pre-fill', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    final equipmentWrites = <List<int>>[];
    await _pumpFlow(tester, patches: patches, equipmentWrites: equipmentWrites);
    await _skip(tester);
    await _skip(tester);

    await _tapKey(tester, const Key('segment.new'));
    await _tapKey(tester, const Key('trainingLocation'));
    await tester.tap(find.byKey(const Key('location.home_gym')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(patches.single, {
      'fitnessLevel': 'new',
      'trainingLocation': 'home_gym',
    });
    expect(equipmentWrites.single.toSet(), {2, 6});
  });

  testWidgets('step 3 shows the eight chips the design specifies, in order', (
    tester,
  ) async {
    await _pumpFlow(tester, patches: []);
    await _skip(tester);
    await _skip(tester);
    expect(find.text('STEP 3 / 6'), findsOneWidget);

    // Read the rendered chips back in tree order, not just check presence —
    // display order is the point of the curated list, and `find.text` alone
    // cannot see it. The key filter excludes the location chips, which are
    // FsChips too but keyed 'location.*'.
    final labels = tester
        .widgetList<FsChip>(find.byType(FsChip))
        .where(
          (chip) =>
              (chip.key as ValueKey<String>).value.startsWith('equipment.'),
        )
        .map((chip) => chip.label)
        .toList();

    expect(labels, [
      'Barbell',
      'Dumbbells',
      'Bench',
      'Pull-up bar',
      'Kettlebell',
      'Bands',
      'Machines',
      'Bodyweight',
    ]);
  });

  testWidgets('a selected equipment chip renders a check', (tester) async {
    await _pumpFlow(tester, patches: []);
    await _skip(tester);
    await _skip(tester);
    expect(find.text('STEP 3 / 6'), findsOneWidget);

    // Scope the icon search to this one chip's subtree. A bare
    // find.byIcon(Icons.check) would also match FsRadioDot on the fitness
    // level cards above (which always renders a check when selected,
    // showCheck or not), so the finder has to discriminate by location, not
    // just by icon.
    final chip = find.byKey(const Key('equipment.3'));
    expect(
      find.descendant(of: chip, matching: find.byIcon(Icons.check)),
      findsNothing,
      reason: 'unselected chip must not show a check',
    );

    await _tapKey(tester, const Key('equipment.3'));

    expect(
      find.descendant(of: chip, matching: find.byIcon(Icons.check)),
      findsOneWidget,
      reason:
          'showCheck must actually be wired to the equipment chips, '
          'not just supported by FsChip',
    );
  });

  testWidgets('the counter tracks the equipment selection', (tester) async {
    await _pumpFlow(tester, patches: []);
    await _skip(tester);
    await _skip(tester);
    expect(find.text('STEP 3 / 6'), findsOneWidget);

    expect(find.text('0 selected'), findsOneWidget);
    await _tapKey(tester, const Key('equipment.3'));
    await _tapKey(tester, const Key('equipment.5'));
    expect(find.text('2 selected'), findsOneWidget);
    await _tapKey(tester, const Key('equipment.3'));
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('step 4 saves the injury set, empty included', (tester) async {
    final injuryWrites = <List<SelectedInjury>>[];
    await _pumpFlow(tester, patches: [], injuryWrites: injuryWrites);

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    expect(find.text('STEP 4 / 6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    // "Nothing hurts" is the common answer and has to be savable.
    expect(injuryWrites.single, isEmpty);
    expect(
      find.text('STEP 5 / 6'),
      findsOneWidget,
      reason:
          'Continue on the injuries step only saves and advances -- the '
          'health check comes next',
    );
  });

  testWidgets('the health step comes after injuries and has no Skip', (
    tester,
  ) async {
    await _pumpFlow(tester, patches: []);

    for (var i = 0; i < 4; i++) {
      await _skip(tester);
    }

    expect(find.text('STEP 5 / 6'), findsOneWidget);
    expect(find.text('Your health'), findsOneWidget);
    expect(find.byKey(const Key('skip')), findsNothing);
  });

  testWidgets('the health step says why Continue is greyed, right above it', (
    tester,
  ) async {
    await _pumpFlow(tester, patches: []);
    for (var i = 0; i < 4; i++) {
      await _skip(tester);
    }

    final hint = find.byKey(const Key('hint'));
    expect(
      tester.widget<ContinueHint>(hint).message,
      'Answer every question to continue',
    );
    final cont = tester.getRect(find.byKey(const Key('continue')));
    expect(cont.top - tester.getRect(hint).bottom, inInclusiveRange(0, 24));

    await _tapKey(tester, const Key('health.asthma'));
    for (final q in healthQuestions) {
      await _tapKey(tester, Key('health.${q.field}.no'));
    }
    expect(
      tester.widget<ContinueHint>(hint).message,
      'Tick both boxes to continue',
    );

    await _tapKey(tester, const Key('health.optOut'));
    expect(hint, findsNothing, reason: 'Continue can be pressed now');
  });

  testWidgets('no other step shows the health hint', (tester) async {
    await _pumpFlow(tester, patches: []);

    expect(find.byKey(const Key('hint')), findsNothing);
  });

  testWidgets('Continue does nothing until the health step is answered', (
    tester,
  ) async {
    final health = FakeHealthRepository();
    await _pumpFlow(tester, patches: [], health: health);
    for (var i = 0; i < 4; i++) {
      await _skip(tester);
    }

    await _tapKey(tester, const Key('continue'));
    expect(find.text('STEP 5 / 6'), findsOneWidget);
    expect(health.writes, isEmpty);

    await _passHealthClear(tester);

    expect(find.text('STEP 6 / 6'), findsOneWidget);
    expect(health.writes.single.toJson(), {
      'conditions': <String>[],
      'chestPain': false,
      'dizziness': false,
      'supervisedOnly': false,
      'consent': false,
      'acknowledged': false,
    });
    expect(health.deletes, 0, reason: 'a save must not also delete');
  });

  testWidgets('a positive health answer needs both boxes, then saves', (
    tester,
  ) async {
    final health = FakeHealthRepository();
    await _pumpFlow(tester, patches: [], health: health);
    for (var i = 0; i < 4; i++) {
      await _skip(tester);
    }

    await _tapKey(tester, const Key('health.asthma'));
    for (final q in healthQuestions) {
      await _tapKey(tester, Key('health.${q.field}.no'));
    }
    await _tapKey(tester, const Key('continue'));
    expect(find.text('STEP 5 / 6'), findsOneWidget, reason: 'no boxes yet');

    await _tapKey(tester, const Key('health.ack'));
    await _tapKey(tester, const Key('continue'));
    expect(find.text('STEP 5 / 6'), findsOneWidget, reason: 'no consent yet');

    await _tapKey(tester, const Key('health.consent'));
    await _tapKey(tester, const Key('continue'));

    expect(find.text('STEP 6 / 6'), findsOneWidget);
    final saved = health.writes.single;
    expect(saved.conditions, ['asthma']);
    expect(saved.consent, isTrue);
    expect(saved.acknowledged, isTrue);
    expect(health.deletes, 0, reason: 'a save must not also delete');
  });

  testWidgets("Don't save my answers continues without storing anything", (
    tester,
  ) async {
    final health = FakeHealthRepository();
    await _pumpFlow(tester, patches: [], health: health);
    for (var i = 0; i < 4; i++) {
      await _skip(tester);
    }

    await _tapKey(tester, const Key('health.none'));
    await _tapKey(tester, const Key('health.chestPain.yes'));
    await _tapKey(tester, const Key('health.dizziness.no'));
    await _tapKey(tester, const Key('health.supervisedOnly.no'));
    await _tapKey(tester, const Key('health.optOut'));
    await _tapKey(tester, const Key('continue'));

    expect(find.text('STEP 6 / 6'), findsOneWidget);
    expect(health.writes, isEmpty);
    expect(health.deletes, 1);
  });

  testWidgets('opting out deletes answers stored earlier', (tester) async {
    // Simulates a row a previous, non-opted-out save already put on the
    // server -- opting out now must remove it, not just skip writing.
    final health = FakeHealthRepository(stored: const HealthAnswers());
    await _pumpFlow(tester, patches: [], health: health);
    for (var i = 0; i < 4; i++) {
      await _skip(tester);
    }

    await _tapKey(tester, const Key('health.asthma'));
    for (final q in healthQuestions) {
      await _tapKey(tester, Key('health.${q.field}.no'));
    }
    await _tapKey(tester, const Key('health.optOut'));
    await _tapKey(tester, const Key('continue'));

    expect(find.text('STEP 6 / 6'), findsOneWidget);
    expect(health.deletes, 1);
    expect(health.writes, isEmpty);
  });

  testWidgets(
    'saving positively, then opting out after Back, deletes what was saved',
    (tester) async {
      final health = FakeHealthRepository();
      await _pumpFlow(tester, patches: [], health: health);
      for (var i = 0; i < 4; i++) {
        await _skip(tester);
      }

      await _tapKey(tester, const Key('health.asthma'));
      for (final q in healthQuestions) {
        await _tapKey(tester, Key('health.${q.field}.no'));
      }
      await _tapKey(tester, const Key('health.ack'));
      await _tapKey(tester, const Key('health.consent'));
      await _tapKey(tester, const Key('continue'));

      expect(find.text('STEP 6 / 6'), findsOneWidget);
      expect(health.writes.length, 1);

      await _tapKey(tester, const Key('back'));
      expect(find.text('STEP 5 / 6'), findsOneWidget);

      await _tapKey(tester, const Key('health.optOut'));
      await _tapKey(tester, const Key('continue'));

      expect(find.text('STEP 6 / 6'), findsOneWidget);
      expect(health.deletes, 1);
    },
  );

  testWidgets('a failed health save shows the message and stays', (
    tester,
  ) async {
    final health = FakeHealthRepository()
      ..writeError = const ApiException(
        'HEALTH_CONSENT_REQUIRED',
        'Health answers that report a condition or a warning sign are '
            'stored only with consent.',
      );
    await _pumpFlow(tester, patches: [], health: health);
    for (var i = 0; i < 4; i++) {
      await _skip(tester);
    }

    await _passHealthClear(tester);

    expect(find.text('STEP 5 / 6'), findsOneWidget);
    expect(find.byKey(const Key('error')), findsOneWidget);
  });

  testWidgets('the last step offers reminders before the plan is built', (
    tester,
  ) async {
    await _pumpFlow(tester, patches: []);

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);

    expect(find.text('STEP 6 / 6'), findsOneWidget);
    expect(find.text('Stay on track'), findsOneWidget);
    expect(
      find.text(
        'Pick what to be reminded about. You can change these any time in '
        'Settings.',
      ),
      findsOneWidget,
    );
    expect(find.text('Turn on reminders'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('Turn on reminders asks for permission, then builds the plan', (
    tester,
  ) async {
    final scheduler = _FakeScheduler();
    final completions = <int>[];
    final completed = <bool>[];
    await _pumpFlow(
      tester,
      patches: [],
      completions: completions,
      completed: completed,
      scheduler: scheduler,
    );

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(scheduler.requestPermissionCalls, 1);
    expect(completions, hasLength(1));
    expect(completed, [
      true,
    ], reason: 'requesting permission must not skip building the plan');
  });

  testWidgets('Not now builds the plan without asking', (tester) async {
    final scheduler = _FakeScheduler();
    final completions = <int>[];
    final completed = <bool>[];
    await _pumpFlow(
      tester,
      patches: [],
      completions: completions,
      completed: completed,
      scheduler: scheduler,
    );

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('secondary')));
    await tester.pumpAndSettle();

    expect(scheduler.requestPermissionCalls, 0);
    expect(completions, hasLength(1));
    expect(completed, [true]);
  });

  testWidgets('both reminder switches start on', (tester) async {
    await _pumpFlow(tester, patches: []);
    await _toRemindersStep(tester);

    Switch at(String key) => tester.widget<Switch>(find.byKey(Key(key)));
    expect(at('onboarding.remind.habits.switch').value, isTrue);
    expect(at('onboarding.remind.checkin.switch').value, isTrue);
  });

  testWidgets('Turn on reminders saves both choices after asking permission', (
    tester,
  ) async {
    final scheduler = _FakeScheduler();
    final permissionsAtPatch = <int>[];
    final reminders = _FakeReminderRepository(
      onPatch: () async =>
          permissionsAtPatch.add(scheduler.requestPermissionCalls),
    );
    final completed = <bool>[];
    await _pumpFlow(
      tester,
      patches: [],
      completed: completed,
      scheduler: scheduler,
      reminders: reminders,
    );
    await _toRemindersStep(tester);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(reminders.patches, [
      {'habitsEnabled': true, 'checkinEnabled': true},
    ]);
    expect(permissionsAtPatch, [1], reason: 'permission is asked first');
    expect(completed, [true]);
  });

  testWidgets('a switched-off check-in is saved off', (tester) async {
    final reminders = _FakeReminderRepository();
    await _pumpFlow(
      tester,
      patches: [],
      scheduler: _FakeScheduler(),
      reminders: reminders,
    );
    await _toRemindersStep(tester);

    await _tapKey(tester, const Key('onboarding.remind.checkin'));
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(reminders.patches, [
      {'habitsEnabled': true, 'checkinEnabled': false},
    ]);
  });

  testWidgets(
    'with both switched off, Continue asks nothing and saves both off',
    (tester) async {
      final scheduler = _FakeScheduler();
      final reminders = _FakeReminderRepository();
      final completed = <bool>[];
      await _pumpFlow(
        tester,
        patches: [],
        completed: completed,
        scheduler: scheduler,
        reminders: reminders,
      );
      await _toRemindersStep(tester);

      await _tapKey(tester, const Key('onboarding.remind.habits'));
      await _tapKey(tester, const Key('onboarding.remind.checkin'));
      expect(find.text('Turn on reminders'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('continue')),
          matching: find.text('Continue'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();

      expect(scheduler.requestPermissionCalls, 0);
      expect(reminders.patches, [
        {'habitsEnabled': false, 'checkinEnabled': false},
      ]);
      expect(completed, [true]);
    },
  );

  testWidgets('Not now saves no reminder choices', (tester) async {
    final reminders = _FakeReminderRepository();
    await _pumpFlow(
      tester,
      patches: [],
      scheduler: _FakeScheduler(),
      reminders: reminders,
    );
    await _toRemindersStep(tester);

    await tester.tap(find.byKey(const Key('secondary')));
    await tester.pumpAndSettle();

    expect(reminders.patches, isEmpty);
  });

  testWidgets('reminder choices that cannot be saved do not stop onboarding', (
    tester,
  ) async {
    final completed = <bool>[];
    await _pumpFlow(
      tester,
      patches: [],
      completed: completed,
      scheduler: _FakeScheduler(),
      reminders: _FakeReminderRepository(
        onPatch: () async => throw Exception('offline'),
      ),
    );
    await _toRemindersStep(tester);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(completed, [true]);
  });

  testWidgets('a reminder save that never finishes does not stop onboarding', (
    tester,
  ) async {
    final completed = <bool>[];
    await _pumpFlow(
      tester,
      patches: [],
      completed: completed,
      scheduler: _FakeScheduler(),
      reminders: _FakeReminderRepository(
        onPatch: () => Completer<void>().future,
      ),
    );
    await _toRemindersStep(tester);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(completed, [true]);
  });

  testWidgets('a reminder flag that cannot be saved does not stop onboarding', (
    tester,
  ) async {
    final completions = <int>[];
    final completed = <bool>[];
    await _pumpFlow(
      tester,
      patches: [],
      completions: completions,
      completed: completed,
      store: _ThrowingReminderPromptStore(),
    );

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('secondary')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(completions, hasLength(1));
    expect(completed, [
      true,
    ], reason: 'a rejected reminder flag write must not block the plan');
  });

  testWidgets(
    'a reminder flag write that never finishes does not stop onboarding',
    (tester) async {
      final completions = <int>[];
      final completed = <bool>[];
      await _pumpFlow(
        tester,
        patches: [],
        completions: completions,
        completed: completed,
        store: _HangingReminderPromptStore(),
      );

      await _skip(tester);
      await _skip(tester);
      await _skip(tester);
      await _skip(tester);
      await _passHealthClear(tester);
      await tester.tap(find.byKey(const Key('secondary')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(completions, hasLength(1));
      expect(
        completed,
        [true],
        reason:
            'a reminder flag write that never resolves must not hang the plan',
      );
    },
  );

  testWidgets(
    'finishing onboarding remembers the reminder question was answered',
    (tester) async {
      final notNowStore = ReminderPromptStore(backing: InMemorySecureStore());
      await _pumpFlow(tester, patches: [], store: notNowStore);

      await _skip(tester);
      await _skip(tester);
      await _skip(tester);
      await _skip(tester);
      await _passHealthClear(tester);
      await tester.tap(find.byKey(const Key('secondary')));
      await tester.pumpAndSettle();

      expect(
        await notNowStore.answered(),
        isTrue,
        reason: 'Not now still counts as answering the Home prompt',
      );
    },
  );

  testWidgets(
    'turning reminders on also remembers the reminder question was answered',
    (tester) async {
      final turnOnStore = ReminderPromptStore(backing: InMemorySecureStore());
      await _pumpFlow(
        tester,
        patches: [],
        store: turnOnStore,
        scheduler: _FakeScheduler(),
      );

      await _skip(tester);
      await _skip(tester);
      await _skip(tester);
      await _skip(tester);
      await _passHealthClear(tester);
      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();

      expect(await turnOnStore.answered(), isTrue);
    },
  );

  testWidgets('generating the plan completes onboarding and hands off', (
    tester,
  ) async {
    final completions = <int>[];
    final completed = <bool>[];
    await _pumpFlow(
      tester,
      patches: [],
      completions: completions,
      completed: completed,
    );

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(completions, hasLength(1));
    expect(completed, [
      true,
    ], reason: 'the shell has to be told, or the user stays in onboarding');
  });

  testWidgets('a built plan has Home say so when it opens', (tester) async {
    await _pumpFlow(tester, patches: []);

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingFlow)),
    );
    expect(container.read(planReadyProvider), isTrue);
  });

  testWidgets('a plan that failed to build is not announced', (tester) async {
    await _pumpFlow(
      tester,
      patches: [],
      onComplete: (attempt) async => throw const ApiException(
        'PLAN_GENERATION_FAILED',
        'Could not build a plan right now.',
      ),
    );

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingFlow)),
    );
    expect(container.read(planReadyProvider), isFalse);
  });

  testWidgets('a failed generation can be retried', (tester) async {
    final completions = <int>[];
    await _pumpFlow(
      tester,
      patches: [],
      completions: completions,
      onComplete: (attempt) async {
        // The server leaves onboarding incomplete when generation fails,
        // precisely so this retry is possible.
        if (attempt == 0) {
          throw const ApiException(
            'PLAN_GENERATION_FAILED',
            'Could not build a plan right now.',
          );
        }
      },
    );

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(find.text('Could not build a plan right now.'), findsOneWidget);
    expect(find.text('STEP 6 / 6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(completions, hasLength(2));
  });

  testWidgets('generating replaces the step with the plan-building screen', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pumpFlow(tester, patches: [], onComplete: (_) => gate.future);

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pump();

    expect(find.text('Building your plan…'), findsOneWidget);
    expect(
      find.text('STEP 6 / 6'),
      findsNothing,
      reason: 'the wizard chrome has no place on the generating screen',
    );

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the generating screen names the injuries the user reported', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pumpFlow(tester, patches: [], onComplete: (_) => gate.future);

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _tapKey(tester, const Key('injury.1'));
    // Skip, not Continue -- _injuries is local state set by the tap above,
    // and this test does not care whether the write itself lands.
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pump();

    // Resolved from injuryOptionsProvider — SelectedInjury carries only an id,
    // so a flow that forgot to look the name up would render an id or nothing.
    expect(find.text('Working around Shoulder'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a pick on the injuries step survives Skip and still reaches the server',
    (tester) async {
      final injuryWrites = <List<SelectedInjury>>[];
      await _pumpFlow(tester, patches: [], injuryWrites: injuryWrites);

      await _skip(tester);
      await _skip(tester);
      await _skip(tester);
      expect(find.text('STEP 4 / 6'), findsOneWidget);

      await _tapKey(tester, const Key('injury.1'));
      // Skip, not Continue -- this is the case that used to lose the pick,
      // back when Skip advanced without saving anything at all.
      await _skip(tester);
      expect(find.text('STEP 5 / 6'), findsOneWidget);
      await _passHealthClear(tester);

      await tester.tap(find.byKey(const Key('continue')));
      await tester.pumpAndSettle();

      expect(
        injuryWrites,
        isNotEmpty,
        reason:
            'a pick made on the injuries step must reach the server even '
            'when that step itself was skipped past',
      );
      expect(injuryWrites.last.single.injuryId, 1);
    },
  );

  testWidgets('holds the generating screen so a fast build cannot flash past', (
    tester,
  ) async {
    final completed = <bool>[];
    // Nothing is gated here: every write resolves on the next microtask, which
    // is the case the hold exists for.
    await _pumpFlow(tester, patches: [], completed: completed);

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pump();
    // Well past the point where the writes have all resolved, and far enough
    // in that a sub-second floor would already have handed off. Deliberately
    // short of the real floor so the exact duration stays a tunable number
    // rather than something this test pins down.
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Building your plan…'), findsOneWidget);
    expect(
      completed,
      isEmpty,
      reason: 'the screen is meant to be readable, not merely non-zero',
    );

    await tester.pumpAndSettle();

    expect(completed, [
      true,
    ], reason: 'the hold delays the hand-off, never skips it');
  });

  testWidgets('every row has ticked before the plan takes the screen', (
    tester,
  ) async {
    final completed = <bool>[];
    await _pumpFlow(tester, patches: [], completed: completed);

    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _skip(tester);
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pump();

    // Just past the last slot: with every write already resolved, all three
    // gates are open, so this is the moment the list is complete.
    await tester.pump(
      GeneratingPace.onboarding.revealAt.last +
          const Duration(milliseconds: 100),
    );

    for (final row in ['lead', 'avoiding', 'exercises']) {
      expect(
        find.byKey(Key('gen.$row.done')),
        findsOneWidget,
        reason: 'row $row should have ticked by the last slot',
      );
    }
    expect(
      completed,
      isEmpty,
      reason:
          'a hold shorter than the schedule would hand off mid-sequence '
          'and the last tick would never be seen',
    );

    await tester.pumpAndSettle();
    expect(completed, [true]);
  });

  testWidgets('back returns to the previous step', (tester) async {
    await _pumpFlow(tester, patches: []);

    await _skip(tester);
    expect(find.text('STEP 2 / 6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 / 6'), findsOneWidget);
  });

  group('Android back', () {
    testWidgets('on step 3 goes to step 2, not out of the app', (tester) async {
      await _pumpFlow(tester, patches: []);
      await _skip(tester);
      await _skip(tester);
      expect(find.text('STEP 3 / 6'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('STEP 2 / 6'), findsOneWidget);
      expect(find.byType(OnboardingFlow), findsOneWidget);
    });

    testWidgets('on step 1 is left to the system, as before', (tester) async {
      await _pumpFlow(tester, patches: []);

      final scope = tester.widget<PopScope<Object?>>(
        find.byKey(const Key('onboarding.pop')),
      );
      expect(scope.canPop, isTrue);
      expect(find.text('STEP 1 / 6'), findsOneWidget);
    });
  });

  testWidgets('Skip keeps the valid answers typed on the step', (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpFlow(tester, patches: patches);
    await _skip(tester);
    expect(find.text('STEP 2 / 6'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('weightKg')), '72');
    await tester.enterText(find.byKey(const Key('heightCm')), 'abc');
    await tester.pumpAndSettle();
    await _skip(tester);

    expect(patches, [
      {'weightKg': 72.0},
    ], reason: 'the typed weight is kept; the unreadable height is not sent');
    expect(find.text('STEP 3 / 6'), findsOneWidget);
  });

  testWidgets('Skip leaves out a zero the server would reject', (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpFlow(tester, patches: patches);
    await _skip(tester);
    expect(find.text('STEP 2 / 6'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('weightKg')), '72');
    await tester.enterText(find.byKey(const Key('heightCm')), '0');
    await tester.pumpAndSettle();
    await _skip(tester);

    expect(patches, [
      {'weightKg': 72.0},
    ], reason: 'the server rejects a height of 0, so Skip must not send it');
    expect(find.text('STEP 3 / 6'), findsOneWidget);
  });

  testWidgets('Continue sends a typed zero and explains the rejection', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    await _pumpFlow(
      tester,
      patches: patches,
      onPatch: () async {
        if (patches.last['heightCm'] == 0) {
          throw const ApiException(
            'INVALID_PROFILE_FIELD',
            'heightCm must be a number between 0 and 1000.',
          );
        }
      },
    );
    await _skip(tester);
    expect(find.text('STEP 2 / 6'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('weightKg')), '72');
    await tester.enterText(find.byKey(const Key('heightCm')), '0');
    await tester.pumpAndSettle();
    // The first Continue queries the 0; the second keeps it.
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();
    expect(patches, isEmpty);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(patches, [
      {'heightCm': 0.0, 'weightKg': 72.0},
    ], reason: 'Continue is an explicit answer, so a 0 is sent, not dropped');
    expect(find.text(_rejectedAnswer), findsOneWidget);
    expect(find.text('STEP 2 / 6'), findsOneWidget);
  });

  testWidgets('a rejected answer is explained without field names', (
    tester,
  ) async {
    await _pumpFlow(
      tester,
      patches: [],
      onSetGoals: () async => throw const ApiException(
        'INVALID_PROFILE_FIELD',
        'goalWeightKg must be a number between 0 and 1000.',
      ),
    );

    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(find.text(_rejectedAnswer), findsOneWidget);
    expect(find.textContaining('Kg'), findsNothing);
    expect(find.textContaining('Cm'), findsNothing);
    expect(find.text('STEP 1 / 6'), findsOneWidget);
  });

  testWidgets('Skip keeps the goals ticked on step 1', (tester) async {
    final goalWrites = <({List<String> goals, String mainGoal})>[];
    await _pumpFlow(tester, patches: [], goalWrites: goalWrites);

    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await _skip(tester);

    expect(goalWrites.single.goals, ['build_muscle']);
    expect(find.text('STEP 2 / 6'), findsOneWidget);
  });

  testWidgets('an error shows above Continue, in plain words, and is read '
      'aloud', (tester) async {
    await _pumpFlow(
      tester,
      patches: [],
      onSetGoals: () async => throw const ApiException(
        'NETWORK_ERROR',
        'Could not reach http://localhost:3000. Check the server is running, '
            'and that "adb reverse tcp:3000 tcp:3000" has been run.',
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    tester.takeAnnouncements();

    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    final error = find.byKey(const Key('error'));
    expect(error, findsOneWidget);
    final message = find.descendant(
      of: error,
      matching: find.text(
        "Couldn't reach FitSync. Check your connection and try again.",
      ),
    );
    expect(message, findsOneWidget);
    expect(find.textContaining('localhost'), findsNothing);
    expect(find.textContaining('adb'), findsNothing);

    // Directly above Continue: below everything the step shows, and its
    // bottom edge sits on Continue's top edge (give or take the gap).
    final errorRect = tester.getRect(error);
    final continueRect = tester.getRect(find.byKey(const Key('continue')));
    expect(errorRect.bottom, lessThanOrEqualTo(continueRect.top));
    expect(continueRect.top - errorRect.bottom, lessThan(24));

    // Read aloud by being a live region, which a screen reader speaks as it
    // appears -- and only that way, so it is not said twice.
    expect(
      tester
          .getSemantics(message)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(tester.takeAnnouncements(), isEmpty);
    handle.dispose();
  });

  testWidgets('a failed plan build offers Try again, which builds again', (
    tester,
  ) async {
    final completions = <int>[];
    final completed = <bool>[];
    final scheduler = _FakeScheduler();
    await _pumpFlow(
      tester,
      patches: [],
      completions: completions,
      completed: completed,
      scheduler: scheduler,
      onComplete: (attempt) async {
        if (attempt == 0) {
          throw const ApiException(
            'PLAN_GENERATION_FAILED',
            'Could not build a plan right now.',
          );
        }
      },
    );
    for (var i = 0; i < 4; i++) {
      await _skip(tester);
    }
    await _passHealthClear(tester);
    await tester.tap(find.byKey(const Key('continue')));
    await tester.pumpAndSettle();

    expect(find.text('Could not build a plan right now.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(
      find.byKey(const Key('secondary')),
      findsNothing,
      reason:
          'the reminder question is already answered; only the build is '
          'left to retry',
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(completions, hasLength(2));
    expect(completed, [true]);
    expect(
      scheduler.requestPermissionCalls,
      1,
      reason: 'retrying the build must not ask for permission a second time',
    );
  });

  group('Sign out on step 1', () {
    testWidgets('signs out', (tester) async {
      final auth = RecordingAuthController([]);
      await _pumpFlow(tester, patches: [], auth: auth);

      await _tapKey(tester, const Key('signOut'));

      expect(find.text('Sign out'), findsOneWidget);
      expect(auth.signOuts, 1);
    });

    testWidgets('is only on step 1', (tester) async {
      await _pumpFlow(tester, patches: []);
      await _skip(tester);

      expect(find.byKey(const Key('signOut')), findsNothing);
    });
  });

  group('A profile that cannot load', () {
    testWidgets('says why in plain words and retries', (tester) async {
      final attempts = <int>[];
      _FailingProfileNotifier.fail = true;
      addTearDown(() => _FailingProfileNotifier.fail = true);
      await _pumpFlow(
        tester,
        patches: [],
        profile: () => _FailingProfileNotifier(attempts),
      );

      expect(
        find.text(
          "Couldn't reach FitSync. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining('10.0.2.2'), findsNothing);
      expect(find.byType(FsRetry), findsOneWidget);

      _FailingProfileNotifier.fail = false;
      final before = attempts.length;
      await tester.tap(find.byKey(const Key('onboarding.retry')));
      await tester.pumpAndSettle();

      expect(attempts.length, greaterThan(before));
      expect(find.text('STEP 1 / 6'), findsOneWidget);
    });

    testWidgets('offers a way back to sign-in', (tester) async {
      final auth = RecordingAuthController([]);
      await _pumpFlow(
        tester,
        patches: [],
        auth: auth,
        profile: () => _FailingProfileNotifier([]),
      );

      final signOut = find.byKey(const Key('signOut'));
      expect(
        find.ancestor(
          of: find.text('Sign out'),
          matching: find.byType(FsButton),
        ),
        findsOneWidget,
      );
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      expect(auth.signOuts, 1);
    });

    testWidgets('fits a small phone at 2.0x text', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pumpFlow(
        tester,
        patches: [],
        profile: () => _FailingProfileNotifier([]),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('About step answers that look wrong', () {
    Future<void> toAbout(WidgetTester tester) async {
      await _skip(tester);
      expect(find.text('STEP 2 / 6'), findsOneWidget);
    }

    testWidgets('an implausible height is queried, then kept on a second '
        'Continue', (tester) async {
      final patches = <Map<String, dynamic>>[];
      await _pumpFlow(tester, patches: patches);
      await toAbout(tester);

      await tester.enterText(find.byKey(const Key('heightCm')), '17');
      await tester.enterText(find.byKey(const Key('weightKg')), '72');
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('continue'));

      expect(patches, isEmpty, reason: 'nothing saved until it is checked');
      expect(find.text('STEP 2 / 6'), findsOneWidget);
      final inline = find.byKey(const Key('error.heightCm'));
      expect(inline, findsOneWidget);
      expect(
        find.descendant(of: inline, matching: find.textContaining('17 cm')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('error')),
          matching: find.textContaining('height'),
        ),
        findsOneWidget,
      );

      // The user meant it: a second Continue saves it as it is.
      await _tapKey(tester, const Key('continue'));
      expect(patches, [
        {'heightCm': 17.0, 'weightKg': 72.0},
      ]);
      expect(find.text('STEP 3 / 6'), findsOneWidget);
    });

    testWidgets('fixing the queried answer clears its message and saves', (
      tester,
    ) async {
      final patches = <Map<String, dynamic>>[];
      await _pumpFlow(tester, patches: patches);
      await toAbout(tester);

      await tester.enterText(find.byKey(const Key('heightCm')), '17');
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('continue'));
      expect(find.byKey(const Key('error.heightCm')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('heightCm')), '175');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('error.heightCm')), findsNothing);
      expect(find.byKey(const Key('error')), findsNothing);

      await _tapKey(tester, const Key('continue'));
      expect(patches, [
        {'heightCm': 175.0},
      ]);
    });

    testWidgets('a new implausible value is queried again', (tester) async {
      final patches = <Map<String, dynamic>>[];
      await _pumpFlow(tester, patches: patches);
      await toAbout(tester);

      await tester.enterText(find.byKey(const Key('heightCm')), '17');
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('continue'));
      await tester.enterText(find.byKey(const Key('heightCm')), '18');
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('continue'));

      expect(patches, isEmpty);
      expect(find.byKey(const Key('error.heightCm')), findsOneWidget);
    });

    testWidgets('switching kg and lb under a queried weight is safe', (
      tester,
    ) async {
      final patches = <Map<String, dynamic>>[];
      await _pumpFlow(tester, patches: patches);
      await toAbout(tester);

      await tester.enterText(find.byKey(const Key('weightKg')), '7');
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('continue'));
      expect(find.byKey(const Key('error.weightKg')), findsOneWidget);

      await _tapKey(tester, const Key('unit.lb'));

      expect(tester.takeException(), isNull);
      expect(find.text('STEP 2 / 6'), findsOneWidget);
    });

    testWidgets('a rejected answer names the field the server pointed at', (
      tester,
    ) async {
      await _pumpFlow(
        tester,
        patches: [],
        onPatch: () async => throw const ApiException(
          'INVALID_PROFILE_FIELD',
          'weightKg must be a number between 0 and 1000.',
          details: [
            {'field': 'weightKg'},
          ],
        ),
      );
      await toAbout(tester);

      await tester.enterText(find.byKey(const Key('weightKg')), '72');
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('continue'));

      expect(
        find.descendant(
          of: find.byKey(const Key('error')),
          matching: find.text(
            "Your weight can't be saved as it is. Check it and try again.",
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('error.weightKg')), findsOneWidget);
      expect(find.textContaining('weightKg'), findsNothing);
      expect(find.text('STEP 2 / 6'), findsOneWidget);
    });
  });

  group('Moving between steps', () {
    double stepOffset(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(SingleChildScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;

    testWidgets('each step opens at its top, forwards and back', (
      tester,
    ) async {
      await _pumpFlow(tester, patches: []);
      await _skip(tester);
      expect(find.text('STEP 2 / 6'), findsOneWidget);

      // Down the long About step, then on to the next one.
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(stepOffset(tester), greaterThan(0));
      await _skip(tester);

      expect(find.text('STEP 3 / 6'), findsOneWidget);
      expect(stepOffset(tester), 0);

      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();

      expect(find.text('STEP 2 / 6'), findsOneWidget);
      expect(stepOffset(tester), 0);
    });

    testWidgets('a screen reader hears which step it is now on', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpFlow(tester, patches: []);
      tester.takeAnnouncements();

      await _skip(tester);
      expect(tester.takeAnnouncements().map((a) => a.message), [
        'Step 2 of 6: A bit about you',
      ]);

      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();
      expect(tester.takeAnnouncements().map((a) => a.message), [
        'Step 1 of 6: What are your goals?',
      ]);
      handle.dispose();
    });

    testWidgets('every step title is a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpFlow(tester, patches: []);

      bool isHeader(String title) => tester
          .getSemantics(find.text(title))
          .getSemanticsData()
          .flagsCollection
          .isHeader;

      for (final title in [
        'What are your goals?',
        'A bit about you',
        'Your level & equipment',
        'Any injuries?',
      ]) {
        expect(isHeader(title), isTrue, reason: '"$title" heads its step');
        await _skip(tester);
      }
      expect(isHeader('Your health'), isTrue);
      await _passHealthClear(tester);
      expect(isHeader('Stay on track'), isTrue);
      handle.dispose();
    });
  });

  testWidgets('step 2 estimates the target for the goal picked on step 1', (
    tester,
  ) async {
    await _pumpFlow(tester, patches: []);
    await tester.tap(find.byKey(const Key('goal.lose_weight')));
    await tester.pumpAndSettle();
    await _skip(tester);

    await _tapKey(tester, const Key('segment.male'));
    await _tapKey(tester, const Key('dateOfBirth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('heightCm')), '175');
    await tester.enterText(find.byKey(const Key('weightKg')), '72');
    await tester.pumpAndSettle();
    await _tapKey(tester, const Key('activity.light'));
    await tester.pumpAndSettle();

    // The picker opens on 1 January, 25 years back.
    final born = DateTime(DateTime.now().year - 25);
    String target(String? mainGoal) {
      final kcal = estimateDailyTargets(
        sex: 'male',
        dateOfBirth: '${born.year}-01-01',
        heightCm: 175,
        weightKg: 72,
        activityLevel: 'light',
        mainGoal: mainGoal,
      )!.kcal;
      return '${kcal ~/ 1000},${(kcal % 1000).toString().padLeft(3, '0')} kcal';
    }

    expect(target('lose_weight'), isNot(target(null)));
    expect(find.textContaining(target('lose_weight')), findsOneWidget);
  });
}
