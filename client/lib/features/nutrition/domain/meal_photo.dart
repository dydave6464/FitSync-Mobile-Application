import 'dart:typed_data';

import 'nutrition.dart';

/// The fewest and most servings a confirm-screen card allows: the log
/// route's own range, in halves.
const minPhotoServings = 0.5;
const maxPhotoServings = 20.0;

/// 'image/jpeg' or 'image/png' from the bytes themselves, or null for any
/// other format (HEIC, WebP): the server takes only these two and checks the
/// same first bytes.
String? sniffImageType(Uint8List bytes) {
  bool startsWith(List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  return null;
}

double? _n(Object? v) => v == null ? null : (v as num).toDouble();

/// A food in a photo answer. Always a row in FitSync's food list (its own, or
/// a saved FatSecret copy), so it logs as `{source: 'local', id}`.
Food photoFoodFromJson(Map<String, dynamic> j) {
  final p = j['perServing'] as Map<String, dynamic>;
  return Food(
    source: 'local',
    id: j['id'] as int,
    name: j['name'] as String,
    servingDesc: j['servingDesc'] as String?,
    kcal: (p['kcal'] as num).round(),
    proteinG: _n(p['proteinG'])!,
    carbsG: _n(p['carbsG'])!,
    fatG: _n(p['fatG'])!,
    fiberG: _n(p['fiberG']),
    sugarG: _n(p['sugarG']),
    sodiumMg: _n(p['sodiumMg']),
    fatsecretCopy: j['fromFatsecret'] == true,
  );
}

/// One item the AI matched to FitSync's list.
class PhotoSuggestion {
  const PhotoSuggestion({
    required this.itemId,
    required this.confidence,
    required this.servings,
    required this.food,
    required this.alternatives,
  });

  factory PhotoSuggestion.fromJson(Map<String, dynamic> j) => PhotoSuggestion(
    itemId: j['itemId'] as int,
    confidence: _n(j['confidence']),
    servings: _n(j['servings'])!,
    food: photoFoodFromJson(j['food'] as Map<String, dynamic>),
    alternatives: [
      for (final a in j['alternatives'] as List)
        photoFoodFromJson(a as Map<String, dynamic>),
    ],
  );

  final int itemId;
  final double? confidence;
  final double servings;
  final Food food;

  /// The AI's next guesses, for "Not right? Pick another".
  final List<Food> alternatives;
}

/// An item the AI saw that isn't in FitSync's list.
class PhotoUnlisted {
  const PhotoUnlisted({required this.itemId, required this.name});

  factory PhotoUnlisted.fromJson(Map<String, dynamic> j) =>
      PhotoUnlisted(itemId: j['itemId'] as int, name: j['name'] as String);

  final int itemId;
  final String name;
}

class PhotoRecognition {
  const PhotoRecognition({
    required this.recognitionId,
    required this.remainingToday,
    required this.items,
    required this.unlisted,
  });

  factory PhotoRecognition.fromJson(Map<String, dynamic> j) => PhotoRecognition(
    recognitionId: j['recognitionId'] as int,
    remainingToday: j['remainingToday'] as int,
    items: [
      for (final i in j['items'] as List)
        PhotoSuggestion.fromJson(i as Map<String, dynamic>),
    ],
    unlisted: [
      for (final u in j['unlisted'] as List)
        PhotoUnlisted.fromJson(u as Map<String, dynamic>),
    ],
  );

  final int recognitionId;
  final int remainingToday;
  final List<PhotoSuggestion> items;
  final List<PhotoUnlisted> unlisted;

  /// No food spotted at all.
  bool get isEmpty => items.isEmpty && unlisted.isEmpty;

  /// How many foods the photo found: matched and unlisted.
  int get foodCount => items.length + unlisted.length;
}

/// Today's photos, asked before the next one: how many are left, and the
/// newest recognised photo if it was not logged, so it can be finished.
class PhotoToday {
  const PhotoToday({
    required this.limit,
    required this.remainingToday,
    this.unlogged,
    this.unloggedAt,
  });

  factory PhotoToday.fromJson(Map<String, dynamic> j) {
    final u = j['unlogged'] as Map<String, dynamic>?;
    return PhotoToday(
      limit: j['limit'] as int,
      remainingToday: j['remainingToday'] as int,
      unlogged: u == null ? null : PhotoRecognition.fromJson(u),
      unloggedAt: u == null ? null : DateTime.parse(u['createdAt'] as String),
    );
  }

  final int limit;
  final int remainingToday;
  final PhotoRecognition? unlogged;
  final DateTime? unloggedAt;
}

/// One food sent to the log route.
class PhotoLogItem {
  const PhotoLogItem({
    required this.itemId,
    required this.servings,
    required this.food,
  });

  /// The suggestion this replaces or keeps; null for a food the user added.
  final int? itemId;
  final double servings;
  final Food food;

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'servings': servings,
    'food': food.toRef(),
  };
}

