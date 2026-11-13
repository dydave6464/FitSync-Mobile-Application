/// What the admin screens read from `/api/v1/admin/*` (spec Appendix A).
///
/// Account information only: nothing about a trainee's body, food, workouts
/// or health answers is sent to the admin app, so none of it is modelled.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'admin_format.dart' show mediaUrl;

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

/// One page of a Content list, whatever it lists: what the lists' shared
/// paging reads.
abstract interface class AdminPaged<T> {
  List<T> get items;
  int get page;
  bool get hasMore;
}

/// One page of the Animations list, with the whole catalogue's counts for
/// the Pending and Live chips (they don't follow the search).
class AdminExercisesPage implements AdminPaged<AdminExercise> {
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
  @override
  final int page;
  final int limit;

  /// Every exercise the chip and search match, not only this page's.
  final int total;

  @override
  List<AdminExercise> get items => exercises;

  @override
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
    this.suggestMeals = const [],
    this.suggestWithRice = false,
    this.contains = const [],
    this.photoUrl,
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

  /// The meals trainees are offered it for as a local meal, in meal order
  /// (`breakfast`, `lunch`, `dinner`, `snack`); empty when never.
  final List<String> suggestMeals;

  /// Offered as ulam with 1 cup of white rice (beside a main meal only).
  final bool suggestWithRice;

  /// The food groups it is often made with (`foodGroups`, in that order):
  /// trainees who avoid one are not suggested it. Empty when untagged.
  final List<String> contains;

  /// The dish's photo as a full URL, or null when it has none.
  final String? photoUrl;

  bool get suggested => suggestMeals.isNotEmpty;

  /// [mediaBase], the server's address, turns the photo's `/storage/...`
  /// path into a full URL; without it the path is kept as sent.
  factory AdminFood.fromJson(Map<String, dynamic> json, {String? mediaBase}) =>
      AdminFood(
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
        suggestMeals: [
          for (final meal in json['suggestMeals'] as List? ?? const [])
            meal as String,
        ],
        suggestWithRice: json['suggestWithRice'] as bool? ?? false,
        contains: [
          for (final group in json['contains'] as List? ?? const [])
            group as String,
        ],
        photoUrl: switch (json['photoUrl'] as String?) {
          final path? when mediaBase != null => mediaUrl(mediaBase, path),
          final path => path,
        },
      );
}

/// One page of the Meals list, with the counts of all FitSync's own foods
/// for the Shown, Hidden and Suggested chips (they don't follow the search).
class AdminFoodsPage implements AdminPaged<AdminFood> {
  const AdminFoodsPage({
    required this.foods,
    required this.shownCount,
    required this.hiddenCount,
    required this.suggestedCount,
    required this.page,
    required this.limit,
    required this.total,
  });

  final List<AdminFood> foods;
  final int shownCount;
  final int hiddenCount;
  final int suggestedCount;
  @override
  final int page;
  final int limit;
  final int total;

  @override
  List<AdminFood> get items => foods;

  @override
  bool get hasMore => page * limit < total;

