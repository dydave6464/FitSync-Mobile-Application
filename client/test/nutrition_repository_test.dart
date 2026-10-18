import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/nutrition/data/nutrition_repository.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';

NutritionRepository _repo(MockClient client) => NutritionRepository(
  ApiClient(baseUrl: 'http://test.local', tokens: TokenStore(backing: InMemorySecureStore()), client: client),
);

http.Response _ok(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(jsonEncode({'data': data}), status);

const _food = {
  'id': null, 'source': 'fatsecret', 'externalId': 'fs-1', 'name': 'Mango Shake', 'servingDesc': '1 glass',
  'kcal': 250, 'proteinG': 4, 'carbsG': 50, 'fatG': 3.5,
};

void main() {
  test('getDay reads /nutrition/day?date=', () async {
    final repo = _repo(MockClient((r) async {
      expect(r.url.path, '/api/v1/nutrition/day');
      expect(r.url.queryParameters['date'], '2026-10-13');
      return _ok({'day': {
        'date': '2026-10-13', 'target': null, 'targetMissing': ['weightKg'],
        'totals': {'kcal': 0, 'proteinG': 0, 'carbsG': 0, 'fatG': 0},
        'meals': {'breakfast': [], 'lunch': [], 'dinner': [], 'snack': []},
      }});
    }));
    final day = await repo.getDay('2026-10-13');
    expect(day.targetMissing, ['weightKg']);
  });

  test("getDay with no date sends none, so the server picks its own today", () async {
    final repo = _repo(MockClient((r) async {
      expect(r.url.path, '/api/v1/nutrition/day');
      expect(r.url.queryParameters.containsKey('date'), isFalse);
      return _ok({'day': {
        'date': '2026-10-14', 'target': null, 'targetMissing': [],
        'totals': {'kcal': 0, 'proteinG': 0, 'carbsG': 0, 'fatG': 0},
        'meals': {'breakfast': [], 'lunch': [], 'dinner': [], 'snack': []},
      }});
    }));
    expect((await repo.getDay(null)).date, '2026-10-14');
  });

  test('logEntry POSTs date, meal, servings and the food ref', () async {
    final repo = _repo(MockClient((r) async {
      expect(r.method, 'POST');
      expect(r.url.path, '/api/v1/nutrition/entries');
      expect(jsonDecode(r.body), {
        'date': '2026-10-14', 'mealType': 'snack', 'servings': 1.5,
        'food': {'source': 'fatsecret', 'externalId': 'fs-1'},
      });
      return _ok({'entry': {
        'id': 9, 'mealType': 'snack', 'name': 'Mango Shake', 'servingDesc': '1 glass', 'servings': 1.5,
        'kcal': 375, 'proteinG': 6, 'carbsG': 75, 'fatG': 5.25, 'source': 'fatsecret', 'foodId': 4, 'externalId': 'fs-1',
      }}, 201);
    }));
    final entry = await repo.logEntry(date: '2026-10-14', mealType: 'snack', servings: 1.5, food: Food.fromJson(_food));
    expect(entry.id, 9);
  });

  test('updateEntry PATCHes meal and servings by id, with no food when the numbers stand', () async {
    final repo = _repo(MockClient((r) async {
      expect(r.method, 'PATCH');
      expect(r.url.path, '/api/v1/nutrition/entries/9');
      expect(jsonDecode(r.body), {'mealType': 'snack', 'servings': 2});
      return _ok({'entry': {
        'id': 9, 'mealType': 'snack', 'name': 'Mango Shake', 'servingDesc': '1 glass', 'servings': 2,
        'kcal': 500, 'proteinG': 8, 'carbsG': 100, 'fatG': 7, 'source': 'fatsecret', 'foodId': 4, 'externalId': 'fs-1',
      }});
    }));
    final entry = await repo.updateEntry(id: 9, mealType: 'snack', servings: 2);
    expect(entry.id, 9);
    expect(entry.mealType, 'snack');
    expect(entry.kcal, 500);
  });

  test("updateEntry sends the user's own numbers as the manual food map", () async {
    const manual = Food(
      source: 'manual', name: 'Chicken adobo', servingDesc: '1 cup',
      kcal: 224, proteinG: 26, carbsG: 3, fatG: 12, sugarG: 1, sodiumMg: 640,
    );
    final repo = _repo(MockClient((r) async {
      expect(r.method, 'PATCH');
      expect(r.url.path, '/api/v1/nutrition/entries/3');
      expect(jsonDecode(r.body), {
        'mealType': 'dinner', 'servings': 1.5,
        'food': {
          'source': 'manual', 'name': 'Chicken adobo', 'servingDesc': '1 cup',
          'proteinG': 26, 'carbsG': 3, 'fatG': 12, 'sugarG': 1, 'sodiumMg': 640,
        },
      });
      return _ok({'entry': {
        'id': 3, 'mealType': 'dinner', 'name': 'Chicken adobo', 'servingDesc': '1 cup', 'servings': 1.5,
        'kcal': 336, 'proteinG': 39, 'carbsG': 4.5, 'fatG': 18, 'sugarG': 1.5, 'sodiumMg': 960,
        'source': 'manual', 'foodId': null, 'externalId': null,
      }});
    }));
    final entry = await repo.updateEntry(id: 3, mealType: 'dinner', servings: 1.5, food: manual);
    expect(entry.source, 'manual');
    expect(entry.sodiumMg, 960);
  });

  test('deleteEntry DELETEs by id', () async {
    final repo = _repo(MockClient((r) async {
      expect(r.method, 'DELETE');
      expect(r.url.path, '/api/v1/nutrition/entries/9');
      return _ok({'deleted': true});
    }));
    await repo.deleteEntry(9);
  });

  test('search and recent read food lists', () async {
    final repo = _repo(MockClient((r) async {
      if (r.url.path == '/api/v1/foods/search') {
        expect(r.url.queryParameters['q'], 'mango');
        return _ok({'foods': [_food], 'fatsecretUnavailable': false});
      }
      expect(r.url.path, '/api/v1/foods/recent');
      return _ok({'foods': [_food]});
    }));
    final found = await repo.search('mango');
    expect(found.foods.single.isFatsecret, isTrue);
    expect(found.fatsecretUnavailable, isFalse);
    expect((await repo.recent()).single.name, 'Mango Shake');
  });

  test('getDay parses fiberG on an entry, the totals and the target', () async {
    final repo = _repo(MockClient((r) async {
      return _ok({'day': {
        'date': '2026-10-14',
        'target': {'kcal': 1850, 'proteinG': 95, 'carbsG': 253, 'fatG': 51, 'fiberG': 26},
        'targetMissing': <String>[],
        'totals': {'kcal': 640, 'proteinG': 56, 'carbsG': 8, 'fatG': 42, 'fiberG': 6.5},
        'meals': {'breakfast': [], 'lunch': [{
          'id': 1, 'mealType': 'lunch', 'name': 'Chicken adobo', 'servingDesc': '1 serving',
          'servings': 2, 'kcal': 640, 'proteinG': 56, 'carbsG': 8, 'fatG': 42, 'fiberG': 6.5,
          'source': 'local', 'foodId': 7, 'externalId': null,
        }], 'dinner': [], 'snack': []},
      }});
    }));
    final day = await repo.getDay('2026-10-14');
    expect(day.target!.fiberG, 26);
    expect(day.totals.fiberG, 6.5);
    expect(day.meals['lunch']!.single.fiberG, 6.5);
  });

  test('getDay parses sugarG and sodiumMg on an entry and the totals', () async {
    final repo = _repo(MockClient((r) async {
      return _ok({'day': {
        'date': '2026-10-14',
        'target': {'kcal': 1850, 'proteinG': 95, 'carbsG': 253, 'fatG': 51},
        'targetMissing': <String>[],
        'totals': {'kcal': 640, 'proteinG': 56, 'carbsG': 8, 'fatG': 42, 'sugarG': 9.7, 'sodiumMg': 124},
        'meals': {'breakfast': [], 'lunch': [{
          'id': 1, 'mealType': 'lunch', 'name': 'Chicken adobo', 'servingDesc': '1 serving',
          'servings': 2, 'kcal': 640, 'proteinG': 56, 'carbsG': 8, 'fatG': 42, 'sugarG': 9.7, 'sodiumMg': 124,
          'source': 'local', 'foodId': 7, 'externalId': null,
        }], 'dinner': [], 'snack': []},
      }});
    }));
    final day = await repo.getDay('2026-10-14');
    expect(day.totals.sugarG, 9.7);
    expect(day.totals.sodiumMg, 124);
    expect(day.meals['lunch']!.single.sugarG, 9.7);
    expect(day.meals['lunch']!.single.sodiumMg, 124);
  });

  test('fatsecretFood reads one FatSecret food\'s detailed serving', () async {
    final repo = _repo(MockClient((r) async {
      expect(r.method, 'GET');
      expect(r.url.path, '/api/v1/foods/fatsecret/fs-1');
      return _ok({'food': {..._food, 'servingDesc': '1 thigh', 'kcal': 107}});
    }));
    final food = await repo.fatsecretFood('fs-1');
    expect(food.servingDesc, '1 thigh');
    expect(food.kcal, 107);
    expect(food.isFatsecret, isTrue);
  });
}
