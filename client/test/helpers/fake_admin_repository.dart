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
  }) : onOverview = overview ?? (() async => sampleOverview()),
       onUsers = users ?? ((_, _, _) async => usersPage(const [])),
       onUser = user ?? ((id) async => sampleDetail(id: id)),
       onSuspend = suspend ?? ((id) async => sampleDetail(id: id)),
       onReinstate = reinstate ?? ((id) async => sampleDetail(id: id));

  Future<AdminOverview> Function() onOverview;
  Future<AdminUsersPage> Function(String q, String filter, int page) onUsers;
  Future<AdminUserDetail> Function(int id) onUser;
  Future<AdminUserDetail> Function(int id) onSuspend;
  Future<AdminUserDetail> Function(int id) onReinstate;

  int overviewCalls = 0;
  final usersCalls = <({String q, String filter, int page})>[];
  final userCalls = <int>[];
  final suspendCalls = <int>[];
  final reinstateCalls = <int>[];

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
