import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/nutrition/domain/meal_photo.dart';
import 'package:fitsync/features/nutrition/domain/nutrition.dart';

Map<String, dynamic> _food(
  int id,
  String name, {
  bool fs = false,
  num kcal = 206,
}) => {
  'id': id,
  'name': name,
  'servingDesc': '1 cup (160 g)',
  'fromFatsecret': fs,
  'perServing': {
    'kcal': kcal,
    'proteinG': 3.4,
    'carbsG': 47.5,
    'fatG': 0.3,
    'fiberG': 0.6,
    'sugarG': null,
    'sodiumMg': 2,
  },
};

final _answer = {
  'recognitionId': 7,
  'remainingToday': 12,
  'items': [
    {
      'itemId': 40,
      'confidence': 0.9,
      'servings': 1.5,
      'food': _food(1, 'White rice'),
      'alternatives': [
        _food(2, 'Garlic fried rice (sinangag)', kcal: 299),
        _food(3, 'Mango Shake', fs: true, kcal: 250),
      ],
    },
    {
      'itemId': 41,
      'confidence': null,
      'servings': 1,
      'food': _food(4, 'Chicken adobo', kcal: 320),
      'alternatives': [],
    },
  ],
  'unlisted': [
    {'itemId': 42, 'name': 'Atchara (pickled papaya)'},
  ],
};

const _rice = Food(
  source: 'local',
  id: 1,
  name: 'White rice',
  servingDesc: '1 cup (160 g)',
  kcal: 206,
  proteinG: 3.4,
  carbsG: 47.5,
  fatG: 0.3,
);
const _garlic = Food(
  source: 'local',
  id: 2,
  name: 'Garlic fried rice (sinangag)',
  kcal: 299,
  proteinG: 4.2,
  carbsG: 56.3,
  fatG: 6.4,
);
const _tinola = Food(
  source: 'local',
  id: 5,
  name: 'Tinola',
  kcal: 180,
  proteinG: 20,
  carbsG: 6,
  fatG: 8,
);
const _shake = Food(
  source: 'fatsecret',
  externalId: 'fs-1',
  name: 'Mango Shake',
  kcal: 250,
  proteinG: 4,
  carbsG: 50,
  fatG: 3.5,
);

