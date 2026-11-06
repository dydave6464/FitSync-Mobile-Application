import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/auth/domain/auth_user.dart';
import 'package:fitsync/features/auth/presentation/auth_controller.dart';
import 'package:fitsync/features/onboarding/presentation/edit_scaffold.dart';
import 'package:fitsync/features/onboarding/presentation/onboarding_scaffold.dart';
import 'package:fitsync/features/onboarding/presentation/steps/about_step.dart';
import 'package:fitsync/features/onboarding/presentation/steps/goal_step.dart';
import 'package:fitsync/features/onboarding/presentation/steps/injuries_step.dart';
import 'package:fitsync/features/onboarding/presentation/steps/level_step.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/theme_controller.dart';
import 'package:fitsync/features/health/domain/health_answers.dart';
import 'package:fitsync/features/health/presentation/providers.dart';
import 'package:fitsync/features/onboarding/presentation/steps/health_step.dart';
import 'package:fitsync/features/plans/presentation/widgets/training_days_row.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/pro/presentation/pro_screen.dart';
import 'package:fitsync/features/pro/presentation/providers.dart';
import 'package:fitsync/features/reminders/domain/reminders.dart';
import 'package:fitsync/features/reminders/presentation/providers.dart';
import 'package:fitsync/features/reminders/presentation/reminders_screen.dart';
import 'package:fitsync/features/settings/presentation/settings_screen.dart';
import 'package:fitsync/features/streaks/domain/streaks.dart';
import 'package:fitsync/features/streaks/presentation/providers.dart'
    show goalsProvider, streakProvider;
import 'package:fitsync/features/streaks/presentation/streaks_screen.dart';
import 'package:fitsync/features/schedule/domain/calendar.dart';
import 'package:fitsync/features/schedule/presentation/providers.dart';
import 'package:fitsync/features/schedule/presentation/schedule_screen.dart';

import 'helpers/a11y.dart' show contrast;
import 'helpers/dialog_buttons.dart';
import 'helpers/fake_health.dart';
import 'helpers/fake_pro_repository.dart';

const _baseProfile = Profile(
  userId: 7,
  email: 'juan@example.com',
  fullName: 'Juan Dela Cruz',
  onboardingCompleted: true,
  isPremium: false,
  notificationsEnabled: true,
  equipment: [],
  injuries: [],
  city: 'Cebu City',
);

const _equipment = [EquipmentOption(equipmentId: 41, name: 'Resistance band')];
const _injuryOptions = [
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
    this.failPatch = false,
    this.trainingDays = const [],
    this.failTrainingDays = false,
    this.fitnessLevel,
    this.goals = const [],
    this.mainGoal,
    this.goalWrites,
    this.failGoals = false,
    this.heightCm,
    this.weightKg,
    this.goalWeightKg,
    this.patchError,
    this.patchGate,
    this.weightUnit = WeightUnit.kg,
  });

  /// The unit the profile opens in.
  final WeightUnit weightUnit;

  /// Seed the Body metrics editor, so a test can clear a stored value.
  final double? heightCm;
  final double? weightKg;
  final double? goalWeightKg;

  /// Thrown by `patch` instead of [failPatch]'s generic rejection, so a test
  /// can pick the error code (a network failure, say).
  final Object? patchError;

  /// Holds every `patch` until completed, so a test can look at the screen
  /// while a write is still on its way.
  final Completer<void>? patchGate;

  final List<Map<String, dynamic>> patches;

  /// Rejects the write, so a test can tell "saved" from "tried to save".
  final bool failPatch;

  /// Rejects `setGoals`, the way [failPatch] rejects `patch` -- goals save on
  /// their own endpoint now, so a goal-editor failure test has to fail that
  /// one instead.
  final bool failGoals;

  /// Seeds the profile the editor opens with, mirroring how `injuries` seeds
  /// `_InjuriesEditor` -- without this a picker test could never see a day
  /// already selected.
  final List<int> trainingDays;

  /// Rejects `setTrainingDays`, so a test can prove a failed save reports the
  /// error and leaves the editor open rather than looking saved.
  final bool failTrainingDays;

  /// Seeds the profile's stored fitness level, so a test can check how the
  /// header words it.
  final String? fitnessLevel;

  /// Seeds the profile's goals and main focus, the way `fitnessLevel` seeds
  /// the stored level -- without this the goal editor's "opens already
  /// accented" test could never see a goal already ticked.
  final List<String> goals;
  final String? mainGoal;

  /// Records every `setGoals` call, the way `equipmentWrites` would for
  /// equipment -- empty by default so tests that do not care never see it.
  final List<({List<String> goals, String mainGoal})>? goalWrites;

  /// The weekdays the screen last asked to save, recorded whether or not the
  /// write went on to succeed.
  List<int>? lastTrainingDays;

  @override
  Future<Profile> build() async => Profile(
    userId: _baseProfile.userId,
    email: _baseProfile.email,
    fullName: _baseProfile.fullName,
    onboardingCompleted: _baseProfile.onboardingCompleted,
    isPremium: _baseProfile.isPremium,
    notificationsEnabled: _baseProfile.notificationsEnabled,
    equipment: _baseProfile.equipment,
    injuries: _baseProfile.injuries,
    trainingDays: trainingDays,
    city: _baseProfile.city,
    mainGoal: mainGoal,
    goals: goals,
    fitnessLevel: fitnessLevel,
    heightCm: heightCm,
    weightKg: weightKg,
    goalWeightKg: goalWeightKg,
    weightUnit: weightUnit,
  );

  /// Every `patch` call, counted on arrival -- before [patchGate] holds it
  /// and whether or not it goes on to succeed.
  int patchCalls = 0;

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
    patchCalls += 1;
    if (patchGate != null) await patchGate!.future;
    if (patchError != null) throw patchError!;
    if (failPatch) {
      throw const ApiException('PROFILE_INVALID', 'That could not be saved.');
    }
    patches.add(fields);
  }

  @override
  Future<void> setEquipment(List<int> equipmentIds) async {}

  @override
  Future<void> setInjuries(List<SelectedInjury> injuries) async {}

  @override
  Future<void> setGoals(List<String> goals, String mainGoal) async {
    if (failGoals) {
      throw const ApiException('PROFILE_INVALID', 'That could not be saved.');
    }
    goalWrites?.add((goals: goals, mainGoal: mainGoal));
  }

  @override
  Future<void> setTrainingDays(List<int> weekdays) async {
    lastTrainingDays = weekdays;
    if (failTrainingDays) {
      throw const ApiException('PROFILE_INVALID', 'That could not be saved.');
    }
  }
}

