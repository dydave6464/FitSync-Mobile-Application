import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/units.dart';
import 'package:fitsync/features/nutrition/presentation/providers.dart';
import 'package:fitsync/features/profile/data/profile_repository.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

import 'nutrition_controller_test.dart' show FakeNutritionRepository;

/// A profile with both figures the body-weight card is drawn from, so a test
/// can change one and leave the other alone.
Profile _profileWith({
  double? weightKg = 86,
  double? goalWeightKg = 92,
  WeightUnit weightUnit = WeightUnit.kg,
}) => Profile(
  userId: 7,
  email: 'juan@example.com',
  fullName: 'Juan Dela Cruz',
  onboardingCompleted: true,
  isPremium: false,
  notificationsEnabled: true,
  equipment: const [],
  injuries: const [],
  weightKg: weightKg,
  goalWeightKg: goalWeightKg,
  weightUnit: weightUnit,
);

class _FakeRepo implements ProfileRepository {
  /// Every bodyWeight() call in order, so a test can count the fetches for a
  /// period rather than only see that one happened at some point.
  final List<String> fetches = [];

  Profile current = _profileWith();

  @override
  Future<Profile> load() async => current;

  @override
  Future<Profile> patch(Map<String, dynamic> fields) async {
    current = _profileWith(
      weightKg: fields.containsKey('weightKg')
          ? fields['weightKg'] as double?
          : current.weightKg,
      goalWeightKg: fields.containsKey('goalWeightKg')
          ? fields['goalWeightKg'] as double?
          : current.goalWeightKg,
      weightUnit: fields['weightUnit'] == 'lb'
          ? WeightUnit.lb
          : current.weightUnit,
    );
    return current;
  }

  @override
  Future<Profile> setGoals(List<String> goals, String mainGoal) async => current;

