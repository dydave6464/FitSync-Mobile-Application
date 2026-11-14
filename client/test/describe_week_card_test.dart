import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/plans/data/plan_repository.dart';
import 'package:fitsync/features/plans/domain/week_description.dart';
import 'package:fitsync/features/plans/presentation/providers.dart';
import 'package:fitsync/features/plans/presentation/widgets/describe_week_card.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

const _knee = InjuryOption(
  injuryId: 3,
  name: 'Knee',
  isLateral: true,
  regionGroup: 'leg',
);
const _back = InjuryOption(
  injuryId: 9,
  name: 'Lower back',
  isLateral: false,
  regionGroup: 'back',
);

/// Answers `readWeek` with whatever the test queued, and records every text
/// the card sent.
class FakeWeekRepository implements PlanRepository {
  final List<String> readWeekCalls = [];

  /// What the next reading answers, when nothing else is set: an empty AI
  /// reading.
  WeekDescription nextReading = const WeekDescription(source: WeekSource.ai);

  /// When set, `readWeek` waits on this instead, so a test decides when the
  /// answer lands.
  Future<WeekDescription>? pendingReading;

  /// When set, `readWeek` fails with it.
  Object? readWeekError;

  @override
  Future<WeekDescription> readWeek(String text) async {
    readWeekCalls.add(text);
    if (readWeekError != null) throw readWeekError!;
    if (pendingReading != null) return pendingReading!;
    return nextReading;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not used by these tests',
  );
}

class FakeCardProfile extends ProfileNotifier {
  FakeCardProfile({
    this.trainingDays = const [1, 3, 5],
    this.injuries = const [],
  });

  List<int> trainingDays;
  List<SelectedInjury> injuries;

  /// The weekdays the card last saved, null before any save.
  List<int>? savedTrainingDays;
  List<SelectedInjury>? savedInjuries;

  bool failTrainingDays = false;
  bool failInjuries = false;

  Profile _profile() => Profile(
    userId: 1,
    email: 'test@example.com',
    fullName: 'Test User',
    onboardingCompleted: true,
    isPremium: false,
    notificationsEnabled: true,
    equipment: const [],
    injuries: injuries,
    trainingDays: trainingDays,
  );

  @override
  Future<Profile> build() async => _profile();

  @override
  Future<void> setTrainingDays(List<int> weekdays) async {
    if (failTrainingDays) {
      throw const ApiException('VALIDATION_ERROR', 'Could not save days.');
    }
    savedTrainingDays = weekdays;
    trainingDays = weekdays;
    state = AsyncData(_profile());
  }

  @override
  Future<void> setInjuries(List<SelectedInjury> next) async {
    if (failInjuries) {
      throw const ApiException('VALIDATION_ERROR', 'Could not save that.');
    }
    savedInjuries = next;
    injuries = next;
    state = AsyncData(_profile());
  }
}

late FakeWeekRepository repo;
late FakeCardProfile profile;
late List<String> splits;
late List<int> lengths;
late List<int> dayCounts;

