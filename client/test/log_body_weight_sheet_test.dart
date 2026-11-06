import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/profile/presentation/widgets/log_body_weight_sheet.dart';

const _profile = Profile(
  userId: 1,
  email: 'a@b.c',
  fullName: 'A',
  onboardingCompleted: true,
  isPremium: false,
  notificationsEnabled: true,
  equipment: [],
  injuries: [],
);

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.logError});

  /// Thrown by [logBodyWeight] instead of saving, when set.
  final Object? logError;

  final logged = <double>[];

  /// The day each save was for; null for today (the server's own day).
  final loggedOn = <String?>[];

  /// How many times [load] has been called -- starts at 0, since unlike
  /// [bodyWeightProvider] nothing in `_pump` eagerly watches [profileProvider]
  /// before the sheet opens.
  int loads = 0;

  @override
  Future<Profile> load() async {
    loads += 1;
    return _profile;
  }

  @override
  Future<BodyWeightPoint> logBodyWeight(
    double weightKg, {
    String? loggedOn,
  }) async {
    if (logError != null) throw logError!;
    logged.add(weightKg);
    this.loggedOn.add(loggedOn);
    return BodyWeightPoint(loggedOn: '2026-09-16', weightKg: weightKg);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// How many times the family entry the sheet targets has been fetched.
/// Starts at 1 (the screen behind the sheet already watches it), so a
/// successful save must bring it to 2.
class _FetchCount {
  int value = 0;
}

/// Noon on 6 Nov 2026 in Manila.
final _noonNov6 = DateTime.utc(2026, 11, 6, 4);

Future<void> _pump(
  WidgetTester tester, {
  required FakeProfileRepository repo,
  required _FetchCount fetches,
  DateTime? now,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bodyWeightClockProvider.overrideWithValue(() => now ?? _noonNov6),
        profileRepositoryProvider.overrideWithValue(repo),
        bodyWeightProvider.overrideWith((ref, period) async {
          fetches.value += 1;
          return const BodyWeightSeries(
            widened: false,
            points: [],
            reference: null,
            unit: 'kg',
          );
        }),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // Watching the same family entry the sheet invalidates gives
              // invalidate() something to actually refetch, the way the real
              // Progress screen (which also watches it) does.
              ref.watch(bodyWeightProvider('week'));
              return ElevatedButton(
                onPressed: () => showLogBodyWeightSheet(context),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  // PS-10: the sheet's only escape control was announced as a bare "Button".
  testWidgets('the close button is named Close for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, repo: FakeProfileRepository(), fetches: _FetchCount());

    expect(
      tester.getSemantics(find.byKey(const Key('bodyWeight.close'))),
      matchesSemantics(
        tooltip: 'Close',
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets(
    'entering a weight and saving calls the repository and refreshes the card',
    (tester) async {
      final repo = FakeProfileRepository();
      final fetches = _FetchCount();
      await _pump(tester, repo: repo, fetches: fetches);
      expect(
        fetches.value,
        1,
        reason: 'the screen behind the sheet already fetched once',
      );

      await tester.enterText(find.byKey(const Key('bodyWeight.field')), '72.5');
      await tester.tap(find.byKey(const Key('bodyWeight.save')));
      await tester.pumpAndSettle();

      expect(repo.logged, [72.5]);
      expect(
        fetches.value,
        2,
        reason: 'a save must invalidate the card\'s provider',
      );
      expect(
        find.byKey(const Key('bodyWeight.save')),
        findsNothing,
        reason: 'a successful save closes the sheet',
      );
    },
  );

  testWidgets(
    'a weight outside the server\'s bound gets a friendly message, not a request',
    (tester) async {
      final repo = FakeProfileRepository();
      final fetches = _FetchCount();
      await _pump(tester, repo: repo, fetches: fetches);

      await tester.enterText(find.byKey(const Key('bodyWeight.field')), '600');
      await tester.tap(find.byKey(const Key('bodyWeight.save')));
      await tester.pumpAndSettle();

      expect(repo.logged, isEmpty);
      expect(find.byKey(const Key('bodyWeight.error')), findsOneWidget);
      expect(find.textContaining('between'), findsOneWidget);
      expect(
        find.byKey(const Key('bodyWeight.save')),
        findsOneWidget,
        reason: 'a rejected entry leaves the sheet open to fix it',
      );
    },
  );

  testWidgets(
    'a successful save also refreshes the profile, not just the card',
    (tester) async {
      // The server syncs users.weight_kg from the newest weigh-in (see
      // writeEntry in server/src/db/body-weight.js), so Profile and Settings --
      // both backed by profileProvider -- must refetch too, or they keep
      // showing the pre-save weight for the rest of the session.
      final repo = FakeProfileRepository();
      final fetches = _FetchCount();
      await _pump(tester, repo: repo, fetches: fetches);
      expect(
        repo.loads,
        1,
        reason: 'the sheet itself already reads the unit off the profile',
      );

      await tester.enterText(find.byKey(const Key('bodyWeight.field')), '72.5');
      await tester.tap(find.byKey(const Key('bodyWeight.save')));
      await tester.pumpAndSettle();

      expect(
        repo.loads,
        2,
        reason: 'a save must invalidate profileProvider too',
      );
    },
  );

  // Month and Year hold the new weigh-in too: refreshing only the period on
  // screen left them showing the old weight and the old change.
  testWidgets('a save refreshes every period, not just the one on screen', (
    tester,
  ) async {
    final repo = FakeProfileRepository();
    final fetches = <String, int>{};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(repo),
          bodyWeightProvider.overrideWith((ref, period) async {
            fetches[period] = (fetches[period] ?? 0) + 1;
            return const BodyWeightSeries(
              widened: false,
              points: [],
              reference: null,
              unit: 'kg',
            );
          }),
        ],
        child: MaterialApp(
          theme: fsLightTheme(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(bodyWeightProvider('week'));
                ref.watch(bodyWeightProvider('month'));
                return ElevatedButton(
                  onPressed: () => showLogBodyWeightSheet(context),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bodyWeight.field')), '72.5');
    await tester.tap(find.byKey(const Key('bodyWeight.save')));
    await tester.pumpAndSettle();

    expect(fetches, {'week': 2, 'month': 2});
  });

  // L-85: a weight the sheet turns down is flagged on its card too, as the
  // About step flags one; a failed request is not the number's fault.
  group('the weight card is flagged only for a number to fix', () {
    bool flagged(WidgetTester tester) =>
        tester.widget<FsStatField>(find.byType(FsStatField)).error;

    testWidgets('empty', (tester) async {
      await _pump(
        tester,
        repo: FakeProfileRepository(),
        fetches: _FetchCount(),
      );
      expect(flagged(tester), isFalse);
      await tester.tap(find.byKey(const Key('bodyWeight.save')));
      await tester.pumpAndSettle();
      expect(flagged(tester), isTrue);

      await tester.enterText(find.byKey(const Key('bodyWeight.field')), '7');
      await tester.pump();
      expect(flagged(tester), isFalse, reason: 'cleared once it is changed');
    });

    testWidgets('out of range', (tester) async {
      await _pump(
        tester,
        repo: FakeProfileRepository(),
        fetches: _FetchCount(),
      );
      await tester.enterText(find.byKey(const Key('bodyWeight.field')), '600');
      await tester.tap(find.byKey(const Key('bodyWeight.save')));
      await tester.pumpAndSettle();
      expect(flagged(tester), isTrue);
    });

    testWidgets('not for a failed request', (tester) async {
      await _pump(
        tester,
        repo: FakeProfileRepository(
          logError: const ApiException('NETWORK_ERROR', 'offline'),
        ),
        fetches: _FetchCount(),
      );
      await tester.enterText(find.byKey(const Key('bodyWeight.field')), '72');
      await tester.tap(find.byKey(const Key('bodyWeight.save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bodyWeight.error')), findsOneWidget);
      expect(flagged(tester), isFalse);
    });
  });

  // PS-20: weigh-ins could only be for today, and nothing said a second one
  // today replaces the first.
  group('the day a weigh-in is for', () {
    String dateShown(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('bodyWeight.date')),
            matching: find.byKey(const Key('bodyWeight.dateText')),
          ),
        )
        .data!;

    testWidgets('is today unless picked, and says today is replaced', (
      tester,
    ) async {
      final repo = FakeProfileRepository();
      await _pump(tester, repo: repo, fetches: _FetchCount());
      expect(dateShown(tester), 'Today');
      expect(
        find.text("Logging again today replaces today's entry."),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('bodyWeight.field')), '72');
      await tester.tap(find.byKey(const Key('bodyWeight.save')));
      await tester.pumpAndSettle();
      expect(repo.loggedOn, [null], reason: "today is the server's own day");
    });

    testWidgets('a past day can be picked, and is sent', (tester) async {
      final repo = FakeProfileRepository();
      await _pump(tester, repo: repo, fetches: _FetchCount());

      await tester.tap(find.byKey(const Key('bodyWeight.date')));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.lastDate, DateTime(2026, 11, 6), reason: 'no future day');
      expect(picker.firstDate, DateTime(2025, 11, 6));
      await tester.tap(find.text('4'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(dateShown(tester), 'Wed, Nov 4');
      expect(
        find.text('Logging again for this day replaces its entry.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('bodyWeight.field')), '72');
      await tester.tap(find.byKey(const Key('bodyWeight.save')));
      await tester.pumpAndSettle();
      expect(repo.loggedOn, ['2026-11-04']);
    });

    testWidgets('yesterday is said as Yesterday', (tester) async {
      await _pump(
        tester,
        repo: FakeProfileRepository(),
        fetches: _FetchCount(),
      );
      await tester.tap(find.byKey(const Key('bodyWeight.date')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dateShown(tester), 'Yesterday');
    });

    testWidgets('a day in another year carries its year after a comma', (
      tester,
    ) async {
      // P-2: it read 'Wed, Dec 31 2025', with no comma before the year.
      await _pump(
        tester,
        repo: FakeProfileRepository(),
        fetches: _FetchCount(),
        now: DateTime.utc(2026, 1, 2, 4),
      );
      await tester.tap(find.byKey(const Key('bodyWeight.date')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('31'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dateShown(tester), 'Wed, Dec 31, 2025');
    });

    testWidgets("today is Manila's, as the server counts it", (tester) async {
      // 01:00 on 6 Nov in Manila, still 5 Nov in UTC.
      await _pump(
        tester,
        repo: FakeProfileRepository(),
        fetches: _FetchCount(),
        now: DateTime.utc(2026, 11, 5, 17),
      );
      await tester.tap(find.byKey(const Key('bodyWeight.date')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).lastDate,
        DateTime(2026, 11, 6),
      );
    });

    testWidgets('the date is one button, named for what it sets', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        repo: FakeProfileRepository(),
        fetches: _FetchCount(),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('bodyWeight.date'))),
        isSemantics(
          label: 'Date',
          value: 'Today',
          hint: 'Opens a date picker',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('fits a small phone at 2x text', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        repo: FakeProfileRepository(),
        fetches: _FetchCount(),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('bodyWeight.save')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  // PS-6 / PS-3: a failed save showed the client's transport text (an
  // address, an adb command, "HTTP 502") as a plain red line no screen
  // reader announced.
  testWidgets('a failed save says so in plain words, announced', (
    tester,
  ) async {
    final repo = FakeProfileRepository(
      logError: const ApiException(
        'INVALID_RESPONSE',
        'Server returned a non-JSON body (HTTP 502).',
      ),
    );
    await _pump(tester, repo: repo, fetches: _FetchCount());

    await tester.enterText(find.byKey(const Key('bodyWeight.field')), '72.5');
    await tester.tap(find.byKey(const Key('bodyWeight.save')));
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong on our side. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('HTTP'), findsNothing);
    expect(find.textContaining('adb'), findsNothing);
    final error = find.byKey(const Key('bodyWeight.error'));
    expect(error, findsOneWidget);
    expect(
      find.descendant(
        of: error,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
      reason: 'the error must be announced when it appears',
    );
  });
}