  @override
  Future<BodyWeightSeries> bodyWeight(String period) async {
    fetches.add(period);
    return BodyWeightSeries(
      widened: false,
      points: const [],
      // The dashed line the Progress chart draws, read by the server from
      // users.goal_weight_kg -- the figure this whole test file is about.
      reference: BodyWeightReference(
        kind: 'goal',
        weightKg: current.goalWeightKg ?? 0,
      ),
      unit: 'kg',
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// A container with the repository faked, plus the body-weight card already
/// on screen for [periods] -- nothing goes stale that was never read.
Future<(ProviderContainer, _FakeRepo)> _open({
  List<String> periods = const ['month'],
}) async {
  final repo = _FakeRepo();
  final container = ProviderContainer(
    overrides: [profileRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);

  // Listened, not just read: an unlistened FutureProvider is disposed as soon
  // as the read returns, so it would refetch on the next read whether or not
  // anything invalidated it -- and every test here would pass vacuously.
  for (final period in periods) {
    container.listen(bodyWeightProvider(period), (_, _) {});
    await container.read(bodyWeightProvider(period).future);
  }
  await container.read(profileProvider.future);
  return (container, repo);
}

void main() {
  test('a new goal weight refetches the body-weight card', () async {
    final (container, repo) = await _open();
    expect(repo.fetches, ['month']);

    await container.read(profileProvider.notifier).patch({
      'goalWeightKg': 80.0,
    });
    await container.read(bodyWeightProvider('month').future);

    // The Progress tab reads its goal line from the server's response, not
    // from the profile, so the patch alone cannot move it.
    expect(repo.fetches, ['month', 'month']);
    final series = container.read(bodyWeightProvider('month')).value;
    expect(series!.reference!.weightKg, 80);
  });

  test('a new weight refetches the body-weight card', () async {
    final (container, repo) = await _open();

    // The server writes a body_weight_logs row for a changed weight, so the
    // series has a point the cached copy cannot know about.
    await container.read(profileProvider.notifier).patch({'weightKg': 84.0});
    await container.read(bodyWeightProvider('month').future);

    expect(repo.fetches, ['month', 'month']);
  });

  test('a patch that touches neither figure refetches nothing', () async {
    final (container, repo) = await _open();

    await container.read(profileProvider.notifier).patch({
      'notificationsEnabled': false,
    });
    await container.read(bodyWeightProvider('month').future);

    expect(repo.fetches, ['month']);
  });

  test('every period is refetched, not just the one on screen', () async {
    final (container, repo) = await _open(periods: ['week', 'month', 'year']);
    expect(repo.fetches, ['week', 'month', 'year']);

    await container.read(profileProvider.notifier).patch({
      'goalWeightKg': 80.0,
    });
    for (final period in ['week', 'month', 'year']) {
      await container.read(bodyWeightProvider(period).future);
    }

    // A goal is not per-period: leaving the other segments cached shows the
    // old line the moment the user switches to one they had already opened.
    expect(repo.fetches, ['week', 'month', 'year', 'week', 'month', 'year']);
  });

  test('a weight-unit change reaches the app without a refetch', () async {
    final (container, repo) = await _open();

    await container.read(profileProvider.notifier).patch({'weightUnit': 'lb'});

    // The other way profile edits propagate, and the reason this fix is not
    // simply "invalidate everything": weightUnitProvider derives from
    // profileProvider, so every weight on screen re-renders from the state
    // the patch just set. The card's figures are kilograms either way, so
    // there is nothing to refetch -- and a refetch here would be a
    // round trip bought for no change at all.
    expect(container.read(weightUnitProvider), WeightUnit.lb);
    expect(repo.fetches, ['month']);
  });

  group("today's target and the meal suggestions", () {
    /// The profile, plus the Nutrition tab's day and lunch suggestions
    /// already on screen (listened, for the reason [_open] gives).
    Future<(ProviderContainer, FakeNutritionRepository)> openNutrition() async {
      final nutrition = FakeNutritionRepository();
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWithValue(_FakeRepo()),
          nutritionRepositoryProvider.overrideWithValue(nutrition),
        ],
      );
      addTearDown(container.dispose);
      container.listen(nutritionDayProvider, (_, _) {});
      container.listen(mealSuggestionsProvider('lunch'), (_, _) {});
      await container.read(nutritionDayProvider.future);
      await container.read(mealSuggestionsProvider('lunch').future);
      await container.read(profileProvider.future);
      return (container, nutrition);
    }

    Future<(int, int)> fetchesAfter(ProviderContainer container, FakeNutritionRepository nutrition) async {
      await container.read(nutritionDayProvider.future);
      await container.read(mealSuggestionsProvider('lunch').future);
      return (nutrition.calls.where((c) => c.startsWith('get ')).length, nutrition.suggestionCalls.length);
    }

    // The server works the target out from these (nutrition-target.js), so
    // a change to any of them leaves the ring and "Fits the ~... left" wrong.
    for (final field in <String, Object>{
      'weightKg': 84.0,
      'heightCm': 170.0,
      'dateOfBirth': '1999-05-01',
      'sex': 'female',
      'activityLevel': 'active',
    }.entries) {
      test('a new ${field.key} refetches both', () async {
        final (container, nutrition) = await openNutrition();
        expect(await fetchesAfter(container, nutrition), (1, 1));

        await container.read(profileProvider.notifier).patch({field.key: field.value});

        expect(await fetchesAfter(container, nutrition), (2, 2));
      });
    }

    test('a new main goal refetches both', () async {
      final (container, nutrition) = await openNutrition();
      await container.read(profileProvider.notifier).setGoals(['lose_weight'], 'lose_weight');
      expect(await fetchesAfter(container, nutrition), (2, 2));
    });

    for (final field in <String, Object>{
      'notificationsEnabled': false,
      'goalWeightKg': 80.0,
      'weightUnit': 'lb',
    }.entries) {
      test('${field.key} refetches neither', () async {
        final (container, nutrition) = await openNutrition();
        await container.read(profileProvider.notifier).patch({field.key: field.value});
        expect(await fetchesAfter(container, nutrition), (1, 1));
      });
    }

    test('a new usual rice refetches the suggestions, not the day', () async {
      final (container, nutrition) = await openNutrition();
      await container.read(profileProvider.notifier).patch({'usualRiceCups': 1.5});
      expect(await fetchesAfter(container, nutrition), (1, 2));
    });
  });
}
