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

  /// While following today it sends no date, and the server's answer says
  /// which day today is; logs then use that day's date.
  @override
  Future<NutritionDay> build() => _repo.getDay(ref.watch(nutritionDateProvider));

  /// Saves to [date], or to the day on screen. The entry shows at once if
  /// that day is the one on screen. If the save fails, it comes back out and
  /// this rethrows, so the caller can say so. With no [date] and no day
  /// loaded there is nowhere to save, which throws a [StateError]. Returns
  /// the saved entry, so the caller can offer to change it.
  Future<FoodEntry> log(Food food, {required String mealType, required double servings, String? date}) async {
    final target = date ?? state.value?.date;
    if (target == null) throw StateError('No day is loaded to log to.');
    final pending = FoodEntry.pending(id: --_pendingIds, food: food, mealType: mealType, servings: servings);
    _onDay(target, (day) => day.withEntry(pending));
    final FoodEntry saved;
    try {
      saved = await _repo.logEntry(date: target, mealType: mealType, servings: servings, food: food);
    } catch (_) {
      _onDay(target, (day) => day.without(pending.id));
      rethrow;
    }
    // The real entry, so it can be deleted even if the refetch below fails.
    _onDay(target, (day) => day.without(pending.id).withEntry(saved));
    ref.invalidate(recentFoodsProvider);
    await _settle(target);
    return saved;
  }

  /// Saves a new meal, servings or -- as [edited], per serving -- numbers
  /// for [entry], on [date] (its own day) or the day on screen. Not
  /// optimistic: the day changes only once the server agrees, so a failure
  /// leaves it as it was and rethrows. (Named so because AsyncNotifier
  /// already has an `update`.)
  Future<void> change(FoodEntry entry, {required String mealType, required double servings, Food? edited, String? date}) async {
    final target = date ?? state.value?.date;
    if (target == null) throw StateError('No day is loaded to change.');
    final saved = await _repo.updateEntry(id: entry.id, mealType: mealType, servings: servings, food: edited);
    // Out and back in, so a new meal moves it.
    _onDay(target, (day) => day.without(entry.id).withEntry(saved));
    ref.invalidate(recentFoodsProvider);
    await _settle(target);
  }

  /// Hides the entry at once. If the delete fails, puts it back -- on its own
  /// day only, if the user has moved on -- and rethrows.
  Future<void> remove(FoodEntry entry) async {
    final date = state.value?.date;
    if (date == null) throw StateError('No day is loaded to remove from.');
    _onDay(date, (day) => day.without(entry.id));
    try {
      await _repo.deleteEntry(entry.id);
    } catch (_) {
      _onDay(date, (day) => day.withEntry(entry));
      rethrow;
    }
    ref.invalidate(recentFoodsProvider);
    await _settle(date);
  }

  /// Applies [change] to the day on screen if it is [date]'s; otherwise the
  /// write belongs to a day the user has left, and this leaves the screen be.
  void _onDay(String date, NutritionDay Function(NutritionDay day) change) {
    final day = state.value;
    if (day != null && day.date == date) state = AsyncData(change(day));
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
