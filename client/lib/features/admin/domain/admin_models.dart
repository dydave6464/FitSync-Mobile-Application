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

/// One exercise demo in the Content tab's Animations list.
class AdminExercise {
  const AdminExercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.thumbnailUrl,
    required this.animationUrl,
    required this.status,
    required this.pendingReason,
  });

  final int id;

  /// As the catalogue stores it, lowercase: shown through
  /// `exerciseDisplayName`, `muscleLabel` and `equipmentLabel`.
  final String name;
  final String? muscleGroup;
  final String? equipment;

  /// Server-relative paths (`/storage/...`), null when there is none.
  final String? thumbnailUrl;
  final String? animationUrl;

  /// `pending` or `live`.
  final String status;

  /// Why a pending exercise was held back from the library: `cardio`,
  /// `rare_equipment`, or null.
  final String? pendingReason;

  bool get live => status == 'live';

  factory AdminExercise.fromJson(Map<String, dynamic> json) => AdminExercise(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    muscleGroup: json['muscleGroup'] as String?,
    equipment: json['equipment'] as String?,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    animationUrl: json['animationUrl'] as String?,
    status: json['status'] as String,
    pendingReason: json['pendingReason'] as String?,
  );
}

/// One page of the Animations list, with the whole catalogue's counts for
/// the Pending and Live chips (they don't follow the search).
class AdminExercisesPage {
  const AdminExercisesPage({
    required this.exercises,
    required this.pendingCount,
    required this.liveCount,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<AdminExercise> exercises;
  final int pendingCount;
  final int liveCount;
  final int page;
  final int limit;

  /// Every exercise the chip and search match, not only this page's.
  final int total;

  bool get hasMore => page * limit < total;

  factory AdminExercisesPage.fromJson(Map<String, dynamic> json) {
    final counts = json['counts'] as Map<String, dynamic>;
    return AdminExercisesPage(
      exercises: [
        for (final exercise in json['exercises'] as List)
          AdminExercise.fromJson(exercise as Map<String, dynamic>),
      ],
      pendingCount: (counts['pending'] as num).toInt(),
      liveCount: (counts['live'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      limit: (json['limit'] as num).toInt(),
      total: (json['total'] as num).toInt(),
    );
  }
}

double? _optional(Object? value) => (value as num?)?.toDouble();

/// One of FitSync's own foods (never a FatSecret copy), per serving.
class AdminFood {
  const AdminFood({
    required this.id,
    required this.name,
    required this.category,
    required this.foodType,
    required this.servingDesc,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.sugarG,
    required this.sodiumMg,
    required this.hidden,
  });

  final int id;
  final String name;

  /// `filipino` or `international`.
  final String category;

  /// One of the nine `food_type` values (see `foodTypeLabels`), or null for
  /// an older food never given one.
  final String? foodType;
  final String? servingDesc;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// Unknown is null, not 0.
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;

  /// Left out of food search, Recents and Snap a meal.
  final bool hidden;

  factory AdminFood.fromJson(Map<String, dynamic> json) => AdminFood(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    category: json['category'] as String,
    foodType: json['foodType'] as String?,
    servingDesc: json['servingDesc'] as String?,
    kcal: (json['kcal'] as num).round(),
    proteinG: (json['proteinG'] as num).toDouble(),
    carbsG: (json['carbsG'] as num).toDouble(),
    fatG: (json['fatG'] as num).toDouble(),
    fiberG: _optional(json['fiberG']),
    sugarG: _optional(json['sugarG']),
    sodiumMg: _optional(json['sodiumMg']),
    hidden: json['hidden'] as bool,
  );
}

/// One page of the Meals list, with the counts of all FitSync's own foods
/// for the Shown and Hidden chips (they don't follow the search).
class AdminFoodsPage {
  const AdminFoodsPage({
    required this.foods,
    required this.shownCount,
    required this.hiddenCount,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<AdminFood> foods;
  final int shownCount;
  final int hiddenCount;
  final int page;
  final int limit;
  final int total;

  bool get hasMore => page * limit < total;

  factory AdminFoodsPage.fromJson(Map<String, dynamic> json) {
    final counts = json['counts'] as Map<String, dynamic>;
    return AdminFoodsPage(
      foods: [
        for (final food in json['foods'] as List)
          AdminFood.fromJson(food as Map<String, dynamic>),
      ],
      shownCount: (counts['shown'] as num).toInt(),
      hiddenCount: (counts['hidden'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      limit: (json['limit'] as num).toInt(),
      total: (json['total'] as num).toInt(),
    );
  }
}

/// What the food form sends, on add and on edit alike. Every field is sent,
/// an empty optional one as null: on an edit, null clears it, and a null
/// [kcal] has the server work the calories out from protein, carbs and fat
/// (the typed-food rule).
class FoodInput {
  const FoodInput({
    required this.name,
    required this.category,
    required this.foodType,
    required this.servingDesc,
    this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.fiberG,
    this.sugarG,
    this.sodiumMg,
  });

  final String name;

  /// `filipino` or `international`.
  final String category;
  final String foodType;
  final String servingDesc;

  /// The label's calories, or null to work them out.
  final int? kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double? fiberG;
  final double? sugarG;
  final double? sodiumMg;

  Map<String, dynamic> toJson() => {
    'name': name,
    'category': category,
    'foodType': foodType,
    'servingDesc': servingDesc,
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'fiberG': fiberG,
    'sugarG': sugarG,
    'sodiumMg': sodiumMg,
  };
}
