import '../../../core/api_client.dart';
import '../domain/admin_models.dart';
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

  /// The Overview tab's figures.
  Future<AdminOverview> overview() async =>
      AdminOverview.fromJson(await _api.getJson('/api/v1/admin/overview'));

  /// One page of trainees, newest sign-ups first. [filter] is `all`, `pro`
  /// or `suspended`. Every query value is a string: `getJson` drops any
  /// other kind.
  Future<AdminUsersPage> users({
    String q = '',
    String filter = 'all',
    int page = 1,
  }) async => AdminUsersPage.fromJson(
    await _api.getJson(
      '/api/v1/admin/users',
      query: {'q': q, 'filter': filter, 'page': '$page'},
    ),
  );

  /// One trainee's account. `404 USER_NOT_FOUND` for an unknown id.
  Future<AdminUserDetail> user(int id) async =>
      _detail(await _api.getJson('/api/v1/admin/users/$id'));

  /// Signs the trainee out everywhere and refuses their sign-ins until
  /// [reinstate]. Repeating it is harmless.
  Future<AdminUserDetail> suspend(int id) async =>
      _detail(await _api.postJson('/api/v1/admin/users/$id/suspend', const {}));

  Future<AdminUserDetail> reinstate(int id) async => _detail(
    await _api.postJson('/api/v1/admin/users/$id/reinstate', const {}),
  );

  AdminUserDetail _detail(Map<String, dynamic> data) =>
      AdminUserDetail.fromJson(data['user'] as Map<String, dynamic>);
}
