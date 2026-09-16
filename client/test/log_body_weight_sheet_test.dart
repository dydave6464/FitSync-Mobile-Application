import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
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
  final logged = <double>[];

  @override
  Future<Profile> load() async => _profile;

  @override
  Future<BodyWeightPoint> logBodyWeight(double weightKg) async {
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
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileRepositoryProvider.overrideWithValue(repo),
      bodyWeightProvider.overrideWith((ref, period) async {
        fetches.value += 1;
        return const BodyWeightSeries(
          widened: false, points: [], reference: null, unit: 'kg',
        );
      }),
    ],
    child: MaterialApp(
      theme: fsLightTheme(),
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          // Watching the same family entry the sheet invalidates gives
          // invalidate() something to actually refetch, the way the real
          // Progress screen (which also watches it) does.
          ref.watch(bodyWeightProvider('week'));
          return ElevatedButton(
            onPressed: () => showLogBodyWeightSheet(context, period: 'week'),
            child: const Text('open'),
          );
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('entering a weight and saving calls the repository and refreshes the card',
      (tester) async {
    final repo = FakeProfileRepository();
    final fetches = _FetchCount();
    await _pump(tester, repo: repo, fetches: fetches);
    expect(fetches.value, 1, reason: 'the screen behind the sheet already fetched once');

    await tester.enterText(find.byKey(const Key('bodyWeight.field')), '72.5');
    await tester.tap(find.byKey(const Key('bodyWeight.save')));
    await tester.pumpAndSettle();

    expect(repo.logged, [72.5]);
    expect(fetches.value, 2, reason: 'a save must invalidate the card\'s provider');
    expect(find.byKey(const Key('bodyWeight.save')), findsNothing,
        reason: 'a successful save closes the sheet');
  });

  testWidgets('a weight outside the server\'s bound gets a friendly message, not a request',
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
    expect(find.byKey(const Key('bodyWeight.save')), findsOneWidget,
        reason: 'a rejected entry leaves the sheet open to fix it');
  });
}