Future<void> pumpCard(
  WidgetTester tester, {
  required String composed,
  List<InjuryOption> options = const [_knee, _back],
  bool catalogueFailed = false,
  List<int> trainingDays = const [1, 3, 5],
  List<SelectedInjury> injuries = const [],
}) async {
  repo = FakeWeekRepository();
  profile = FakeCardProfile(trainingDays: trainingDays, injuries: injuries);
  splits = [];
  lengths = [];
  dayCounts = [];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planRepositoryProvider.overrideWithValue(repo),
        profileProvider.overrideWith(() => profile),
        injuryOptionsProvider.overrideWith((ref) async => options),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            // The days come from the profile, as on the screen, so a saved
            // set comes back round into the card.
            child: Consumer(
              builder: (context, ref, _) => DescribeWeekCard(
                composed: composed,
                options: options,
                catalogueFailed: catalogueFailed,
                trainingDays:
                    ref.watch(profileProvider).value?.trainingDays ??
                    const <int>[],
                onSplit: splits.add,
                onLength: lengths.add,
                onDayCount: dayCounts.add,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> type(WidgetTester tester, String text) =>
    tester.enterText(find.byKey(const Key('gen.describe.field')), text);

void main() {
  testWidgets('no Apply: typing is read after a pause', (tester) async {
    await pumpCard(tester, composed: 'I want to build muscle');
    expect(find.text('Apply'), findsNothing);
    await type(tester, 'ppl, 50 min');
    await tester.pump(const Duration(milliseconds: 399));
    expect(splits, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(splits, ['push_pull_legs']);
    expect(lengths, [45]);
    expect(find.text('Split: Push / Pull / Legs'), findsOneWidget);
    expect(find.text('Length: 45 min (nearest to 50)'), findsOneWidget);
  });

  testWidgets('a length typed exactly reads without the nearest note', (
    tester,
  ) async {
    await pumpCard(tester, composed: '');
    await type(tester, 'an hour');
    await tester.pump(kPhoneReadDelay);
    expect(lengths, [60]);
    expect(find.text('Length: 60 min'), findsOneWidget);
  });

  testWidgets('each keystroke restarts the pause', (tester) async {
    await pumpCard(tester, composed: '');
    await type(tester, 'pp');
    await tester.pump(const Duration(milliseconds: 300));
    await type(tester, 'ppl');
    await tester.pump(const Duration(milliseconds: 300));
    expect(splits, isEmpty, reason: 'read once typing stops, not per key');
    await tester.pump(const Duration(milliseconds: 100));
    expect(splits, ['push_pull_legs']);
  });

  testWidgets(
    'the filled-in sentence applies nothing and is never sent to AI',
    (tester) async {
      await pumpCard(
        tester,
        composed: 'train 3 days a week, push / pull / legs',
      );
      await tester.pump(const Duration(seconds: 2));
      expect(splits, isEmpty);
      expect(dayCounts, isEmpty);
      expect(repo.readWeekCalls, isEmpty);
      // Read for its lines all the same.
      expect(find.text('Split: Push / Pull / Legs'), findsOneWidget);
    },
  );

  testWidgets('From profile goes back to the sentence and applies nothing', (
    tester,
  ) async {
    await pumpCard(tester, composed: 'upper / lower');
    await type(tester, 'ppl');
    await tester.pump(kAiReadDelay);
    expect(splits, ['push_pull_legs']);

    await tester.tap(find.byKey(const Key('gen.describe.fromProfile')));
    await tester.pump(const Duration(seconds: 2));

    expect(splits, ['push_pull_legs'], reason: 'the baseline applies nothing');
    expect(repo.readWeekCalls, isEmpty);
    expect(find.text('Split: Upper / Lower'), findsOneWidget);
  });

  testWidgets('a hand-picked chip survives typing that does not name a split', (
    tester,
  ) async {
    await pumpCard(tester, composed: '');
    await type(tester, 'ppl');
    await tester.pump(const Duration(milliseconds: 400));
    expect(splits, ['push_pull_legs']);
    await type(tester, 'ppl, protect my knee');
    await tester.pump(const Duration(milliseconds: 400));
    expect(splits, [
      'push_pull_legs',
    ], reason: 'the split did not change, so it is not re-applied');
  });

  testWidgets('the AI reading replaces the lines after 1.5 s and is tagged', (
    tester,
  ) async {
    await pumpCard(tester, composed: '');
    repo.nextReading = const WeekDescription(
      splitStyle: 'upper_lower',
      source: WeekSource.ai,
    );
    await type(tester, 'top half one day bottom the next');
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(repo.readWeekCalls, ['top half one day bottom the next']);
    expect(splits.last, 'upper_lower');
    expect(find.text('Split: Upper / Lower'), findsOneWidget);
    expect(find.byKey(const Key('gen.describe.ai')), findsOneWidget);
    expect(find.text('Read by AI'), findsOneWidget);
  });

  testWidgets('the same text is not sent twice', (tester) async {
    await pumpCard(tester, composed: '');
    await type(tester, 'full body please');
    await tester.pump(kAiReadDelay);
    await type(tester, 'full body please!');
    await tester.pump(const Duration(milliseconds: 200));
    await type(tester, 'full body please');
    await tester.pump(kAiReadDelay);
    expect(repo.readWeekCalls, ['full body please']);
  });

  testWidgets('a stale AI answer is dropped', (tester) async {
    await pumpCard(tester, composed: '');
    final pending = Completer<WeekDescription>();
    repo.pendingReading = pending.future;
    await type(tester, 'top half bottom half');
    await tester.pump(const Duration(milliseconds: 1500));
    await type(tester, 'full body');
    pending.complete(
      const WeekDescription(splitStyle: 'upper_lower', source: WeekSource.ai),
    );
    await tester.pump();
    expect(splits, isNot(contains('upper_lower')));
    expect(find.text('Read by AI'), findsNothing);
  });

  testWidgets('AI_BUSY keeps the phone reading with no message', (
    tester,
  ) async {
    await pumpCard(tester, composed: '');
    repo.readWeekError = const ApiException(
      'AI_BUSY',
      'AI reading is busy. Try again in a moment.',
    );
    await type(tester, 'ppl, 45 min');
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(repo.readWeekCalls, ['ppl, 45 min']);
    expect(find.text('Split: Push / Pull / Legs'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Read by AI'), findsNothing);
  });

  testWidgets('a network failure keeps the phone reading with no message', (
    tester,
  ) async {
    await pumpCard(tester, composed: '');
    repo.readWeekError = const ApiException('NETWORK_ERROR', 'offline');
    await type(tester, 'ppl, 45 min');
    await tester.pump(kAiReadDelay);
    await tester.pump();
    expect(find.text('Split: Push / Pull / Legs'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('gen.describe.limit')), findsNothing);
  });

  testWidgets('READ_LIMIT says so once and stops asking', (tester) async {
    await pumpCard(tester, composed: '');
    repo.readWeekError = const ApiException(
      'READ_LIMIT',
      'AI reading is used up for today.',
    );
    await type(tester, 'ppl, 45 min');
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(
      find.text('AI reading is used up for today. Showing the quick reading.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('gen.describe.limit')), findsOneWidget);
    await type(tester, 'upper lower please');
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(repo.readWeekCalls.length, 1);
    expect(splits.last, 'upper_lower', reason: 'the phone still reads it');
  });

  testWidgets('one word is not sent to AI', (tester) async {
    await pumpCard(tester, composed: '');
    await type(tester, 'ppl');
    await tester.pump(const Duration(milliseconds: 1500));
    expect(repo.readWeekCalls, isEmpty);
  });

  testWidgets(
    'named days offer Use these days, and saying your own days does not',
    (tester) async {
      await pumpCard(tester, composed: '');
      await type(tester, 'mon wed fri');
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Days: Mon · Wed · Fri (already your days)'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('gen.describe.useDays')), findsNothing);

      await type(tester, 'tue and thu');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Days: Tue · Thu'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gen.describe.useDays')));
      await tester.pump();
      expect(profile.savedTrainingDays, [2, 4]);
      await tester.pump();
      expect(
        find.text('Days: Tue · Thu (already your days)'),
        findsOneWidget,
        reason: 'the saved days come back round as the ticked ones',
      );
    },
  );

  testWidgets('a failed Use these days says so and keeps the button', (
    tester,
  ) async {
    await pumpCard(tester, composed: '');
    profile.failTrainingDays = true;
    await type(tester, 'tue and thu');
    await tester.pump(kPhoneReadDelay);
    await tester.tap(find.byKey(const Key('gen.describe.useDays')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Could not save days.'), findsOneWidget);
    expect(find.byKey(const Key('gen.describe.useDays')), findsOneWidget);
  });

  testWidgets('a day count with days ticked says the picker sets it', (
    tester,
  ) async {
    await pumpCard(tester, composed: '');
    await type(tester, 'full body, 5 days a week');
    await tester.pump(kPhoneReadDelay);
    expect(find.textContaining('weekdays you have chosen'), findsOneWidget);
  });

  testWidgets('a day count with no days ticked asks for them', (tester) async {
    await pumpCard(tester, composed: '', trainingDays: const []);
    await type(tester, '4 days a week');
    await tester.pump(kPhoneReadDelay);
    expect(find.text('4 days a week: tick which days below'), findsOneWidget);
    expect(dayCounts, [4]);
  });

  testWidgets('a goal is named, not dropped', (tester) async {
    await pumpCard(tester, composed: '');
    await type(tester, 'I want to gain muscle');
    await tester.pump(kPhoneReadDelay);
    expect(find.text('Goals are set in your profile.'), findsOneWidget);
    expect(
      find.text("Nothing to change yet. Try: 'ppl, 45 min, protect my knee'."),
      findsNothing,
    );
  });

  testWidgets('nothing understood gives the example', (tester) async {
    await pumpCard(tester, composed: '');
    await type(tester, 'hello there');
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text("Nothing to change yet. Try: 'ppl, 45 min, protect my knee'."),
      findsOneWidget,
    );
  });

  testWidgets('the lines are one polite live region', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester, composed: '');
    await type(tester, 'ppl');
    await tester.pump(kPhoneReadDelay);
    final data = tester
        .getSemantics(find.byKey(const Key('gen.describe.lines')))
        .getSemanticsData();
    expect(data.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('its buttons fit at 2x text, $width dp', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCard(tester, composed: '');
      await type(tester, 'tue and thu, protect my right knee, ppl 50 min');
      await tester.pump(kPhoneReadDelay);
      expect(find.byKey(const Key('gen.describe.useDays')), findsOneWidget);
      expect(find.byKey(const Key('gen.describe.add.3')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('injury offers', () {
    testWidgets('a region the profile lacks is offered, not applied', (
      tester,
    ) async {
      await pumpCard(tester, composed: '');
      await type(tester, 'protect my right knee');
      await tester.pump(kPhoneReadDelay);
      expect(find.byKey(const Key('gen.describe.add.3')), findsOneWidget);
      expect(profile.savedInjuries, isNull);
    });

    testWidgets('the offer says what adding the region will do', (
      tester,
    ) async {
      await pumpCard(tester, composed: '');
      await type(tester, 'protect my right knee');
      await tester.pump(kPhoneReadDelay);
      expect(
        find.textContaining('every plan from now on will work around it.'),
        findsOneWidget,
      );
    });

    testWidgets('adding keeps the injuries the profile already had', (
      tester,
    ) async {
      await pumpCard(
        tester,
        composed: '',
        injuries: const [SelectedInjury(injuryId: 9)],
      );
      await type(tester, 'protect my right knee');
      await tester.pump(kPhoneReadDelay);
      await tester.tap(find.byKey(const Key('gen.describe.add.3')));
      await tester.pump();
      expect(profile.savedInjuries!.map((i) => i.injuryId), [9, 3]);
      expect(profile.savedInjuries!.last.side, 'right');
      expect(find.byKey(const Key('gen.describe.add.3')), findsNothing);
    });

    testWidgets('a region already in the profile is not offered again', (
      tester,
    ) async {
      await pumpCard(
        tester,
        composed: '',
        injuries: const [SelectedInjury(injuryId: 3, side: 'right')],
      );
      await type(tester, 'protect my right knee');
      await tester.pump(kPhoneReadDelay);
      expect(find.byKey(const Key('gen.describe.add.3')), findsNothing);
    });

    testWidgets('a failed add says so and keeps the offer', (tester) async {
      await pumpCard(tester, composed: '');
      profile.failInjuries = true;
      await type(tester, 'protect my right knee');
      await tester.pump(kPhoneReadDelay);
      await tester.tap(find.byKey(const Key('gen.describe.add.3')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Could not save that'), findsOneWidget);
      expect(find.byKey(const Key('gen.describe.add.3')), findsOneWidget);
    });

    testWidgets('an AI reading offers its regions the same way', (
      tester,
    ) async {
      await pumpCard(tester, composed: '');
      repo.nextReading = const WeekDescription(
        injuries: [SelectedInjury(injuryId: 9)],
        source: WeekSource.ai,
      );
      await type(tester, 'my back hurts a lot');
      await tester.pump(kAiReadDelay);
      await tester.pump();
      expect(find.byKey(const Key('gen.describe.add.9')), findsOneWidget);
    });

    testWidgets(
      'a catalogue that failed to load does not claim nothing matched',
      (tester) async {
        await pumpCard(
          tester,
          composed: '',
          options: const [],
          catalogueFailed: true,
        );
        await type(tester, 'protect my right knee');
        await tester.pump(kPhoneReadDelay);
        expect(
          find.descendant(
            of: find.byKey(const Key('gen.describe.catalogueError')),
            matching: find.byType(FsErrorLine),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('Nothing to change yet'),
          findsNothing,
          reason: 'the catalogue failure is the line to show',
        );
      },
    );
  });
}
