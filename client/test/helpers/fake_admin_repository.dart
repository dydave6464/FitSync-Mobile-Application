import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/features/admin/data/admin_repository.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';
import 'package:fitsync/features/admin/domain/admin_user.dart';

/// An [AdminRepository] whose answers a test sets, recording what it was
/// asked. Every answer is a function so a test can make one fail, wait, or
/// change between calls.
class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({
    Future<AdminOverview> Function()? overview,
    Future<AdminUsersPage> Function(String q, String filter, int page)? users,
    Future<AdminUserDetail> Function(int id)? user,
    Future<AdminUserDetail> Function(int id)? suspend,
    Future<AdminUserDetail> Function(int id)? reinstate,
    Future<AdminExercisesPage> Function(String status, String q, int page)?
    exercises,
    Future<AdminExercise> Function(int id)? publish,
    Future<AdminExercise> Function(int id)? unpublish,
    Future<AdminFoodsPage> Function(String show, String q, int page)? foods,
    Future<AdminFood> Function(FoodInput input)? createFood,
    Future<AdminFood> Function(int id, FoodInput input)? updateFood,
    Future<AdminFood> Function(int id)? hideFood,
    Future<AdminFood> Function(int id)? showFood,
    Future<List<AdminAd>> Function()? ads,
    Future<AdminAd> Function(AdInput input)? createAd,
    Future<AdminAd> Function(int id, AdInput input)? updateAd,
    Future<AdminAd> Function(int id, bool active)? setAdActive,
  }) : onAds = ads ?? (() async => const []),
       onCreateAd = createAd ?? ((_) async => sampleAd()),
       onUpdateAd = updateAd ?? ((id, _) async => sampleAd(id: id)),
       onSetAdActive =
           setAdActive ??
           ((id, active) async => sampleAd(
             id: id,
             active: active,
             status: active ? 'running' : 'paused',
           )),
       onOverview = overview ?? (() async => sampleOverview()),
       onUsers = users ?? ((_, _, _) async => usersPage(const [])),
       onUser = user ?? ((id) async => sampleDetail(id: id)),
       onSuspend = suspend ?? ((id) async => sampleDetail(id: id)),
       onReinstate = reinstate ?? ((id) async => sampleDetail(id: id)),
       onExercises = exercises ?? ((_, _, _) async => exercisesPage(const [])),
       onPublish = publish ?? ((id) async => sampleExercise(id: id)),
       onUnpublish =
           unpublish ??
           ((id) async => sampleExercise(id: id, status: 'pending')),
       onFoods = foods ?? ((_, _, _) async => foodsPage(const [])),
       onCreateFood = createFood ?? ((_) async => sampleFood()),
       onUpdateFood = updateFood ?? ((id, _) async => sampleFood(id: id)),
       onHideFood =
           hideFood ?? ((id) async => sampleFood(id: id, hidden: true)),
       onShowFood = showFood ?? ((id) async => sampleFood(id: id));

  Future<AdminOverview> Function() onOverview;
  Future<AdminUsersPage> Function(String q, String filter, int page) onUsers;
  Future<AdminUserDetail> Function(int id) onUser;
  Future<AdminUserDetail> Function(int id) onSuspend;
  Future<AdminUserDetail> Function(int id) onReinstate;
  Future<AdminExercisesPage> Function(String status, String q, int page)
  onExercises;
  Future<AdminExercise> Function(int id) onPublish;
  Future<AdminExercise> Function(int id) onUnpublish;
  Future<AdminFoodsPage> Function(String show, String q, int page) onFoods;
  Future<AdminFood> Function(FoodInput input) onCreateFood;
  Future<AdminFood> Function(int id, FoodInput input) onUpdateFood;
  Future<AdminFood> Function(int id) onHideFood;
  Future<AdminFood> Function(int id) onShowFood;

  int overviewCalls = 0;
  final usersCalls = <({String q, String filter, int page})>[];
  final userCalls = <int>[];
  final suspendCalls = <int>[];
  final reinstateCalls = <int>[];
  final exercisesCalls = <({String status, String q, int page})>[];
  final publishCalls = <int>[];
  final unpublishCalls = <int>[];
  final foodsCalls = <({String show, String q, int page})>[];
  final createFoodCalls = <FoodInput>[];
  final updateFoodCalls = <({int id, FoodInput input})>[];
  final hideFoodCalls = <int>[];
  final showFoodCalls = <int>[];

  Future<List<AdminAd>> Function() onAds;
  Future<AdminAd> Function(AdInput input) onCreateAd;
  Future<AdminAd> Function(int id, AdInput input) onUpdateAd;
  Future<AdminAd> Function(int id, bool active) onSetAdActive;

  int adsCalls = 0;
  final createAdCalls = <AdInput>[];
  final updateAdCalls = <({int id, AdInput input})>[];
  final setAdActiveCalls = <({int id, bool active})>[];

  @override
  Future<List<AdminAd>> ads() {
    adsCalls++;
    return onAds();
  }

  @override
  Future<AdminAd> createAd(AdInput input) {
    createAdCalls.add(input);
    return onCreateAd(input);
  }

  @override
  Future<AdminAd> updateAd(int id, AdInput input) {
    updateAdCalls.add((id: id, input: input));
    return onUpdateAd(id, input);
  }

  @override
  Future<AdminAd> setAdActive(int id, {required bool active}) {
    setAdActiveCalls.add((id: id, active: active));
    return onSetAdActive(id, active);
  }

  @override
  String get baseUrl => 'http://fitsync.test';

  @override
  Future<AdminExercisesPage> exercises({
    String status = 'pending',
    String q = '',
    int page = 1,
  }) {
    exercisesCalls.add((status: status, q: q, page: page));
    return onExercises(status, q, page);
  }

  @override
  Future<AdminExercise> publish(int id) {
    publishCalls.add(id);
    return onPublish(id);
  }

  @override
  Future<AdminExercise> unpublish(int id) {
    unpublishCalls.add(id);
    return onUnpublish(id);
  }

  @override
  Future<AdminFoodsPage> foods({
    String show = 'shown',
    String q = '',
    int page = 1,
  }) {
    foodsCalls.add((show: show, q: q, page: page));
    return onFoods(show, q, page);
  }

  @override
  Future<AdminFood> createFood(FoodInput input) {
    createFoodCalls.add(input);
    return onCreateFood(input);
  }

  @override
  Future<AdminFood> updateFood(int id, FoodInput input) {
    updateFoodCalls.add((id: id, input: input));
    return onUpdateFood(id, input);
  }

  @override
  Future<AdminFood> hideFood(int id) {
    hideFoodCalls.add(id);
    return onHideFood(id);
  }

  @override
  Future<AdminFood> showFood(int id) {
    showFoodCalls.add(id);
    return onShowFood(id);
  }

  @override
  Future<AdminUser> me() async =>
      const AdminUser(id: 1, email: 'admin@fitsync.ph', fullName: 'Ana Reyes');

  @override
  Future<AdminOverview> overview() {
    overviewCalls++;
    return onOverview();
  }

  @override
  Future<AdminUsersPage> users({
    String q = '',
    String filter = 'all',
    int page = 1,
  }) {
    usersCalls.add((q: q, filter: filter, page: page));
    return onUsers(q, filter, page);
  }

  @override
  Future<AdminUserDetail> user(int id) {
    userCalls.add(id);
    return onUser(id);
  }

  @override
  Future<AdminUserDetail> suspend(int id) {
    suspendCalls.add(id);
    return onSuspend(id);
  }

  @override
  Future<AdminUserDetail> reinstate(int id) {
    reinstateCalls.add(id);
    return onReinstate(id);
  }
}

