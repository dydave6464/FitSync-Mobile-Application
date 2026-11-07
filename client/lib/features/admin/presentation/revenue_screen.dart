import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/dates.dart' show monthShort;
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';
import 'providers.dart';
import 'revenue_chart.dart';
import 'widgets/admin_widgets.dart';

/// How far back the month switcher goes, at most.
const _monthsBack = 24;

/// [ym] moved by [by] months: `('2026-01', -1)` is `'2025-12'`.
String _shift(String ym, int by) {
  final index =
      int.parse(ym.substring(0, 4)) * 12 + int.parse(ym.substring(5)) - 1 + by;
  final month = (index % 12 + 1).toString().padLeft(2, '0');
  return '${index ~/ 12}-$month';
}

/// The admin's Revenue tab: one Manila month at a time, its total against
/// the month before, Pro and ads apart, the last six months as bars, and
/// every payment that month.
class RevenueScreen extends ConsumerStatefulWidget {
  const RevenueScreen({super.key});

  @override
  ConsumerState<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends ConsumerState<RevenueScreen> {
  /// The month shown, `YYYY-MM`; null is the server's own this month, which
  /// never asks for a month the server thinks is still to come.
  String? _month;

  /// The month of the first payment or ad, as last heard: kept while
  /// another month loads, so the switcher does not flicker off.
  String? _firstMonth;

  /// The server's own this month, as last heard.
  String? _serverMonth;

  Future<void> _refresh() async {
    try {
      ref.invalidate(adminRevenueProvider(_month));
      await ref.read(adminRevenueProvider(_month).future);
    } catch (_) {
      // The failure is the provider's state, drawn as the error below.
    }
  }

  @override
  Widget build(BuildContext context) {
    final revenue = ref.watch(adminRevenueProvider(_month));
    final loaded = revenue.value;
    if (loaded != null) {
      _firstMonth = loaded.firstMonth;
      if (_month == null) _serverMonth = loaded.month;
    }
    // The later of the phone's month and the server's: around midnight on
    // a month's last day the two can differ, and the server's decides what
    // it will answer.
    final phone = ref.watch(adminTodayProvider).substring(0, 7);
    final server = _serverMonth;
    final current = server != null && server.compareTo(phone) > 0
        ? server
        : phone;
    final shown = _month ?? loaded?.month ?? current;

    final floor = _shift(current, -_monthsBack);
    final first = _firstMonth ?? current;
    final earliest = first.compareTo(floor) > 0 ? first : floor;
    final canGoBack = shown.compareTo(earliest) > 0;
    final canGoOn = shown.compareTo(current) < 0;

    void go(int by) {
      final target = _shift(shown, by);
      setState(() => _month = target.compareTo(current) >= 0 ? null : target);
    }

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          // Pull to refresh works on a short page and on an error too.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Semantics(
              header: true,
              child: Text(
                'Revenue',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            _MonthSwitcher(
              label: monthLabel(shown),
              onPrevious: canGoBack ? () => go(-1) : null,
              onNext: canGoOn ? () => go(1) : null,
            ),
            const SizedBox(height: 12),
            ...revenue.when(
              data: (value) => _body(value, current: current),
              error: (error, _) => [
                FsRetry(
                  message: userMessage(error),
                  buttonKey: const Key('admin.revenue.retry'),
                  onRetry: () => ref.invalidate(adminRevenueProvider(_month)),
                ),
              ],
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(RevenueMonth r, {required String current}) {
    final isCurrent = r.month == current;
    final empty = r.proPayments.isEmpty && r.adPayments.isEmpty;
    return [
      _TotalCard(revenue: r, isCurrent: isCurrent),
      const SizedBox(height: 10),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _PartCard(
                title: 'Pro subscriptions',
                value: formatPhp(r.proTotalPhp),
                detail: '${r.proMonthly} monthly · ${r.proAnnual} yearly',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PartCard(
                title: 'Ads',
                value: formatPhp(r.adsTotalPhp),
                detail: r.adsCount == 1 ? '1 ad' : '${r.adsCount} ads',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      FsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Heading('Last 6 months'),
            const SizedBox(height: 12),
            RevenueChart(months: r.lastSixMonths),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (empty) AdminEmpty(message: 'No payments in ${monthLabel(r.month)}.'),
      if (r.proPayments.isNotEmpty)
        ..._section('Pro payments', [
          for (final p in r.proPayments)
            _PaymentRow(
              name: p.name ?? 'Deleted account',
              dim: p.name == null,
              detail:
                  '${p.plan == 'annual' ? 'Yearly' : 'Monthly'} · '
                  '${_methodLabel(p.method)} · ${_dayLabel(p.paidOn)}',
              amount: formatPhp(p.amountPhp),
            ),
        ]),
      if (r.adPayments.isNotEmpty)
        ..._section('Ad payments', [
          for (final a in r.adPayments)
            _PaymentRow(
              name: a.advertiser,
              detail: '${a.title} · ${runLabel(a.startsOn, a.endsOn)}',
              amount: formatPhp(a.amountPhp),
            ),
        ]),
    ];
  }

  /// A heading over one card of [rows], with a hairline between rows.
  List<Widget> _section(String title, List<Widget> rows) => [
    _Heading(title),
    const SizedBox(height: 8),
    FsCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.fs.line),
            rows[i],
          ],
        ],
      ),
    ),
    const SizedBox(height: 16),
  ];
}

/// `gcash` → "GCash", `paymaya` → "Maya", `card` → "Card"; "—" when none
/// was recorded.
String _methodLabel(String? method) => switch (method) {
  'gcash' => 'GCash',
  'paymaya' => 'Maya',
  'card' => 'Card',
  null => '—',
  final other => other,
};

/// "2026-11-05" → "5 Nov", as the Pro screen writes a day.
String _dayLabel(String ymd) {
  final parts = ymd.split('-');
  // A no-break space: "3" and "Nov" stay on one line.
  return '${int.parse(parts[2])}\u00A0${monthShort[int.parse(parts[1]) - 1]}';
}

/// "‹ November 2026 ›". A null callback leaves its button off: next on the
/// current month, previous at the first month with money in it.
class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    Widget button(IconData icon, String tip, VoidCallback? onPressed) =>
        IconButton(
          icon: Icon(icon),
          tooltip: tip,
          color: t.text,
          disabledColor: t.text3.withValues(alpha: 0.4),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: onPressed,
        );
    return Row(
      children: [
        button(Icons.chevron_left, 'Previous month', onPrevious),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        button(Icons.chevron_right, 'Next month', onNext),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// The month's total, and how it moved from the month before.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.revenue, required this.isCurrent});

  final RevenueMonth revenue;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final r = revenue;
    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FsOneLine(formatPhp(r.totalPhp), style: fsNum(t, size: 28)),
          const SizedBox(height: 2),
          Text(
            isCurrent ? 'this month' : 'in ${monthLabel(r.month)}',
            style: TextStyle(fontSize: 12.5, color: t.text2),
          ),
          const SizedBox(height: 6),
          ChangeLine(
            deltaCount: null,
            deltaPhp: r.totalPhp - r.previousTotalPhp,
            semanticsPrefix: isCurrent
                ? 'Change from last month:'
                : 'Change from the month before:',
          ),
        ],
      ),
    );
  }
}

/// Pro or Ads: its share of the month and what made it up.
class _PartCard extends StatelessWidget {
  const _PartCard({
    required this.title,
    required this.value,
    required this.detail,
  });

  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return FsCard(
      small: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shrunk rather than broken mid-word in a half-width card at
          // large text ("Pro subscri" / "ptions").
          FsOneLine(title, style: TextStyle(fontSize: 12, color: t.text2)),
          const SizedBox(height: 6),
          FsOneLine(value, style: fsNum(t, size: 19)),
          const SizedBox(height: 2),
          Text(detail, style: TextStyle(fontSize: 11.5, color: t.text3)),
        ],
      ),
    );
  }
}

/// One payment: who paid and how on the left, the amount on the right.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.name,
    required this.detail,
    required this.amount,
    this.dim = false,
  });

  final String name;
  final String detail;
  final String amount;

  /// A deleted account's stand-in name, in the dim ink.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: dim ? t.text3 : t.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(fontSize: 12, color: t.text2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(amount, style: fsNum(t, size: 14)),
        ],
      ),
    );
  }
}
