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

  /// The server's address, which the media paths in exercises
  /// (`/storage/...`) are joined to.
  String get baseUrl => _api.baseUrl;

  /// One page of exercise demos. [status] is `pending` or `live`.
  Future<AdminExercisesPage> exercises({
    String status = 'pending',
    String q = '',
    int page = 1,
  }) async => AdminExercisesPage.fromJson(
    await _api.getJson(
      '/api/v1/admin/exercises',
      query: {'status': status, 'q': q, 'page': '$page'},
    ),
  );

  /// Puts the exercise in the library, with its safety rows. `409
  /// EXERCISE_UNCLASSIFIABLE` when they can't be worked out.
  Future<AdminExercise> publish(int id) async => _exercise(
    await _api.postJson('/api/v1/admin/exercises/$id/publish', const {}),
  );

  /// Takes the exercise out of the library. `409 EXERCISE_IN_USE` once any
  /// trainee has it in a plan or a workout.
  Future<AdminExercise> unpublish(int id) async => _exercise(
    await _api.postJson('/api/v1/admin/exercises/$id/unpublish', const {}),
  );

  /// One page of FitSync's own foods. [show] is `shown` or `hidden`.
  Future<AdminFoodsPage> foods({
    String show = 'shown',
    String q = '',
    int page = 1,
  }) async => AdminFoodsPage.fromJson(
    await _api.getJson(
      '/api/v1/admin/foods',
      query: {'show': show, 'q': q, 'page': '$page'},
    ),
  );

  /// `400` per field (`details: [{ field }]`); `409 FOOD_NAME_TAKEN`.
  Future<AdminFood> createFood(FoodInput input) async =>
      _food(await _api.postJson('/api/v1/admin/foods', input.toJson()));

  Future<AdminFood> updateFood(int id, FoodInput input) async =>
      _food(await _api.patchJson('/api/v1/admin/foods/$id', input.toJson()));

  /// Leaves the food out of search, Recents and Snap a meal. Meals already
  /// logged keep it.
  Future<AdminFood> hideFood(int id) async =>
      _food(await _api.postJson('/api/v1/admin/foods/$id/hide', const {}));

  Future<AdminFood> showFood(int id) async =>
      _food(await _api.postJson('/api/v1/admin/foods/$id/show', const {}));

  /// Every ad, newest first (no paging: there are few).
  Future<List<AdminAd>> ads() async {
    final data = await _api.getJson('/api/v1/admin/ads');
    return [
      for (final ad in data['ads'] as List)
        AdminAd.fromJson(ad as Map<String, dynamic>),
    ];
  }

  /// `400` per field (`details: [{ field }]`); `400 INVALID_IMAGE`.
  Future<AdminAd> createAd(AdInput input) async =>
      _ad(await _api.postJson('/api/v1/admin/ads', input.toJson()));

  /// `404 AD_NOT_FOUND`. The image is replaced only when [input] has one.
  Future<AdminAd> updateAd(int id, AdInput input) async =>
      _ad(await _api.patchJson('/api/v1/admin/ads/$id', input.toJson()));

  /// Pauses the ad ([active] false) or resumes it, nothing else changed.
  Future<AdminAd> setAdActive(int id, {required bool active}) async =>
      _ad(await _api.patchJson('/api/v1/admin/ads/$id', {'active': active}));

  /// One Manila month's revenue, `YYYY-MM`; null is this month. A future
  /// month or a bad one is `400`.
  Future<RevenueMonth> revenue({String? month}) async => RevenueMonth.fromJson(
    await _api.getJson('/api/v1/admin/revenue', query: {'month': month}),
  );

  AdminAd _ad(Map<String, dynamic> data) =>
      AdminAd.fromJson(data['ad'] as Map<String, dynamic>);

  AdminExercise _exercise(Map<String, dynamic> data) =>
      AdminExercise.fromJson(data['exercise'] as Map<String, dynamic>);

  AdminFood _food(Map<String, dynamic> data) =>
      AdminFood.fromJson(data['food'] as Map<String, dynamic>);
}
