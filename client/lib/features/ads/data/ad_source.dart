import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../admin/domain/admin_format.dart' show mediaUrl;
import '../../exercises/presentation/providers.dart' show apiClientProvider;
import '../domain/house_ad.dart';

/// Where the ad card gets its ad. FitSync's own ads today
/// ([HouseAdSource]); an ad network can stand behind the same three calls
/// later without the card changing.
abstract interface class AdSource {
  /// One ad to show, or null for none (a Pro member, or nothing running).
  Future<HouseAd?> current();

  /// The card showed ad [id]. Never throws: a lost count is not worth a
  /// trainee seeing an error.
  Future<void> viewed(int id);

  /// The card with ad [id] was tapped. Never throws.
  Future<void> tapped(int id);
}

/// FitSync's own ads, from `/api/v1/ads`.
class HouseAdSource implements AdSource {
  HouseAdSource(this._api);

  final ApiClient _api;

  @override
  Future<HouseAd?> current() async {
    final data = await _api.getJson('/api/v1/ads/current');
    final ad = data['ad'] as Map<String, dynamic>?;
    if (ad == null) return null;
    return HouseAd(
      id: (ad['id'] as num).toInt(),
      title: ad['title'] as String,
      imageUrl: mediaUrl(_api.baseUrl, ad['imageUrl'] as String),
      linkUrl: ad['linkUrl'] as String?,
    );
  }

  @override
  Future<void> viewed(int id) => _report('/api/v1/ads/$id/view');

  @override
  Future<void> tapped(int id) => _report('/api/v1/ads/$id/tap');

  Future<void> _report(String path) async {
    try {
      await _api.postJson(path, const {});
    } catch (_) {
      // The server answers 204 whatever it counted; a failure here only
      // loses one count.
    }
  }
}

final adSourceProvider = Provider<AdSource>(
  (ref) => HouseAdSource(ref.watch(apiClientProvider)),
);