/// A fixed answer instead of a repository round trip, so `SettingsScreen`
/// has something to give `RemindersScreen` when the notifications row opens
/// it -- this file's tests never change a reminder setting themselves.
class DefaultReminderSettings extends ReminderSettingsController {
  @override
  Future<ReminderSettings> build() async => ReminderSettings.defaults;
}

class RecordingAuthController extends AuthController {
  RecordingAuthController(this.signOuts);

  final List<bool> signOuts;

  @override
  Future<AuthState> build() async => AuthState(
    AuthStatus.ready,
    const AuthUser(
      userId: 7,
      email: 'juan@example.com',
      fullName: 'Juan Dela Cruz',
      onboardingCompleted: true,
      isPremium: false,
    ),
  );

  @override
  Future<void> signOut() async {
    signOuts.add(true);
    state = const AsyncData(AuthState.signedOut);
  }
}

/// A health repository whose load can be held open or made to fail, so a
/// test can see the editor's loading and error screens.
class _HealthLoad extends FakeHealthRepository {
  _HealthLoad({this.gate, this.failures = 0, this.error});

  /// Holds the load until completed.
  final Completer<HealthAnswers?>? gate;

  /// How many loads fail with [error] before one succeeds.
  int failures;
  final Object? error;
  int loads = 0;

  @override
  Future<HealthAnswers?> getHealth() async {
    loads += 1;
    if (gate != null) return gate!.future;
    if (failures > 0) {
      failures -= 1;
      throw error!;
    }
    return stored;
  }
}

/// The profile notifier fake the running test's `_pump` installed. Set fresh
/// on every call so a test can assert what it recorded -- `_profile.
/// lastTrainingDays` -- without threading the fake through by hand.
late FakeProfileNotifier _profile;

