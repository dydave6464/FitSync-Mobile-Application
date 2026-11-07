/// What the admin screens read from `/api/v1/admin/*` (spec Appendix A).
///
/// Account information only: nothing about a trainee's body, food, workouts
/// or health answers is sent to the admin app, so none of it is modelled.
library;

double _php(Object? value) => (value as num).toDouble();

/// One Manila day of the sign-ups chart.
class SignupDay {
  const SignupDay({required this.date, required this.count});

  /// `YYYY-MM-DD`.
  final String date;
  final int count;

  factory SignupDay.fromJson(Map<String, dynamic> json) => SignupDay(
    date: json['date'] as String,
    count: (json['count'] as num).toInt(),
  );
}

/// The Overview tab's figures.
class AdminOverview {
  const AdminOverview({
    required this.today,
    required this.activeUsers,
    required this.previousActiveUsers,
    required this.proMembers,
    required this.proRevenueThisMonth,
    required this.proRevenueLastMonth,
    required this.adRevenueThisMonth,
    required this.adRevenueLastMonth,
    required this.signupsTotal,
    required this.signupDays,
  });

  /// The server's Manila day, `YYYY-MM-DD`.
  final String today;

  /// Trainees active in the last 30 days, and in the 30 before those.
  final int activeUsers;
  final int previousActiveUsers;
  final int proMembers;
  final double proRevenueThisMonth;
  final double proRevenueLastMonth;
  final double adRevenueThisMonth;
  final double adRevenueLastMonth;
  final int signupsTotal;

  /// 30 days, oldest first, zeros included.
  final List<SignupDay> signupDays;

  factory AdminOverview.fromJson(Map<String, dynamic> json) {
    final active = json['activeUsers'] as Map<String, dynamic>;
    final pro = json['proRevenue'] as Map<String, dynamic>;
    final ads = json['adRevenue'] as Map<String, dynamic>;
    final signups = json['signups'] as Map<String, dynamic>;
    return AdminOverview(
      today: json['today'] as String,
      activeUsers: (active['count'] as num).toInt(),
      previousActiveUsers: (active['previousCount'] as num).toInt(),
      proMembers: (json['proMembers'] as num).toInt(),
      proRevenueThisMonth: _php(pro['thisMonthPhp']),
      proRevenueLastMonth: _php(pro['lastMonthPhp']),
      adRevenueThisMonth: _php(ads['thisMonthPhp']),
      adRevenueLastMonth: _php(ads['lastMonthPhp']),
      signupsTotal: (signups['total'] as num).toInt(),
      signupDays: [
        for (final day in signups['days'] as List)
          SignupDay.fromJson(day as Map<String, dynamic>),
      ],
    );
  }
}

/// One trainee in the Users list.
class AdminUserRow {
  const AdminUserRow({
    required this.id,
    required this.fullName,
    required this.email,
    required this.isPro,
    required this.suspended,
    required this.lastActiveOn,
    required this.joinedOn,
  });

  final int id;
  final String fullName;
  final String email;
  final bool isPro;
  final bool suspended;

  /// The last Manila day with anything logged, or null for none yet.
  final String? lastActiveOn;
  final String joinedOn;

  factory AdminUserRow.fromJson(Map<String, dynamic> json) => AdminUserRow(
    id: (json['id'] as num).toInt(),
    fullName: json['fullName'] as String,
    email: json['email'] as String,
    isPro: json['isPro'] as bool,
    suspended: json['suspended'] as bool,
    lastActiveOn: json['lastActiveOn'] as String?,
    joinedOn: json['joinedOn'] as String,
  );
}

/// One page of the Users list.
class AdminUsersPage {
  const AdminUsersPage({
    required this.users,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<AdminUserRow> users;
  final int page;
  final int limit;

  /// Every trainee the search and filter match, not only this page's.
  final int total;

  bool get hasMore => page * limit < total;

  factory AdminUsersPage.fromJson(Map<String, dynamic> json) => AdminUsersPage(
    users: [
      for (final user in json['users'] as List)
        AdminUserRow.fromJson(user as Map<String, dynamic>),
    ],
    page: (json['page'] as num).toInt(),
    limit: (json['limit'] as num).toInt(),
    total: (json['total'] as num).toInt(),
  );
}

/// A trainee's page: account information only.
class AdminUserDetail {
  const AdminUserDetail({
    required this.id,
    required this.fullName,
    required this.email,
    required this.joinedOn,
    required this.emailVerified,
    required this.signInMethods,
    required this.lastActiveOn,
    required this.isPro,
    required this.proSource,
    required this.proUntil,
    required this.suspendedAt,
  });

  final int id;
  final String fullName;
  final String email;
  final String joinedOn;
  final bool emailVerified;

  /// `password` and/or `google`.
  final List<String> signInMethods;
  final String? lastActiveOn;
  final bool isPro;

  /// `paid`, `granted`, or null when not Pro.
  final String? proSource;

  /// When a paid period ends; null for granted Pro and for free.
  final DateTime? proUntil;
  final DateTime? suspendedAt;

  bool get suspended => suspendedAt != null;

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) {
    final pro = json['pro'] as Map<String, dynamic>;
    final until = pro['until'] as String?;
    final suspendedAt = json['suspendedAt'] as String?;
    return AdminUserDetail(
      id: (json['id'] as num).toInt(),
      fullName: json['fullName'] as String,
      email: json['email'] as String,
      joinedOn: json['joinedOn'] as String,
      emailVerified: json['emailVerified'] as bool,
      signInMethods: [
        for (final method in json['signInMethods'] as List) method as String,
      ],
      lastActiveOn: json['lastActiveOn'] as String?,
      isPro: pro['isPro'] as bool,
      proSource: pro['source'] as String?,
      proUntil: until == null ? null : DateTime.parse(until),
      suspendedAt: suspendedAt == null ? null : DateTime.parse(suspendedAt),
    );
  }
}