  /// [mediaBase] as in [AdminFood.fromJson].
  factory AdminFoodsPage.fromJson(
    Map<String, dynamic> json, {
    String? mediaBase,
  }) {
    final counts = json['counts'] as Map<String, dynamic>;
    return AdminFoodsPage(
      foods: [
        for (final food in json['foods'] as List)
          AdminFood.fromJson(
            food as Map<String, dynamic>,
            mediaBase: mediaBase,
          ),
      ],
      shownCount: (counts['shown'] as num).toInt(),
      hiddenCount: (counts['hidden'] as num).toInt(),
      suggestedCount: (counts['suggested'] as num?)?.toInt() ?? 0,
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
    this.suggestMeals = const [],
    this.suggestWithRice = false,
    this.contains = const [],
    this.image,
    this.mimeType,
    this.removePhoto = false,
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

  /// The meals it is suggested for, in meal order; empty for none.
  final List<String> suggestMeals;

  /// With 1 cup of rice; only ever true beside a main meal.
  final bool suggestWithRice;

  /// The food groups it is often made with; empty for none.
  final List<String> contains;

  /// A new photo: a JPEG's or PNG's bytes, with its [mimeType]. Null keeps
  /// the food's own.
  final Uint8List? image;
  final String? mimeType;

  /// Takes the food's photo away; never with an [image].
  final bool removePhoto;

  /// The photo is sent only when changed: an untouched one sends neither
  /// `image` nor `removePhoto`.
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
    'suggestMeals': suggestMeals,
    'suggestWithRice': suggestWithRice,
    'contains': contains,
    // Plain base64, no `data:` prefix: the server's image rule.
    if (image case final bytes?) ...{
      'image': base64Encode(bytes),
      'mimeType': mimeType,
    },
    if (removePhoto) 'removePhoto': true,
  };
}

/// One of FitSync's own ads, as the Ads list and form show it.
class AdminAd {
  const AdminAd({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.linkUrl,
    required this.advertiser,
    required this.amountPhp,
    required this.startsOn,
    required this.endsOn,
    required this.active,
    required this.status,
    required this.views,
    required this.taps,
  });

  final int id;
  final String title;

  /// A server media path (`/storage/ads/...`); see `mediaUrl`.
  final String imageUrl;

  /// The https link the card opens, or null for an ad with none.
  final String? linkUrl;
  final String advertiser;

  /// What the advertiser paid, counted as revenue in the month it starts.
  final double amountPhp;

  /// The run, Manila `YYYY-MM-DD`, both days included.
  final String startsOn;
  final String endsOn;

  /// False is paused.
  final bool active;

  /// `running`, `scheduled`, `ended` or `paused`, worked out by the server
  /// for its own today.
  final String status;
  final int views;
  final int taps;

  factory AdminAd.fromJson(Map<String, dynamic> json) => AdminAd(
    id: (json['id'] as num).toInt(),
    title: json['title'] as String,
    imageUrl: json['imageUrl'] as String,
    linkUrl: json['linkUrl'] as String?,
    advertiser: json['advertiser'] as String,
    amountPhp: _php(json['amountPhp']),
    startsOn: json['startsOn'] as String,
    endsOn: json['endsOn'] as String,
    active: json['active'] as bool,
    status: json['status'] as String,
    views: (json['views'] as num).toInt(),
    taps: (json['taps'] as num).toInt(),
  );
}

/// What the ad form sends, on add and on edit alike. Every field is sent,
/// an empty link as null (on an edit, null takes the link away). The image
/// goes only when one was picked: required to add, optional to edit.
class AdInput {
  const AdInput({
    required this.title,
    required this.advertiser,
    required this.amountPhp,
    required this.startsOn,
    required this.endsOn,
    this.linkUrl,
    this.image,
    this.mimeType,
  });

  final String title;
  final String advertiser;
  final double amountPhp;

  /// `YYYY-MM-DD`.
  final String startsOn;
  final String endsOn;
  final String? linkUrl;

  /// A JPEG's or PNG's bytes, with its [mimeType].
  final Uint8List? image;
  final String? mimeType;

  Map<String, dynamic> toJson() => {
    'title': title,
    'advertiser': advertiser,
    'amountPhp': amountPhp,
    'startsOn': startsOn,
    'endsOn': endsOn,
    'linkUrl': linkUrl,
    // Plain base64, no `data:` prefix: the server's image rule.
    if (image case final bytes?) ...{
      'image': base64Encode(bytes),
      'mimeType': mimeType,
    },
  };
}

/// One month of the Revenue chart: what Pro and ads brought in.
class RevenueBar {
  const RevenueBar({
    required this.month,
    required this.proPhp,
    required this.adsPhp,
  });

  /// `YYYY-MM`.
  final String month;
  final double proPhp;
  final double adsPhp;

  double get totalPhp => proPhp + adsPhp;

