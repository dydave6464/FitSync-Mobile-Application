import '../../../core/api_client.dart';
import '../domain/admin_user.dart';

/// The admin's side of the server, every route under `/api/v1/admin`. The
/// token it sends is the admin token stored at sign-in; a trainee token is
/// refused there with `UNAUTHENTICATED`.
class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  /// The signed-in admin. The launch check: an expired or revoked admin token
  /// answers `UNAUTHENTICATED`.
  Future<AdminUser> me() async {
    final data = await _api.getJson('/api/v1/admin/me');
    return AdminUser.fromJson(data['admin'] as Map<String, dynamic>);
  }
}