/// A server error the automatic retry leaves alone, so a test sees the
/// error state at once.
const refused = ApiException('UNKNOWN_ADMIN_ERROR', 'The server said no.');

/// Appendix A's example: 14 active (11 before), 3 Pro, ₱498 Pro revenue
/// against ₱249, no ad revenue, and 12 sign-ups over 30 days -- 2 on
/// Nov 5, the rest spread one a day.
AdminOverview sampleOverview({
  int activeUsers = 14,
  int previousActiveUsers = 11,
  int proMembers = 3,
  double proThisMonth = 498,
  double proLastMonth = 249,
  double adThisMonth = 0,
  double adLastMonth = 0,
}) {
  final first = DateTime.utc(2026, 10, 9);
  String day(int i) =>
      first.add(Duration(days: i)).toIso8601String().substring(0, 10);
  // Nov 5 is day 27; ten more single sign-ups on days 10..19.
  final days = [
    for (var i = 0; i < 30; i++)
      SignupDay(date: day(i), count: i == 27 ? 2 : (i >= 10 && i < 20 ? 1 : 0)),
  ];
  return AdminOverview(
    today: '2026-11-07',
    activeUsers: activeUsers,
    previousActiveUsers: previousActiveUsers,
    proMembers: proMembers,
    proRevenueThisMonth: proThisMonth,
    proRevenueLastMonth: proLastMonth,
    adRevenueThisMonth: adThisMonth,
    adRevenueLastMonth: adLastMonth,
    signupsTotal: 12,
    signupDays: days,
  );
}

