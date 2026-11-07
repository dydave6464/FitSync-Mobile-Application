import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/dates.dart';
import '../../../core/numbers.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_charts.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';
import 'providers.dart';
import 'widgets/admin_widgets.dart';

/// The admin's first tab: four figures and the last 30 days of sign-ups,
/// as the prototype's admin dashboard draws them, with three changes from
/// the spec: "MRR" is "Pro revenue, this month", changes are signed counts
/// or pesos with an arrow (never percentages), and the bell is Sign out.
class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    try {
      ref.invalidate(adminOverviewProvider);
      await ref.read(adminOverviewProvider.future);
    } catch (_) {
      // The failure is the provider's state, drawn as the error below.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(adminOverviewProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          // Pull to refresh works on a short page and on an error too.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Above every state, so Sign out is there even when the figures
            // will not load.
            const _Header(),
            const SizedBox(height: 16),
            ...overview.when(
              data: (value) => [
                _Figures(overview: value),
                const SizedBox(height: 12),
                _Signups(overview: value),
              ],
              error: (error, _) => [
                FsRetry(
                  message: userMessage(error),
                  buttonKey: const Key('admin.overview.retry'),
                  onRetry: () => ref.invalidate(adminOverviewProvider),
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
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    return Row(
      children: [
        const ExcludeSemantics(child: FsIconTile(icon: Icons.shield_outlined)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Shrunk rather than wrapped at large text: beside Sign out the
            // column can be narrow enough to break "Overview" letter by
            // letter.
            children: [
              FsOneLine(
                'FitSync Admin',
                style: TextStyle(fontSize: 11.5, color: t.text3),
              ),
              Semantics(
                header: true,
                child: FsOneLine(
                  'Overview',
                  style: Theme.of(context).textTheme.titleMedium!
                      .copyWith(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // The prototype's bell, as a text button. An admin has no reminders
        // on the phone to lose, so unlike the trainee's Sign out this one
        // does not ask first.
        FsButton(
          key: const Key('admin.signOut'),
          label: 'Sign out',
          kind: FsButtonKind.ghost,
          small: true,
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
        ),
      ],
    );
  }
}

/// "1,204".
String _count(int n) => groupThousands(n.toDouble());

/// The 2×2 grid of figure cards.
class _Figures extends ConsumerWidget {
  const _Figures({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = overview;
    void open(int tab, {String? usersFilter}) => ref
        .read(adminTabProvider.notifier)
        .select(tab, usersFilter: usersFilter);

    final activeDelta = o.activeUsers - o.previousActiveUsers;
    final proDelta = o.proRevenueThisMonth - o.proRevenueLastMonth;
    final adDelta = o.adRevenueThisMonth - o.adRevenueLastMonth;

    final active = _FigureCard(
      icon: Icons.people_outline,
      title: 'Active users',
      value: _count(o.activeUsers),
      change: ChangeLine(
        deltaCount: activeDelta,
        semanticsPrefix: 'Change from the 30 days before:',
      ),
      spoken:
          'Active users, ${_count(o.activeUsers)}, '
          '${changeWords(deltaCount: activeDelta)} from the 30 days before',
      onTap: () => open(1, usersFilter: 'all'),
    );
    final pro = _FigureCard(
      icon: Icons.workspace_premium_outlined,
      title: 'Pro members',
      value: _count(o.proMembers),
      spoken: 'Pro members, ${_count(o.proMembers)}',
      onTap: () => open(1, usersFilter: 'pro'),
    );
    final proRevenue = _FigureCard(
      icon: Icons.payments_outlined,
      title: 'Pro revenue',
      subtitle: 'this month',
      value: formatPhp(o.proRevenueThisMonth),
      change: ChangeLine(
        deltaCount: null,
        deltaPhp: proDelta,
        semanticsPrefix: 'Change from last month:',
      ),
      spoken:
          'Pro revenue this month, ${formatPhp(o.proRevenueThisMonth)}, '
          '${changeWords(deltaCount: null, deltaPhp: proDelta)} from last month',
      onTap: () => open(3),
    );
    final adRevenue = _FigureCard(
      icon: Icons.campaign_outlined,
      title: 'Ad revenue',
      subtitle: 'this month',
      value: formatPhp(o.adRevenueThisMonth),
      change: ChangeLine(
        deltaCount: null,
        deltaPhp: adDelta,
        semanticsPrefix: 'Change from last month:',
      ),
      spoken:
          'Ad revenue this month, ${formatPhp(o.adRevenueThisMonth)}, '
          '${changeWords(deltaCount: null, deltaPhp: adDelta)} from last month',
      onTap: () => open(3),
    );

    Widget pair(Widget a, Widget b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: a),
          const SizedBox(width: 10),
          Expanded(child: b),
        ],
      ),
    );

    return Column(
      children: [
        pair(active, pro),
        const SizedBox(height: 10),
        pair(proRevenue, adRevenue),
      ],
    );
  }
}

class _FigureCard extends StatelessWidget {
  const _FigureCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.spoken,
    required this.onTap,
    this.subtitle,
    this.change,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String value;
  final Widget? change;

  /// The whole card in one sentence: its figures are read together.
  final String spoken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return FsCard(
      small: true,
      onTap: onTap,
      child: Semantics(
        label: spoken,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: t.text3),
            const SizedBox(height: 8),
            FsOneLine(value, style: fsNum(t, size: 21)),
            const SizedBox(height: 2),
            Text(title, style: TextStyle(fontSize: 12, color: t.text2)),
            if (subtitle != null)
              Text(subtitle!, style: TextStyle(fontSize: 11, color: t.text3)),
            if (change != null) ...[const SizedBox(height: 6), change!],
          ],
        ),
      ),
    );
  }
}

/// New sign-ups over the last 30 Manila days: bars rather than the
/// prototype's area, because each day's count stands alone and `fs_charts`
/// has no area chart.
class _Signups extends StatelessWidget {
  const _Signups({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final days = overview.signupDays;
    final total = overview.signupsTotal;
    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'New sign-ups',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(child: FsTag('Last 30 days')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            total == 1 ? '1 new trainee' : '$total new trainees',
            style: TextStyle(fontSize: 12.5, color: t.text2),
          ),
          const SizedBox(height: 12),
          FsBarChart(
            label: 'New sign-ups, last 30 days: $total',
            height: 96,
            bars: [
              for (var i = 0; i < days.length; i++)
                _bar(days[i], labelled: (days.length - 1 - i) % 7 == 0),
            ],
          ),
        ],
      ),
    );
  }

  /// Every seventh day carries its date, counted back from today's so the
  /// newest bar is always named.
  FsChartBar _bar(SignupDay day, {required bool labelled}) {
    final name = shortDate(DateTime.parse(day.date));
    return FsChartBar(
      value: day.count.toDouble(),
      label: labelled ? name : '',
      tooltip: '$name: ${day.count}',
    );
  }
}
