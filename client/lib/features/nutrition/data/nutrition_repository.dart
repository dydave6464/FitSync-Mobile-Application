import '../../../core/api_client.dart';
import '../domain/nutrition.dart';

/// The food log: /nutrition for days and entries, /foods for finding foods.
class NutritionRepository {
  NutritionRepository(this._api);

  final ApiClient _api;

  /// A null [date] sends none, and the server answers with its own today: a
  /// phone clock a little ahead near midnight would otherwise ask for a day
  /// the server still calls the future.
  Future<NutritionDay> getDay(String? date) async {
    final data = await _api.getJson('/api/v1/nutrition/day', query: {'date': ?date});
    return NutritionDay.fromJson(data['day'] as Map<String, dynamic>);
  }

  Future<FoodEntry> logEntry({
    required String date,
    required String mealType,
    required double servings,
    required Food food,
  }) async {
    final data = await _api.postJson('/api/v1/nutrition/entries', {
      'date': date,
      'mealType': mealType,
      'servings': servings,
      'food': food.toRef(),
    });
    return FoodEntry.fromJson(data['entry'] as Map<String, dynamic>);
  }

  Future<void> deleteEntry(int id) async {
    await _api.deleteJson('/api/v1/nutrition/entries/$id');
  }

  Future<FoodSearchResult> search(String q) async {
    final data = await _api.getJson('/api/v1/foods/search', query: {'q': q});
    return FoodSearchResult(
      foods: _foods(data),
      fatsecretUnavailable: data['fatsecretUnavailable'] == true,
    );
  }

  Future<List<Food>> recent() async => _foods(await _api.getJson('/api/v1/foods/recent'));

  List<Food> _foods(Map<String, dynamic> data) =>
      [for (final f in data['foods'] as List) Food.fromJson(f as Map<String, dynamic>)];
}