Future<void> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>>? patches,
  List<bool>? signOuts,
  bool failPatch = false,
  List<int> trainingDays = const [],
  bool failTrainingDays = false,
  String? fitnessLevel,
  List<String> goals = const [],
  String? mainGoal,
  List<({List<String> goals, String mainGoal})>? goalWrites,
  bool failGoals = false,
  FakeHealthRepository? health,
  FakeProRepository? pro,
  double? heightCm,
  double? weightKg,
  double? goalWeightKg,
  Object? patchError,
  Completer<void>? patchGate,
  bool dark = false,
  WeightUnit weightUnit = WeightUnit.kg,
}) async {
  _profile = FakeProfileNotifier(
    patches ?? <Map<String, dynamic>>[],
    failPatch: failPatch,
    trainingDays: trainingDays,
    failTrainingDays: failTrainingDays,
    fitnessLevel: fitnessLevel,
    goals: goals,
    mainGoal: mainGoal,
    goalWrites: goalWrites,
    failGoals: failGoals,
    heightCm: heightCm,
    weightKg: weightKg,
    goalWeightKg: goalWeightKg,
    patchError: patchError,
    patchGate: patchGate,
    weightUnit: weightUnit,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileProvider.overrideWith(() => _profile),
        authControllerProvider.overrideWith(
          () => RecordingAuthController(signOuts ?? []),
        ),
        equipmentOptionsProvider.overrideWith((ref) async => _equipment),
        injuryOptionsProvider.overrideWith((ref) async => _injuryOptions),
        reminderSettingsProvider.overrideWith(() => DefaultReminderSettings()),
        streakProvider.overrideWith(
          (ref) async =>
              const Streak(current: 0, best: 0, todayActive: false, week: []),
        ),
        goalsProvider.overrideWith((ref) async => const <LiftGoal>[]),
        calendarProvider.overrideWith(
          (ref, span) async =>
              const CalendarRange(today: '2026-09-24', days: []),
        ),
        proRepositoryProvider.overrideWithValue(pro ?? FakeProRepository()),
        healthRepositoryProvider.overrideWithValue(
          health ?? FakeHealthRepository(),
        ),
      ],
      child: MaterialApp(
        theme: dark ? fsDarkTheme() : null,
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls to a row and taps it.
///
/// scrollUntilVisible rather than ensureVisible: this is a ListView, which
/// does not build what it has not reached, and ensureVisible can only move to
/// a widget that is already in the tree. Rows low in the list were within the
/// build range by luck until the Pro card lengthened the screen above them.
Future<void> _openRow(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(find.byKey(key), 200);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows who is signed in', (tester) async {
    await _pump(tester, patches: []);

    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.textContaining('Cebu City'), findsOneWidget);
  });

  testWidgets('words the header as New to training, not New', (tester) async {
    await _pump(tester, patches: [], fitnessLevel: 'new');

    expect(find.textContaining('New to training'), findsOneWidget);
    expect(find.text('New'), findsNothing);
  });

  // Reachable when you are not mid-workout: the logger's header toggle is the
  // discoverable one, but nobody goes there to change a setting.
  testWidgets('the weight unit row saves what it is switched to', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    await _pump(tester, patches: patches);

    await _openRow(tester, const Key('unit.lb'));

    // Whole-list equality, not `contains`: Dart maps compare by identity, so
    // contains() would miss an equal-but-distinct map. This also pins that
    // flipping the unit writes nothing else.
    expect(patches, [
      {'weightUnit': 'lb'},
    ]);
  });

  // The switch is drawn a few pixels tall in a 32 dp row; a thumb gets the
  // full 48 dp, centred on it, without the row being drawn any taller.
  testWidgets('kg / lb answers a thumb 22 dp above or below its middle', (
    tester,
  ) async {
    final patches = <Map<String, dynamic>>[];
    await _pump(tester, patches: patches);
    await tester.scrollUntilVisible(find.byKey(const Key('unit.lb')), 200);
    await tester.pumpAndSettle();

    // The fake does not apply the patch, so kg stays in force and lb stays
    // the one that takes a tap.
    final lb = tester.getCenter(find.byKey(const Key('unit.lb')));
    await tester.tapAt(lb - const Offset(0, 22));
    await tester.pumpAndSettle();
    await tester.tapAt(lb + const Offset(0, 22));
    await tester.pumpAndSettle();
    expect(patches, [
      {'weightUnit': 'lb'},
      {'weightUnit': 'lb'},
    ]);
  });

  // lb ends the row, so the half of its band past the letters lies in the
  // card's 16 dp padding, outside the row itself.
  testWidgets('lb answers a thumb 8 dp past its letters', (tester) async {
    final patches = <Map<String, dynamic>>[];
    await _pump(tester, patches: patches);
    await tester.scrollUntilVisible(find.byKey(const Key('unit.lb')), 200);
    await tester.pumpAndSettle();

    final lb = tester.getRect(find.byKey(const Key('unit.lb')));
    await tester.tapAt(lb.centerRight + const Offset(8, 0));
    await tester.pumpAndSettle();
    expect(patches, [
      {'weightUnit': 'lb'},
    ]);
  });

  testWidgets('offers no language row', (tester) async {
    await _pump(tester, patches: []);

    // English only, per the spec. A row that does nothing is worse than none.
    expect(find.text('Language'), findsNothing);
  });

  testWidgets('each row opens its step inside the edit scaffold', (
    tester,
  ) async {
    await _pump(tester, patches: []);

    for (final row in [
      (key: const Key('edit.goal'), type: GoalStep),
      (key: const Key('edit.about'), type: AboutStep),
      (key: const Key('edit.level'), type: LevelStep),
      (key: const Key('edit.injuries'), type: InjuriesStep),
      (key: const Key('edit.health'), type: HealthStep),
    ]) {
      await _openRow(tester, row.key);

      expect(
        find.byType(EditScaffold),
        findsOneWidget,
        reason: '${row.key} must open an editor, not a wizard step',
      );
      expect(find.byType(row.type), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  // Settings > Body metrics is the same step as onboarding's "A bit about
  // you", so goal weight follows the saved goals there too.
  for (final (goals, asked) in [
    (['build_muscle'], false),
    (['lose_weight'], true),
  ]) {
    testWidgets(
      'Body metrics ${asked ? 'asks' : 'offers'} goal weight for ${goals.join(' + ')}',
      (tester) async {
        await _pump(tester, patches: [], goals: goals);
        await _openRow(tester, const Key('edit.about'));

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

  testWidgets('a profile seeded with goals but no focus does not crash Save', (
    tester,
  ) async {
    final goalWrites = <({List<String> goals, String mainGoal})>[];
    await _pump(
      tester,
      goals: ['lose_weight', 'build_muscle'],
      goalWrites: goalWrites,
    );

    await _openRow(tester, const Key('edit.goal'));
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // build_muscle comes before lose_weight in card order, so a null
    // focus falls back to it.
    expect(goalWrites.single.goals, ['build_muscle', 'lose_weight']);
    expect(goalWrites.single.mainGoal, 'build_muscle');
  });

  testWidgets('saving an edited goal writes it and returns', (tester) async {
    final patches = <Map<String, dynamic>>[];
    final goalWrites = <({List<String> goals, String mainGoal})>[];
    await _pump(tester, patches: patches, goalWrites: goalWrites);

    await _openRow(tester, const Key('edit.goal'));
    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    // Not a single record comparison: a record's == delegates to each
    // field's own ==, and List's is identity-based, so two structurally
    // identical records holding equal-but-distinct lists would never match.
    expect(goalWrites.single.goals, ['build_muscle']);
    expect(goalWrites.single.mainGoal, 'build_muscle');
    expect(patches, isEmpty, reason: 'goals have their own endpoint now');
    expect(
      find.byType(EditScaffold),
      findsNothing,
      reason: 'a successful save should return to Settings',
    );
  });

  testWidgets(
    'the goal editor opens seeded with every goal and the right focus chip',
    (tester) async {
      await _pump(
        tester,
        goals: ['lose_weight', 'improve_endurance'],
        mainGoal: 'improve_endurance',
      );

      await _openRow(tester, const Key('edit.goal'));

      expect(
        tester.widget<FsCard>(find.byKey(const Key('goal.lose_weight'))).accent,
        isTrue,
      );
      expect(
        tester
            .widget<FsCard>(find.byKey(const Key('goal.improve_endurance')))
            .accent,
        isTrue,
      );
      expect(
        tester
            .widget<FsChip>(find.byKey(const Key('focus.improve_endurance')))
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('a save says so, naming what was saved', (tester) async {
    await _pump(tester, patches: []);

    await _openRow(tester, const Key('edit.goal'));
    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    // Returning to Settings was the only signal a write had happened, which
    // looks the same as a screen that closed without doing anything.
    expect(find.text('Goals saved'), findsOneWidget);
  });

  testWidgets('the message names the section, not a generic success', (
    tester,
  ) async {
    await _pump(tester, patches: []);

    await _openRow(tester, const Key('edit.injuries'));
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    expect(find.text('Injuries saved'), findsOneWidget);
  });

  testWidgets('a failed save says nothing about having saved', (tester) async {
    await _pump(tester, patches: [], failGoals: true);

    await _openRow(tester, const Key('edit.goal'));
    await tester.tap(find.byKey(const Key('goal.build_muscle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    // Not textContaining('saved') — the rejection message itself reads "That
    // could not be saved", which such a matcher would catch and call a pass.
    expect(find.text('Goals saved'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byKey(const Key('error')),
      findsOneWidget,
      reason: 'the failure is reported where the user is, on the editor',
    );
  });

  testWidgets('the notifications row opens Reminders', (tester) async {
    await _pump(tester);

    await _openRow(tester, const Key('notifications'));

    expect(find.byType(RemindersScreen), findsOneWidget);
  });

  testWidgets('sign out clears the session', (tester) async {
    final signOuts = <bool>[];
    await _pump(tester, patches: [], signOuts: signOuts);

    // The list is long enough that sign out starts outside ListView's lazy
    // build window, so scroll it into existence before tapping.
    await tester.scrollUntilVisible(find.byKey(const Key('signOut')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signOut')));
    await tester.pumpAndSettle();

    expect(signOuts, [true]);
  });

  testWidgets('settings offers a training days row', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('edit.trainingDays')), findsOneWidget);
    expect(find.text('Training days'), findsOneWidget);
  });

  testWidgets('the row opens a picker seeded from the profile', (tester) async {
    await _pump(tester, trainingDays: const [1, 3]);

    await _openRow(tester, const Key('edit.trainingDays'));

    expect(
      tester
          .widget<TrainingDayCell>(find.byKey(const Key('weekday.1')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<TrainingDayCell>(find.byKey(const Key('weekday.5')))
          .selected,
      isFalse,
    );
  });

  testWidgets('saving the picker writes the whole set', (tester) async {
    await _pump(tester, trainingDays: const [1]);

    await _openRow(tester, const Key('edit.trainingDays'));
    await tester.tap(find.byKey(const Key('weekday.3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    expect(_profile.lastTrainingDays, [1, 3]);
  });

  testWidgets('a failed save reports it and stays on the editor', (
    tester,
  ) async {
    // Same contract every other editor here has: nothing may look saved that
    // is not, and the screen must not pop on failure.
    await _pump(tester, trainingDays: const [1], failTrainingDays: true);

    await _openRow(tester, const Key('edit.trainingDays'));
    await tester.tap(find.byKey(const Key('weekday.3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsOneWidget);
    expect(find.text('Training days'), findsOneWidget);
  });

  testWidgets('the same step widget renders under both scaffolds', (
    tester,
  ) async {
    // The point of the two-scaffold design. If this ever needs a flag on the
    // step to pass, the boundary has leaked and Task 10 stops being wiring.
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScaffold(
          step: 1,
          total: 4,
          onContinue: () {},
          child: GoalStep(value: const GoalAnswers(), onChanged: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal.lose_weight')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: EditScaffold(
          title: 'Goal',
          onSave: () {},
          child: GoalStep(value: const GoalAnswers(), onChanged: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal.lose_weight')), findsOneWidget);
  });

  testWidgets('the header toggle flips the theme', (tester) async {
    await _pump(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(themeModeProvider), ThemeMode.light);

    await tester.tap(find.byKey(const Key('themeToggle')));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  testWidgets('the theme is not also offered as a row', (tester) async {
    await _pump(tester);
    // Scrolled to the foot of the list so the App card is mounted: a
    // ListView leaves off-screen children unbuilt, and an unbuilt row would
    // let this pass whether or not the row was ever removed.
    await tester.scrollUntilVisible(find.byKey(const Key('signOut')), 200);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('signOut')), findsOneWidget);
    expect(find.text('Dark mode'), findsNothing);
  });

  testWidgets('the profile offers a way to Pro', (tester) async {
    await _pump(tester);

    // The prototype's own Profile screen carries this card, and it is the one
    // entry point that does not require meeting a lock first.
    await tester.tap(find.byKey(const Key('settings.goPro')));
    await tester.pumpAndSettle();

    expect(find.byType(ProScreen), findsOneWidget);
  });

  testWidgets('the Pro card shows when Pro ends', (tester) async {
    await _pump(
      tester,
      pro: FakeProRepository(paidStatus(until: DateTime(2026, 11, 26, 12))),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('settings.goPro')),
        matching: find.text('Pro until 26 Nov 2026'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the Pro screen asks for a fresh status each time it opens', (
    tester,
  ) async {
    // The Settings card keeps the status alive for as long as the tab is
    // mounted, so without a fresh ask a grant made on the server would not
    // show until the app restarted.
    final repo = FakeProRepository();
    await _pump(tester, pro: repo);
    await tester.tap(find.byKey(const Key('settings.goPro')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pro.pay')), findsOneWidget);

    await tester.tap(find.byKey(const Key('pro.close')));
    await tester.pumpAndSettle();
    repo.statusValue = grantedStatus;

    await tester.tap(find.byKey(const Key('settings.goPro')));
    await tester.pumpAndSettle();
    expect(find.text('FitSync Pro (granted)'), findsOneWidget);
    expect(find.byKey(const Key('pro.pay')), findsNothing);

    await tester.tap(find.byKey(const Key('pro.close')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('settings.goPro')),
        matching: find.text('Pro (granted)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the Streaks & goals row opens the screen', (tester) async {
    await _pump(tester);

    await _openRow(tester, const Key('edit.streaks'));

    expect(find.byType(StreaksScreen), findsOneWidget);
  });

  testWidgets('the Schedule row opens the screen', (tester) async {
    await _pump(tester);

    await _openRow(tester, const Key('edit.schedule'));

    expect(find.byType(ScheduleScreen), findsOneWidget);
  });

  final storedAsthma = HealthAnswers.fromJson(const {
    'conditions': ['asthma'],
    'chestPain': false,
    'dizziness': false,
    'supervisedOnly': false,
    'consentedAt': '2026-10-07T01:00:00.000Z',
    'acknowledgedAt': '2026-10-07T01:00:00.000Z',
  });

  testWidgets('the Health editor shows the stored answers, without opt-out', (
    tester,
  ) async {
    await _pump(tester, health: FakeHealthRepository(stored: storedAsthma));

    await _openRow(tester, const Key('edit.health'));

    expect(find.byType(EditScaffold), findsOneWidget);
    final step = tester.widget<HealthStep>(find.byType(HealthStep));
    expect(step.value.conditions, ['asthma']);
    expect(step.value.consent, isTrue);
    expect(find.byKey(const Key('health.optOut')), findsNothing);
  });

  testWidgets('Save waits for a valid answer, then writes it', (tester) async {
    final health = FakeHealthRepository();
    await _pump(tester, health: health);
    await _openRow(tester, const Key('edit.health'));

    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();
    expect(health.writes, isEmpty);
    expect(find.byType(HealthStep), findsOneWidget, reason: 'still open');

    for (final key in [
      'health.none',
      'health.chestPain.no',
      'health.dizziness.no',
      'health.supervisedOnly.no',
    ]) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('save')));
    await tester.pumpAndSettle();

    expect(health.writes.single.conditions, isEmpty);
    expect(find.byType(HealthStep), findsNothing, reason: 'closed');
    expect(find.text('Health saved'), findsOneWidget);
  });

  testWidgets('the Health editor says why Save is greyed, right above it', (
    tester,
  ) async {
    await _pump(tester);
    await _openRow(tester, const Key('edit.health'));

    final hint = find.text('Answer every question to save');
    expect(hint, findsOneWidget);
    final save = tester.getRect(find.byKey(const Key('save')));
    expect(save.top - tester.getRect(hint).bottom, inInclusiveRange(0, 24));
  });

  testWidgets('there is no delete button without stored answers', (
    tester,
  ) async {
    await _pump(tester);
    await _openRow(tester, const Key('edit.health'));

    expect(find.byKey(const Key('health.delete')), findsNothing);
  });

  testWidgets('the delete question shows Delete in red', (tester) async {
    await _pump(tester, health: FakeHealthRepository(stored: storedAsthma));
    await _openRow(tester, const Key('edit.health'));

    await tester.ensureVisible(find.byKey(const Key('health.delete')));
    await tester.tap(find.byKey(const Key('health.delete')));
    await tester.pumpAndSettle();

    expect(
      labelColor(tester, find.byKey(const Key('health.delete.confirm'))),
      dialogRed(tester),
    );
    expect(
      labelColor(tester, find.byKey(const Key('health.delete.cancel'))),
      isNot(dialogRed(tester)),
    );
  });

  testWidgets('delete asks first, then removes the answers', (tester) async {
    final health = FakeHealthRepository(stored: storedAsthma);
    await _pump(tester, health: health);
    await _openRow(tester, const Key('edit.health'));

    await tester.ensureVisible(find.byKey(const Key('health.delete')));
    await tester.tap(find.byKey(const Key('health.delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete your health answers?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('health.delete.cancel')));
    await tester.pumpAndSettle();
    expect(health.deletes, 0);

    await tester.tap(find.byKey(const Key('health.delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('health.delete.confirm')));
    await tester.pumpAndSettle();

    expect(health.deletes, 1);
    expect(find.byType(HealthStep), findsNothing, reason: 'closed');
    expect(find.text('Health answers deleted'), findsOneWidget);
  });

  // AO-4 / PS-1: back threw away whatever the editor held, with no warning.
  group('an edited answer is not dropped on back', () {
    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    final edits = <String, Future<void> Function(WidgetTester)>{
      'edit.goal': (t) => tapKey(t, 'goal.build_muscle'),
      'edit.about': (t) async {
        await t.enterText(find.byKey(const Key('heightCm')), '181');
        await t.pumpAndSettle();
      },
      'edit.level': (t) => tapKey(t, 'equipment.41'),
      'edit.injuries': (t) => tapKey(t, 'injury.1'),
      'edit.health': (t) => tapKey(t, 'health.none'),
      'edit.trainingDays': (t) => tapKey(t, 'weekday.1'),
      'profile.edit': (t) async {
        await t.enterText(find.byKey(const Key('profile.city')), 'Davao');
        await t.pumpAndSettle();
      },
    };

    for (final MapEntry(key: row, value: edit) in edits.entries) {
      testWidgets('$row asks before discarding, and Keep editing stays', (
        tester,
      ) async {
        final patches = <Map<String, dynamic>>[];
        await _pump(tester, patches: patches, heightCm: 170, weightKg: 70);
        await _openRow(tester, Key(row));
        await edit(tester);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Discard your changes?'), findsOneWidget);

        await tester.tap(find.byKey(const Key('discard.keep')));
        await tester.pumpAndSettle();
        expect(find.byType(EditScaffold), findsOneWidget, reason: 'kept');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('discard.confirm')));
        await tester.pumpAndSettle();
        expect(find.byType(EditScaffold), findsNothing, reason: 'discarded');
        expect(patches, isEmpty, reason: 'discarding writes nothing');
      });

      testWidgets('$row closes on back without asking when unchanged', (
        tester,
      ) async {
        await _pump(tester, heightCm: 170, weightKg: 70);
        await _openRow(tester, Key(row));

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Discard your changes?'), findsNothing);
        expect(find.byType(EditScaffold), findsNothing);
      });
    }

    // 0.1 lb is 0.045 kg: inside a 0.05 kg tolerance, so the smallest edit
    // a user in pounds can make was dropped on back without a word.
    testWidgets('a 0.1 lb weight edit still asks before discarding', (
      tester,
    ) async {
      await _pump(
        tester,
        heightCm: 170,
        weightKg: 155 * 0.45359237,
        weightUnit: WeightUnit.lb,
      );
      await _openRow(tester, const Key('edit.about'));
      await tester.enterText(find.byKey(const Key('weightKg')), '155.1');
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
    });

    testWidgets('undoing an edit makes back quiet again', (tester) async {
      await _pump(tester);
      await _openRow(tester, const Key('edit.goal'));
      await tapKey(tester, 'goal.build_muscle');
      await tapKey(tester, 'goal.build_muscle');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.byType(EditScaffold), findsNothing);
    });
  });

  // PS-12: the name Home greets the user with could never be corrected, and
  // the city was never asked for at all.
  group('name and city', () {
    testWidgets('the header card offers Edit, a full-size target', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('profile.edit')),
          matching: find.text('Edit'),
        ),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('Edit opens both, filled in, and Save writes them', (
      tester,
    ) async {
      final patches = <Map<String, dynamic>>[];
      await _pump(tester, patches: patches);
      await _openRow(tester, const Key('profile.edit'));

      expect(find.byType(EditScaffold), findsOneWidget);
      final name = tester.widget<TextField>(
        find.byKey(const Key('profile.fullName')),
      );
      expect(name.controller!.text, 'Juan Dela Cruz');
      expect(name.autofillHints, [AutofillHints.name]);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('profile.city')))
            .controller!
            .text,
        'Cebu City',
      );

      await tester.enterText(
        find.byKey(const Key('profile.fullName')),
        '  Juan D. Cruz ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      expect(patches, [
        {'fullName': 'Juan D. Cruz', 'city': 'Cebu City'},
      ]);
      expect(find.text('Name & city saved'), findsOneWidget);
    });

    testWidgets('an emptied city is cleared', (tester) async {
      final patches = <Map<String, dynamic>>[];
      await _pump(tester, patches: patches);
      await _openRow(tester, const Key('profile.edit'));

      await tester.enterText(find.byKey(const Key('profile.city')), ' ');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      expect(patches.single.containsKey('city'), isTrue);
      expect(patches.single['city'], isNull);
    });

    testWidgets('the header and the editor fit a small phone at 2x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pump(tester);
      expect(tester.takeException(), isNull);
      await _openRow(tester, const Key('profile.edit'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty name greys Save and says why', (tester) async {
      final patches = <Map<String, dynamic>>[];
      await _pump(tester, patches: patches);
      await _openRow(tester, const Key('profile.edit'));

      await tester.enterText(find.byKey(const Key('profile.fullName')), '');
      await tester.pumpAndSettle();

      expect(
        tester.widget<FsButton>(find.byKey(const Key('save'))).onPressed,
        isNull,
      );
      expect(find.text('Enter your name to save.'), findsOneWidget);
    });
  });

  // PS-5: the kg/lb switch looked dead until the server answered, and a
  // failure changed nothing and said nothing.
  group('the kg/lb switch answers at once', () {
    WeightUnit shown(WidgetTester tester) =>
        tester.widget<FsUnitToggle>(find.byType(FsUnitToggle)).value;

    Future<void> openUnit(WidgetTester tester, String editor) async {
      if (editor == 'row') {
        await tester.scrollUntilVisible(find.byKey(const Key('unit.lb')), 200);
        await tester.pumpAndSettle();
      } else {
        await _openRow(tester, const Key('edit.about'));
        await tester.ensureVisible(find.byKey(const Key('unit.lb')));
        await tester.pumpAndSettle();
      }
    }

    // The unit saves on tap, so it is no edit for back to warn about -- even
    // though the weights on screen are rewritten in pounds, rounded.
    testWidgets('a unit switch alone leaves Body metrics clean', (
      tester,
    ) async {
      final gate = Completer<void>();
      await _pump(tester, heightCm: 170, weightKg: 70.3, patchGate: gate);
      await openUnit(tester, 'Body metrics');
      await tester.tap(find.byKey(const Key('unit.lb')));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.byType(EditScaffold), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
    });

    for (final editor in ['row', 'Body metrics']) {
      testWidgets('$editor: shows the new unit while saving, ignoring taps', (
        tester,
      ) async {
        final gate = Completer<void>();
        await _pump(tester, heightCm: 170, weightKg: 70, patchGate: gate);
        await openUnit(tester, editor);

        await tester.tap(find.byKey(const Key('unit.lb')));
        await tester.pump();
        expect(shown(tester), WeightUnit.lb, reason: 'shown straight away');

        await tester.tap(find.byKey(const Key('unit.kg')));
        await tester.pump();
        expect(_profile.patchCalls, 1, reason: 'a second tap waits its turn');
        expect(shown(tester), WeightUnit.lb);

        gate.complete();
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('$editor: a failed switch goes back and says so', (
        tester,
      ) async {
        await _pump(
          tester,
          heightCm: 170,
          weightKg: 70,
          patchError: const ApiException('NETWORK_ERROR', 'SocketException'),
        );
        await openUnit(tester, editor);

        await tester.tap(find.byKey(const Key('unit.lb')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(shown(tester), WeightUnit.kg);
        expect(find.text("Couldn't switch to lb. Try again."), findsOneWidget);
      });
    }
  });

  // PS-4: the Health editor's loading screen had no title or back button,
  // and its error screen no way to try again.
  group('the Health editor while it loads or fails', () {
    testWidgets('loading keeps the title and the back button', (tester) async {
      final health = _HealthLoad(gate: Completer<HealthAnswers?>());
      await _pump(tester, health: health);
      await tester.scrollUntilVisible(
        find.byKey(const Key('edit.health')),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit.health')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Health'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);

      health.gate!.complete(null);
      await tester.pumpAndSettle();
    });

    testWidgets('a failed load offers Try again, which reloads', (
      tester,
    ) async {
      final health = _HealthLoad(
        failures: 1000,
        error: const ApiException('NETWORK_ERROR', 'SocketException'),
      );
      await _pump(tester, health: health);
      await _openRow(tester, const Key('edit.health'));

      expect(find.widgetWithText(AppBar, 'Health'), findsOneWidget);
      expect(find.byType(FsRetry), findsOneWidget);
      expect(
        find.text(
          "Couldn't reach FitSync. Check your connection and try again.",
        ),
        findsOneWidget,
      );

      final loadsBefore = health.loads;
      health.failures = 0;
      await tester.tap(find.byKey(const Key('health.retry')));
      await tester.pumpAndSettle();
      expect(find.byType(HealthStep), findsOneWidget);
      expect(health.loads, loadsBefore + 1);
    });
  });

  // PS-2: "Goals saved" / "Body metrics saved" appeared over writes that
  // never happened.
  group('Save says saved only for a real write', () {
    bool saveEnabled(WidgetTester tester) =>
        tester.widget<FsButton>(find.byKey(const Key('save'))).onPressed !=
        null;

    testWidgets('unticking every goal greys Save and says why', (tester) async {
      final goalWrites = <({List<String> goals, String mainGoal})>[];
      await _pump(
        tester,
        goals: ['build_muscle'],
        mainGoal: 'build_muscle',
        goalWrites: goalWrites,
      );
      await _openRow(tester, const Key('edit.goal'));
      await tester.tap(find.byKey(const Key('goal.build_muscle')));
      await tester.pumpAndSettle();

      expect(saveEnabled(tester), isFalse);
      expect(find.text('Pick at least one goal to save.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();
      expect(goalWrites, isEmpty);
      expect(find.text('Goals saved'), findsNothing);
      expect(find.byType(EditScaffold), findsOneWidget, reason: 'still open');
    });

    testWidgets('clearing a stored goal weight removes it', (tester) async {
      final patches = <Map<String, dynamic>>[];
      await _pump(
        tester,
        patches: patches,
        goals: ['lose_weight'],
        mainGoal: 'lose_weight',
        heightCm: 170,
        weightKg: 70,
        goalWeightKg: 65,
      );
      await _openRow(tester, const Key('edit.about'));
      await tester.enterText(find.byKey(const Key('goalWeightKg')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      expect(patches.single.containsKey('goalWeightKg'), isTrue);
      expect(patches.single['goalWeightKg'], isNull);
      expect(find.text('Body metrics saved'), findsOneWidget);
    });

    testWidgets('an untouched empty goal weight is not sent', (tester) async {
      final patches = <Map<String, dynamic>>[];
      await _pump(tester, patches: patches, heightCm: 170, weightKg: 70);
      await _openRow(tester, const Key('edit.about'));
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      expect(patches.single.containsKey('goalWeightKg'), isFalse);
    });

    for (final (field, hint) in [
      ('heightCm', 'Enter your height to save.'),
      ('weightKg', 'Enter your weight to save.'),
    ]) {
      testWidgets('an empty $field greys Save and says why', (tester) async {
        final patches = <Map<String, dynamic>>[];
        await _pump(tester, patches: patches, heightCm: 170, weightKg: 70);
        await _openRow(tester, const Key('edit.about'));
        await tester.enterText(find.byKey(Key(field)), '');
        await tester.pumpAndSettle();

        expect(saveEnabled(tester), isFalse);
        expect(find.text(hint), findsOneWidget);
        await tester.tap(find.byKey(const Key('save')));
        await tester.pumpAndSettle();
        expect(patches, isEmpty);
        expect(find.text('Body metrics saved'), findsNothing);
      });
    }
  });

  // AO-12 / PS-3: a failed save's message sat under the whole form, often
  // below the fold, and was not announced.
  group('a failed save is reported right above Save', () {
    void expectErrorAboveSave(WidgetTester tester, String message) {
      final line = find.byType(FsErrorLine);
      expect(line, findsOneWidget);
      expect(
        find.descendant(of: line, matching: find.text(message)),
        findsOneWidget,
      );
      expect(find.byKey(const Key('error')), findsOneWidget);
      final gap =
          tester.getRect(find.byKey(const Key('save'))).top -
          tester.getRect(line).bottom;
      expect(gap, inInclusiveRange(0, 24));
    }

    testWidgets('in a profile editor, in plain words', (tester) async {
      await _pump(tester, failTrainingDays: true);
      await _openRow(tester, const Key('edit.trainingDays'));
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      expectErrorAboveSave(tester, 'That could not be saved.');
    });

    testWidgets('a lost connection reads as one, not as a raw code', (
      tester,
    ) async {
      await _pump(
        tester,
        heightCm: 170,
        weightKg: 70,
        patchError: const ApiException('NETWORK_ERROR', 'SocketException'),
      );
      await _openRow(tester, const Key('edit.about'));
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      expectErrorAboveSave(
        tester,
        "Couldn't reach FitSync. Check your connection and try again.",
      );
    });

    testWidgets('in the Health editor', (tester) async {
      final health = FakeHealthRepository(stored: storedAsthma)
        ..writeError = const ApiException('HEALTH_INVALID', 'Not saved.');
      await _pump(tester, health: health);
      await _openRow(tester, const Key('edit.health'));
      await tester.tap(find.byKey(const Key('save')));
      await tester.pumpAndSettle();

      expectErrorAboveSave(tester, 'Not saved.');
    });
  });

  for (final dark in [false, true]) {
    testWidgets("the Pro card's subtitle reads at 4.5:1 on its accent tint "
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await _pump(tester, dark: dark);
      final t = dark ? FsTokens.dark : FsTokens.light;
      // FsCard(accent: true) at its strongest tint.
      final strongest = Color.alphaBlend(
        t.accent.withValues(alpha: 0.16),
        t.bg,
      );
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('settings.goPro')),
          matching: find.byType(Text),
        ),
      );
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(
          contrast(text.style!.color!, strongest),
          greaterThanOrEqualTo(4.5),
          reason: text.data,
        );
      }
    });
  }
}
