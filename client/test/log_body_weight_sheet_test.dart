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
  Future<BodyWeightPoint> logBodyWeight(double weightKg) async {
    if (logError != null) throw logError!;
    logged.add(weightKg);
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

Future<void> _pump(
  WidgetTester tester, {
  required FakeProfileRepository repo,
  required _FetchCount fetches,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