AdminUserRow sampleRow({
  int id = 7,
  String fullName = 'Juan Dela Cruz',
  String? email,
  bool isPro = false,
  bool suspended = false,
  String? lastActiveOn = '2026-11-06',
  String joinedOn = '2026-11-05',
}) => AdminUserRow(
  id: id,
  fullName: fullName,
  email: email ?? 'user$id@example.com',
  isPro: isPro,
  suspended: suspended,
  lastActiveOn: lastActiveOn,
  joinedOn: joinedOn,
);

AdminUsersPage usersPage(
  List<AdminUserRow> users, {
  int page = 1,
  int limit = 30,
  int? total,
}) => AdminUsersPage(
  users: users,
  page: page,
  limit: limit,
  total: total ?? users.length,
);

AdminUserDetail sampleDetail({
  int id = 7,
  String fullName = 'Juan Dela Cruz',
  String email = 'juan@example.com',
  String joinedOn = '2026-11-05',
  bool emailVerified = true,
  List<String> signInMethods = const ['password'],
  String? lastActiveOn = '2026-11-06',
  bool isPro = false,
  String? proSource,
  DateTime? proUntil,
  DateTime? suspendedAt,
}) => AdminUserDetail(
  id: id,
  fullName: fullName,
  email: email,
  joinedOn: joinedOn,
  emailVerified: emailVerified,
  signInMethods: signInMethods,
  lastActiveOn: lastActiveOn,
  isPro: isPro,
  proSource: proSource,
  proUntil: proUntil,
  suspendedAt: suspendedAt,
);

AdminExercise sampleExercise({
  int id = 41,
  String name = 'romanian deadlift',
  String? muscleGroup = 'hamstrings',
  String? equipment = 'barbell',
  String? thumbnailUrl = '/storage/exercises/41/thumb.jpg',
  String? animationUrl = '/storage/exercises/41/demo.gif',
  String status = 'live',
  String? pendingReason,
}) => AdminExercise(
  id: id,
  name: name,
  muscleGroup: muscleGroup,
  equipment: equipment,
  thumbnailUrl: thumbnailUrl,
  animationUrl: animationUrl,
  status: status,
  pendingReason: pendingReason,
);

AdminExercisesPage exercisesPage(
  List<AdminExercise> exercises, {
  int pending = 121,
  int live = 1203,
  int page = 1,
  int limit = 30,
  int? total,
}) => AdminExercisesPage(
  exercises: exercises,
  pendingCount: pending,
  liveCount: live,
  page: page,
  limit: limit,
  total: total ?? exercises.length,
);

AdminFood sampleFood({
  int id = 12,
  String name = 'Chicken adobo',
  String category = 'filipino',
  String? foodType = 'home',
  String? servingDesc = '1 cup',
  int kcal = 320,
  double proteinG = 28,
  double carbsG = 4,
  double fatG = 21,
  double? fiberG,
  double? sugarG,
  double? sodiumMg,
  bool hidden = false,
}) => AdminFood(
  id: id,
  name: name,
  category: category,
  foodType: foodType,
  servingDesc: servingDesc,
  kcal: kcal,
  proteinG: proteinG,
  carbsG: carbsG,
  fatG: fatG,
  fiberG: fiberG,
  sugarG: sugarG,
  sodiumMg: sodiumMg,
  hidden: hidden,
);

AdminFoodsPage foodsPage(
  List<AdminFood> foods, {
  int shown = 412,
  int hidden = 3,
  int page = 1,
  int limit = 30,
  int? total,
}) => AdminFoodsPage(
  foods: foods,
  shownCount: shown,
  hiddenCount: hidden,
  page: page,
  limit: limit,
  total: total ?? foods.length,
);

AdminAd sampleAd({
  int id = 5,
  String title = 'Protein bars, 20% off',
  String imageUrl = '/storage/ads/5.jpg',
  String? linkUrl = 'https://shop.example.ph/',
  String advertiser = 'GymShark PH',
  double amountPhp = 1200,
  String startsOn = '2026-11-01',
  String endsOn = '2026-11-30',
  bool active = true,
  String status = 'running',
  int views = 1204,
  int taps = 37,
}) => AdminAd(
  id: id,
  title: title,
  imageUrl: imageUrl,
  linkUrl: linkUrl,
  advertiser: advertiser,
  amountPhp: amountPhp,
  startsOn: startsOn,
  endsOn: endsOn,
  active: active,
  status: status,
  views: views,
  taps: taps,
);