/// Whether [a] and [b] are the same food: by id for a FitSync food, by
/// FatSecret id for an online one, by name for the user's own.
bool sameFood(Food a, Food b) {
  if (a.source != b.source) return false;
  return switch (a.source) {
    'local' => a.id == b.id,
    'fatsecret' => a.externalId == b.externalId,
    _ => a.name == b.name,
  };
}

/// "Atchara (pickled papaya)" -> "Atchara": what Search starts from. The
/// search matches the whole typed text, and the bracketed part rarely
/// matches FitSync's own wording.
String searchNameOf(String name) {
  final head = name.split('(').first.trim();
  return head.isEmpty ? name : head;
}

/// One card on the confirm screen: a food to log, or an item the AI named
/// that isn't in FitSync's list (no [food]) until the user picks one.
class DraftCard {
  DraftCard.suggested(PhotoSuggestion s, {required this.id})
    : itemId = s.itemId,
      unlistedName = null,
      food = s.food,
      servings = s.servings,
      alternatives = List.of(s.alternatives);

  DraftCard.unlisted(PhotoUnlisted u, {required this.id})
    : itemId = u.itemId,
      unlistedName = u.name,
      food = null,
      servings = 1,
      alternatives = [];

  /// A food the user added with "+ Add an item".
  DraftCard.added(Food this.food, {required this.id})
    : itemId = null,
      unlistedName = null,
      servings = 1,
      alternatives = [];

  /// The card's own number on the screen, given once in the order cards
  /// are made. Its parts are keyed by it, not by where the card sits, so
  /// they stay put when a card above is removed or put back.
  final int id;

  final int? itemId;
  final String? unlistedName;
  Food? food;
  double servings;
  List<Food> alternatives;

  bool get isUnlisted => food == null;

  /// What the card is called in messages ("Removed …").
  String get label => food?.name ?? unlistedName!;

  /// Puts [to] in place of the card's food. The food it replaces becomes the
  /// first chip, so a wrong swap is one tap to undo; at most two chips.
  void replaceWith(Food to) {
    final from = food;
    if (from != null && sameFood(from, to)) return;
    alternatives = [
      ?from,
      ...alternatives.where((a) => !sameFood(a, to)),
    ].take(2).toList();
    food = to;
  }

  void setServings(double value) =>
      servings = value.clamp(minPhotoServings, maxPhotoServings).toDouble();
}

/// The estimated total of every card with a food, rounded per item the way
/// the server stores entries.
MacroTotals draftTotals(Iterable<DraftCard> cards) => MacroTotals.of([
  for (final c in cards)
    if (c.food != null)
      FoodEntry.pending(
        id: 0,
        food: c.food!,
        mealType: 'snack',
        servings: c.servings,
      ),
]);

/// The cards that will be logged: every one with a food, in screen order.
List<PhotoLogItem> logItemsOf(Iterable<DraftCard> cards) => [
  for (final c in cards)
    if (c.food != null)
      PhotoLogItem(itemId: c.itemId, servings: c.servings, food: c.food!),
];
