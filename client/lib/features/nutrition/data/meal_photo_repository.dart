import 'dart:convert';
import 'dart:typed_data';

import '../../../core/api_client.dart';
import '../domain/meal_photo.dart';

/// Snap a meal's two calls: send a photo, then log what the user confirmed.
class MealPhotoRepository {
  MealPhotoRepository(this._api);

  final ApiClient _api;

  /// The server gives the AI 15 seconds and asks once more after an
  /// unreadable answer, so this outlasts both.
  static const recognizeTimeout = Duration(seconds: 45);

  /// A FatSecret item is fetched from FatSecret while logging.
  static const logTimeout = Duration(seconds: 30);

  Future<PhotoRecognition> recognize(Uint8List bytes, String mimeType) async {
    final data = await _api.postJson('/api/v1/nutrition/recognize', {
      'image': base64Encode(bytes),
      'mimeType': mimeType,
    }, timeout: recognizeTimeout);
    return PhotoRecognition.fromJson(data);
  }

  /// Logs [items] to [mealType] on [date], all or none. Returns how many
  /// entries were saved.
  Future<int> log({
    required int recognitionId,
    required String date,
    required String mealType,
    required List<PhotoLogItem> items,
  }) async {
    final data = await _api.postJson(
      '/api/v1/nutrition/recognitions/$recognitionId/log',
      {
        'date': date,
        'mealType': mealType,
        'items': [for (final i in items) i.toJson()],
      },
      timeout: logTimeout,
    );
    return (data['entries'] as List).length;
  }
}
