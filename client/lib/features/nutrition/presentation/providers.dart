import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/manila_day.dart';
import '../../exercises/presentation/providers.dart' show apiClientProvider, apiRetryPolicy;
import '../data/nutrition_repository.dart';
import '../domain/nutrition.dart';

final nutritionRepositoryProvider = Provider<NutritionRepository>(
  (ref) => NutritionRepository(ref.watch(apiClientProvider)),
);

/// Injectable for tests.
final nutritionClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

String nutritionToday(Ref ref) => manilaDayOf(ref.read(nutritionClockProvider)());

String _shiftDate(String date, int days) {
  final d = DateTime.parse('${date}T00:00:00Z').add(Duration(days: days));
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${pad(d.month)}-${pad(d.day)}';
}

/// The day the Nutrition tab shows. Null means "today", and keeps meaning it
/// across midnight; a past day is held as its date.
final nutritionDateProvider = NotifierProvider<NutritionDateController, String?>(
  NutritionDateController.new,
);

class NutritionDateController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? date) => state = date;

  /// Moves by [days]; never past today, and landing on today stores null.
  void shift(int days) {
    final today = nutritionToday(ref);
    final next = _shiftDate(state ?? today, days);
    state = next.compareTo(today) >= 0 ? null : next;
  }
}

/// Not autoDispose -- the Nutrition tab stays mounted once visited -- so it is
/// on sign-out's list of per-user caches.
final nutritionDayProvider = AsyncNotifierProvider<NutritionDayController, NutritionDay>(
  NutritionDayController.new,
  retry: apiRetryPolicy,
);

class NutritionDayController extends AsyncNotifier<NutritionDay> {
  int _pendingIds = 0;

  NutritionRepository get _repo => ref.read(nutritionRepositoryProvider);

  @override
  Future<NutritionDay> build() {
    final date = ref.watch(nutritionDateProvider) ?? nutritionToday(ref);
    return _repo.getDay(date);
  }

  /// Shows the entry at once. If the save fails, takes it back out and
  /// rethrows, so the caller can say so.
  Future<void> log(Food food, {required String mealType, required double servings}) async {
    final day = state.value;
    if (day == null) return;
    final pending = FoodEntry.pending(id: --_pendingIds, food: food, mealType: mealType, servings: servings);
    state = AsyncData(day.withEntry(pending));
    try {
      await _repo.logEntry(date: day.date, mealType: mealType, servings: servings, food: food);
    } catch (_) {
      final now = state.value;
      if (now != null) state = AsyncData(now.without(pending.id));
      rethrow;
    }
    ref.invalidate(recentFoodsProvider);
    await _settle(day.date);
  }

  /// Hides the entry at once. If the delete fails, puts it back and rethrows.
  Future<void> remove(FoodEntry entry) async {
    final day = state.value;
    if (day == null) return;
    state = AsyncData(day.without(entry.id));
    try {
      await _repo.deleteEntry(entry.id);
    } catch (_) {
      final now = state.value;
      if (now != null) state = AsyncData(now.withEntry(entry));
      rethrow;
    }
    await _settle(day.date);
  }

  /// Replaces the optimistic day with the server's, if the user is still on
  /// it. A failure here keeps the optimistic day; the next open refetches.
  Future<void> _settle(String date) async {
    try {
      final fresh = await _repo.getDay(date);
      if (state.value?.date == date) state = AsyncData(fresh);
    } catch (_) {}
  }
}

final recentFoodsProvider = FutureProvider.autoDispose<List<Food>>(
  (ref) => ref.watch(nutritionRepositoryProvider).recent(),
);

/// Keyed by the (already debounced, trimmed) query; Log food debounces.
final foodSearchProvider = FutureProvider.autoDispose.family<FoodSearchResult, String>(
  (ref, q) => ref.watch(nutritionRepositoryProvider).search(q),
);