  factory RevenueBar.fromJson(Map<String, dynamic> json) => RevenueBar(
    month: json['month'] as String,
    proPhp: _php(json['proPhp']),
    adsPhp: _php(json['adsPhp']),
  );
}

/// A Pro payment, counted in the month it was paid. [name] is null once the
/// trainee's account is deleted: the amount is kept, the person is not.
class RevenueProPayment {
  const RevenueProPayment({
    required this.paymentId,
    required this.name,
    required this.plan,
    required this.method,
    required this.amountPhp,
    required this.paidOn,
  });

  final int paymentId;
  final String? name;

  /// `monthly` or `annual`.
  final String plan;

  /// `gcash`, `paymaya`, `card`, or null when none was recorded.
  final String? method;
  final double amountPhp;

  /// Manila `YYYY-MM-DD`.
  final String paidOn;

  factory RevenueProPayment.fromJson(Map<String, dynamic> json) =>
      RevenueProPayment(
        paymentId: (json['paymentId'] as num).toInt(),
        name: json['name'] as String?,
        plan: json['plan'] as String,
        method: json['method'] as String?,
        amountPhp: _php(json['amountPhp']),
        paidOn: json['paidOn'] as String,
      );
}

/// What an advertiser paid for an ad, counted in the month it starts.
class RevenueAdPayment {
  const RevenueAdPayment({
    required this.adId,
    required this.advertiser,
    required this.title,
    required this.amountPhp,
    required this.startsOn,
    required this.endsOn,
  });

  final int adId;
  final String advertiser;
  final String title;
  final double amountPhp;

  /// Manila `YYYY-MM-DD`, both days included.
  final String startsOn;
  final String endsOn;

  factory RevenueAdPayment.fromJson(Map<String, dynamic> json) =>
      RevenueAdPayment(
        adId: (json['adId'] as num).toInt(),
        advertiser: json['advertiser'] as String,
        title: json['title'] as String,
        amountPhp: _php(json['amountPhp']),
        startsOn: json['startsOn'] as String,
        endsOn: json['endsOn'] as String,
      );
}

/// One Manila month on the Revenue tab.
class RevenueMonth {
  const RevenueMonth({
    required this.month,
    required this.totalPhp,
    required this.previousTotalPhp,
    required this.proTotalPhp,
    required this.proMonthly,
    required this.proAnnual,
    required this.adsTotalPhp,
    required this.adsCount,
    required this.lastSixMonths,
    required this.proPayments,
    required this.adPayments,
    required this.firstMonth,
  });

  /// `YYYY-MM`.
  final String month;
  final double totalPhp;
  final double previousTotalPhp;
  final double proTotalPhp;
  final int proMonthly;
  final int proAnnual;
  final double adsTotalPhp;
  final int adsCount;

  /// Six months, oldest first, ending at [month].
  final List<RevenueBar> lastSixMonths;
  final List<RevenueProPayment> proPayments;
  final List<RevenueAdPayment> adPayments;

  /// The month of the first payment or ad, `YYYY-MM`; null when there is
  /// none yet.
  final String? firstMonth;

  factory RevenueMonth.fromJson(Map<String, dynamic> json) {
    final pro = json['pro'] as Map<String, dynamic>;
    final ads = json['ads'] as Map<String, dynamic>;
    return RevenueMonth(
      month: json['month'] as String,
      totalPhp: _php(json['totalPhp']),
      previousTotalPhp: _php(json['previousTotalPhp']),
      proTotalPhp: _php(pro['totalPhp']),
      proMonthly: (pro['monthly'] as num).toInt(),
      proAnnual: (pro['annual'] as num).toInt(),
      adsTotalPhp: _php(ads['totalPhp']),
      adsCount: (ads['count'] as num).toInt(),
      lastSixMonths: [
        for (final bar in json['lastSixMonths'] as List)
          RevenueBar.fromJson(bar as Map<String, dynamic>),
      ],
      proPayments: [
        for (final p in json['proPayments'] as List)
          RevenueProPayment.fromJson(p as Map<String, dynamic>),
      ],
      adPayments: [
        for (final a in json['adPayments'] as List)
          RevenueAdPayment.fromJson(a as Map<String, dynamic>),
      ],
      firstMonth: json['firstMonth'] as String?,
    );
  }
}
