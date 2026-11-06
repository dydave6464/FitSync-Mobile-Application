/// What Pro is for this account, from `GET /api/v1/pro`.
library;

enum ProPlan {
  monthly('monthly', 1),
  annual('annual', 12);

  const ProPlan(this.wire, this.months);

  /// The name the server uses.
  final String wire;

  /// How long one payment adds, as the server's plans define it
  /// (server/src/lib/pro-plans.js). One payment, one period: nothing renews.
  final int months;

  static ProPlan? fromWire(Object? value) => switch (value) {
    'monthly' => ProPlan.monthly,
    'annual' => ProPlan.annual,
    _ => null,
  };
}

/// Paid for a period, or granted by hand (demo and teacher accounts, which
/// never expire).
enum ProSource { paid, granted }

/// One plan's terms as the server states them: what one payment costs and
/// how many months it adds.
class ProPlanTerms {
  const ProPlanTerms({required this.pricePhp, required this.months});

  final int pricePhp;
  final int months;
}

/// The server's prices in pesos -- the only place they are set.
class ProPrices {
  const ProPrices({required this.monthly, required this.annual});

  final int monthly;
  final int annual;

  int forPlan(ProPlan plan) => plan == ProPlan.monthly ? monthly : annual;

  /// The annual card's headline figure: a year's price per month.
  int get annualPerMonth => (annual / 12).round();

  /// The annual card's tag, e.g. 40 for "-40%".
  int get annualSavingPct => (100 - annual / 12 / monthly * 100).round();
}

class ProStatus {
  const ProStatus({
    required this.pro,
    required this.source,
    required this.until,
    required this.plan,
    required this.method,
    required this.endsSoon,
    required this.plans,
    this.renews = false,
    this.nextPeriodStartsAt,
  });

  factory ProStatus.fromJson(Map<String, dynamic> json) {
    final prices = json['prices'] as Map<String, dynamic>;
    final plans = json['plans'] as Map<String, dynamic>?;
    final until = json['until'] as String?;
    final next = json['nextPeriodStartsAt'] as String?;
    return ProStatus(
      pro: json['pro'] as bool? ?? false,
      source: switch (json['source']) {
        'paid' => ProSource.paid,
        'granted' => ProSource.granted,
        _ => null,
      },
      until: until == null ? null : DateTime.parse(until),
      plan: ProPlan.fromWire(json['plan']),
      method: json['method'] as String?,
      endsSoon: json['endsSoon'] as bool? ?? false,
      // An older server sends only prices: its months are the ones the
      // app was built with.
      plans: {
        for (final plan in ProPlan.values)
          plan: switch (plans?[plan.wire]) {
            {'pricePhp': final num price, 'months': final num months} =>
              ProPlanTerms(pricePhp: price.toInt(), months: months.toInt()),
            _ => ProPlanTerms(
              pricePhp: (prices[plan.wire] as num).toInt(),
              months: plan.months,
            ),
          },
      },
      renews: json['renews'] as bool? ?? false,
      nextPeriodStartsAt: next == null ? null : DateTime.parse(next),
    );
  }

  final bool pro;
  final ProSource? source;

  /// When a paid period ends; null when free or granted.
  final DateTime? until;
  final ProPlan? plan;

  /// PayMongo's name for how the last period was paid: gcash, paymaya, card.
  final String? method;

  /// A paid period that ends within 3 days.
  final bool endsSoon;

  /// Every plan's price and months, as the server states them.
  final Map<ProPlan, ProPlanTerms> plans;

  /// Whether Pro renews by itself. Always false today: each payment buys
  /// one period.
  final bool renews;

  /// When the months of a payment made now would begin: the end of the
  /// period running now. Null when a payment now starts at once.
  final DateTime? nextPeriodStartsAt;

  /// The prices, from [plans].
  ProPrices get prices => ProPrices(
    monthly: plans[ProPlan.monthly]!.pricePhp,
    annual: plans[ProPlan.annual]!.pricePhp,
  );
}

/// Where to pay for one attempt.
class ProCheckout {
  const ProCheckout({required this.paymentId, required this.checkoutUrl});

  factory ProCheckout.fromJson(Map<String, dynamic> json) => ProCheckout(
    paymentId: (json['paymentId'] as num).toInt(),
    checkoutUrl: Uri.parse(json['checkoutUrl'] as String),
  );

  final int paymentId;
  final Uri checkoutUrl;
}

enum ProPaymentState { paid, pending }

/// The server's answer to "was this paid?", with the account's status after it.
class ProConfirmation {
  const ProConfirmation({required this.state, required this.status});

  factory ProConfirmation.fromJson(Map<String, dynamic> json) =>
      ProConfirmation(
        state: json['status'] == 'paid'
            ? ProPaymentState.paid
            : ProPaymentState.pending,
        status: ProStatus.fromJson(json['pro'] as Map<String, dynamic>),
      );

  final ProPaymentState state;
  final ProStatus status;
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "26 Nov 2026", in the phone's time zone.
String formatProDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// "26 Nov", in the phone's time zone.
String formatProDay(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]}';
}

/// "₱1,788".
String peso(int php) {
  final digits = php.toString();
  final out = StringBuffer('₱');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// How the app names PayMongo's payment methods; null for one it doesn't know.
String? methodLabel(String? method) => switch (method) {
  'gcash' => 'GCash',
  'paymaya' => 'Maya',
  'card' => 'card',
  _ => null,
};

/// The Settings Pro card's second line. [premium] is what the profile says;
/// it answers while [status] is not in yet (loading, or a failed read), so a
/// Pro account is not shown the free pitch.
String proCardSubtitle(ProStatus? status, {bool premium = false}) {
  if (status == null && premium) return 'Pro';
  if (status == null || !status.pro) {
    return 'Muscle analytics, Snap a meal, unlimited AI cues';
  }
  if (status.source == ProSource.granted) return 'Pro (granted)';
  final until = status.until;
  if (until == null) return 'Pro';
  if (status.endsSoon) {
    return 'Pro ends on ${formatProDay(until)}. Renew to keep Snap a meal and your analytics.';
  }
  return 'Pro until ${formatProDate(until)}';
}
