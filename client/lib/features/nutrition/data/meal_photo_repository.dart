import 'dart:convert';
import 'dart:typed_data';

import '../../../core/api_client.dart';
import '../domain/meal_photo.dart';

/// Snap a meal's calls: ask about today, send a photo, then log what the
/// user confirmed.
class MealPhotoRepository {
  MealPhotoRepository(this._api);

  final ApiClient _api;

  /// The server gives one photo at most 37 seconds -- the Cloudflare backup,
  /// waiting out a busy Groq once, and one retry -- (BUDGET_MS in
  /// server/src/services/vision/chat-client.js), so this outlasts it with
  /// room for the upload. Lower it only together with that budget.
  static const recognizeTimeout = Duration(seconds: 45);

  /// A FatSecret item is fetched from FatSecret while logging.
  static const logTimeout = Duration(seconds: 30);

  /// The capture sheet's question is a nicety: it gives up quickly.
  /// getJson has no timeout parameter, so this wraps the call.
  static const todayTimeout = Duration(seconds: 5);

  /// How many photos are left today, and today's unlogged photo, if any.
  Future<PhotoToday> today() async {
    final data = await _api.getJson('/api/v1/nutrition/recognitions/today').timeout(todayTimeout);
    return PhotoToday.fromJson(data);
  }

  /// Completing [cancel] drops the request: the server then stops, sends
  /// nothing more to the AI and does not count the photo.
  Future<PhotoRecognition> recognize(Uint8List bytes, String mimeType, {Future<void>? cancel}) async {
    final data = await _api.postJson('/api/v1/nutrition/recognize', {
      'image': base64Encode(bytes),
      'mimeType': mimeType,
    }, timeout: recognizeTimeout, abortTrigger: cancel);
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
