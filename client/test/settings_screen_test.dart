import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
import 'package:fitsync/core/theme_controller.dart';
import 'package:fitsync/features/health/domain/health_answers.dart';
import 'package:fitsync/features/health/presentation/providers.dart';
import 'package:fitsync/features/onboarding/presentation/steps/health_step.dart';
import 'package:fitsync/features/plans/presentation/widgets/training_days_row.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/pro/presentation/pro_screen.dart';
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

import 'helpers/dialog_buttons.dart';
import 'helpers/fake_health.dart';

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
  });

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
  );

  @override
  Future<void> patch(Map<String, dynamic> fields) async {
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
        healthRepositoryProvider.overrideWithValue(
          health ?? FakeHealthRepository(),
        ),
      ],
      child: const MaterialApp(home: SettingsScreen()),
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
}