void main() {
  test('sniffImageType reads the first bytes, not the file name', () {
    expect(
      sniffImageType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0])),
      'image/jpeg',
    );
    expect(
      sniffImageType(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]),
      ),
      'image/png',
    );
    expect(
      sniffImageType(
        Uint8List.fromList([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70]),
      ),
      isNull,
      reason: 'HEIC',
    );
    expect(sniffImageType(Uint8List.fromList([0xFF, 0xD8])), isNull);
  });

  test('a recognition answer parses into foods that log by id', () {
    final r = PhotoRecognition.fromJson(_answer);
    expect([r.recognitionId, r.remainingToday, r.isEmpty], [7, 12, false]);
    final first = r.items.first;
    expect([first.itemId, first.confidence, first.servings], [40, 0.9, 1.5]);
    expect(first.food.source, 'local');
    expect(first.food.id, 1);
    expect(first.food.kcal, 206);
    expect(first.food.sugarG, isNull);
    expect(first.food.toRef(), {'source': 'local', 'id': 1});
    expect(first.alternatives.map((f) => f.name), [
      'Garlic fried rice (sinangag)',
      'Mango Shake',
    ]);
    expect(first.alternatives.last.fatsecretCopy, isTrue);
    expect(first.alternatives.last.showsFatsecret, isTrue);
    expect(first.food.showsFatsecret, isFalse);
    expect(r.items.last.confidence, isNull);
    expect(r.unlisted.single.name, 'Atchara (pickled papaya)');
    expect(
      PhotoRecognition.fromJson({
        'recognitionId': 8,
        'remainingToday': 0,
        'items': [],
        'unlisted': [],
      }).isEmpty,
      isTrue,
    );
  });

  test('a log item sends its suggestion id, servings and food reference', () {
    expect(
      const PhotoLogItem(itemId: 40, servings: 1.5, food: _rice).toJson(),
      {
        'itemId': 40,
        'servings': 1.5,
        'food': {'source': 'local', 'id': 1},
      },
    );
    expect(
      const PhotoLogItem(itemId: null, servings: 1, food: _shake).toJson(),
      {
        'itemId': null,
        'servings': 1.0,
        'food': {'source': 'fatsecret', 'externalId': 'fs-1'},
      },
    );
  });

  test('swapping keeps the food it replaced as a chip, so the swap can be undone; at most two chips', () {
    final card = DraftCard.suggested(
      PhotoRecognition.fromJson(_answer).items.first,
      id: 0,
    );
    card.replaceWith(_garlic);
    expect(card.food!.name, 'Garlic fried rice (sinangag)');
    expect(card.alternatives.map((f) => f.name), ['White rice', 'Mango Shake']);
    card.replaceWith(_tinola);
    expect(card.alternatives.map((f) => f.name), [
      'Garlic fried rice (sinangag)',
      'White rice',
    ]);
    card.replaceWith(_tinola);
    expect(card.alternatives.map((f) => f.name), [
      'Garlic fried rice (sinangag)',
      'White rice',
    ], reason: 'same food: nothing changes');
  });

  test('an unlisted card has no food until one is picked, then logs with its own item id', () {
    final card = DraftCard.unlisted(
      PhotoRecognition.fromJson(_answer).unlisted.single,
      id: 0,
    );
    expect(card.isUnlisted, isTrue);
    expect(card.label, 'Atchara (pickled papaya)');
    expect(logItemsOf([card]), isEmpty);
    card.replaceWith(_shake);
    expect(card.isUnlisted, isFalse);
    expect(card.alternatives, isEmpty);
    expect(logItemsOf([card]).single.toJson()['itemId'], 42);
  });

  test('servings step in halves between 0.5 and 20', () {
    final card = DraftCard.added(_rice, id: 0);
    expect([card.itemId, card.servings], [null, 1.0]);
    card.setServings(0.5);
    card.setServings(0);
    expect(card.servings, 0.5);
    card.setServings(25);
    expect(card.servings, 20);
  });

  test('the estimated total follows the server\'s rounding and skips unlisted cards', () {
    final cards = [
      DraftCard.added(_rice, id: 0)..setServings(1.5),
      DraftCard.added(_garlic, id: 1),
      DraftCard.unlisted(
        const PhotoUnlisted(itemId: 9, name: 'Atchara'),
        id: 2,
      ),
    ];
    final t = draftTotals(cards);
    expect(t.kcal, 309 + 299);
    expect(t.proteinG, closeTo(5.1 + 4.2, 1e-9));
    expect(logItemsOf(cards).length, 2);
  });

  test('search starts from the name without its bracketed part', () {
    expect(searchNameOf('Atchara (pickled papaya)'), 'Atchara');
    expect(searchNameOf('Sinigang na baboy'), 'Sinigang na baboy');
    expect(searchNameOf('(odd)'), '(odd)');
  });

  test('sameFood compares by id, FatSecret id, or a manual name', () {
    expect(
      sameFood(
        _rice,
        const Food(
          source: 'local',
          id: 1,
          name: 'x',
          kcal: 0,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
        ),
      ),
      isTrue,
    );
    expect(sameFood(_rice, _garlic), isFalse);
    expect(
      sameFood(
        _shake,
        const Food(
          source: 'fatsecret',
          externalId: 'fs-1',
          name: 'y',
          kcal: 0,
          proteinG: 0,
          carbsG: 0,
          fatG: 0,
        ),
      ),
      isTrue,
    );
    expect(sameFood(_rice, _shake), isFalse);
  });
}
