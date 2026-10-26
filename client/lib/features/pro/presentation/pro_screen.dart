import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../profile/presentation/providers.dart' show profileProvider;
import '../domain/pro_status.dart';
import 'providers.dart';

/// What Pro unlocks, in the order a user meets it: volume by muscle (the
/// Progress card and shared reports), Snap a meal (the server refuses a free
/// account, 403 PRO_REQUIRED), and AI cues without the free 3-a-day limit
/// (server/src/db/ai-cue-allowance.js).
const _unlocks = [
  'Volume by muscle on the Progress tab',
  'The same muscle breakdown in reports you share with a coach',
  'Food photo recognition: Snap a meal on the Nutrition tab',
  'Unlimited AI coaching cues (free: 3 exercises a day)',
];

/// While PayMongo's page is open the screen asks the server every
/// [proPollEvery] whether the payment went through -- on an iPhone the page is
/// a sheet inside the app, so there is no "came back" moment to wait for --
/// for at most [proPollTicks] times (10 minutes).
const proPollEvery = Duration(seconds: 4);
const proPollTicks = 150;

const _openFailed = "Couldn't open the payment page. Try again.";

/// Opens the Pro screen. Every lock in the app routes through here.
Future<void> openProScreen(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ProScreen()));

enum _Pay { idle, opening, waiting, notCompleted, checkFailed }

/// What Pro costs, what it unlocks, and buying it through PayMongo
/// (spec 2026-10-26-pro-payments-design). The server makes the checkout for
/// its own price and confirms the payment with PayMongo; this screen only
/// opens the page and asks "was it paid?".
class ProScreen extends ConsumerStatefulWidget {
  const ProScreen({super.key});

  @override
  ConsumerState<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends ConsumerState<ProScreen> {
  ProPlan _plan = ProPlan.annual;
  _Pay _pay = _Pay.idle;
  String? _openError;
  ProCheckout? _checkout;
  bool _checking = false;
  Timer? _poll;
  int _ticks = 0;
  String? _paidLine;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    // The Settings card can keep a status alive for the whole session, so a
    // grant, an expiry or an "ends soon" would otherwise not show here. The
    // cached status stays on screen while the fresh one loads. Only when one
    // is cached: otherwise this screen's own first read is the fresh fetch.
    if (ref.exists(proStatusProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(proStatusProvider);
      });
    }
    // A checkout from an earlier visit may have been paid since the screen
    // closed: ask once, quietly. Only "paid" changes what the screen shows.
    final leftOver = ref.read(proPendingCheckoutProvider);
    if (leftOver != null) {
      _checkout = leftOver;
      _check(userAsked: false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  bool get _awaiting =>
      _pay == _Pay.waiting ||
      _pay == _Pay.notCompleted ||
      _pay == _Pay.checkFailed;

  /// Back from PayMongo's page (an Android tab, or the phone's browser): ask now.
  void _onResume() {
    if (_awaiting) _check(userAsked: true);
  }

  Future<void> _start() async {
    // Two taps inside one frame both reach the button before it rebuilds.
    if (_pay != _Pay.idle) return;
    setState(() {
      _pay = _Pay.opening;
      _openError = null;
      _paidLine = null;
    });
    try {
      final checkout = await ref.read(proRepositoryProvider).checkout(_plan);
      _checkout = checkout;
      if (mounted) {
        ref.read(proPendingCheckoutProvider.notifier).remember(checkout);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _pay = _Pay.idle;
          _openError = _openFailed;
        });
      }
      return;
    }
    if (mounted) await _openPage();
  }

  Future<void> _openPage() async {
    final checkout = _checkout;
    if (checkout == null) return;
    bool opened;
    try {
      opened = await ref.read(proCheckoutOpenerProvider)(checkout.checkoutUrl);
    } catch (_) {
      // url_launcher throws on most failures (on Android it never returns
      // false), e.g. no browser, or the app left while the checkout was made.
      opened = false;
    }
    if (!mounted) return;
    if (!opened) {
      _stopPolling();
      setState(() {
        _pay = _Pay.idle;
        _checkout = null;
        _openError = _openFailed;
      });
      return;
    }
    setState(() => _pay = _Pay.waiting);
    _stopPolling();
    _ticks = 0;
    _poll = Timer.periodic(proPollEvery, (_) {
      _ticks += 1;
      if (_ticks > proPollTicks) {
        _stopPolling();
        if (mounted && _pay == _Pay.waiting) {
          setState(() => _pay = _Pay.notCompleted);
        }
        return;
      }
      _check(userAsked: false);
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  void _reset() {
    _stopPolling();
    setState(() {
      _pay = _Pay.idle;
      _checkout = null;
    });
  }

  /// Asks the server whether the payment went through. A quiet poll that
  /// hears "pending" or fails changes nothing on screen; a check the user
  /// asked for (a button, or coming back to the app) says what it found.
  Future<void> _check({required bool userAsked}) async {
    final checkout = _checkout;
    if (checkout == null || _checking) return;
    setState(() => _checking = true);
    try {
      final result = await ref
          .read(proRepositoryProvider)
          .confirm(checkout.paymentId);
      if (!mounted) return;
      if (result.state == ProPaymentState.paid) {
        _stopPolling();
        final until = result.status.until;
        setState(() {
          _pay = _Pay.idle;
          _checkout = null;
          _paidLine = until == null
              ? "You're Pro"
              : "You're Pro until ${formatProDate(until)}";
        });
        ref.read(proPendingCheckoutProvider.notifier).paid(checkout.paymentId);
        // Every Pro lock reads the profile; refreshing it unlocks them at once.
        ref.invalidate(profileProvider);
        ref.invalidate(proStatusProvider);
      } else if (userAsked) {
        setState(() => _pay = _Pay.notCompleted);
      }
    } catch (_) {
      if (mounted && userAsked) setState(() => _pay = _Pay.checkFailed);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final status = ref.watch(proStatusProvider);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        leading: IconButton(
          key: const Key('pro.close'),
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Center(
            child: Column(
              children: [
                FsIconTile(icon: Icons.workspace_premium_outlined, size: 56),
                const SizedBox(height: 16),
                Text('FitSync Pro', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                SizedBox(
                  width: 250,
                  child: Text(
                    'Train with deeper insight into where your work is going.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: t.text2,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_paidLine != null) ...[
            _Note(key: const Key('pro.paid'), text: _paidLine!, strong: true),
            const SizedBox(height: 14),
          ],
          ...status.when<List<Widget>>(
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (error, stack) => [
              _Note(text: "Couldn't load your Pro status."),
              const SizedBox(height: 12),
              FsButton(
                key: const Key('pro.retryStatus'),
                label: 'Try again',
                kind: FsButtonKind.secondary,
                onPressed: () => ref.invalidate(proStatusProvider),
              ),
            ],
            data: _body,
          ),
        ],
      ),
    );
  }

  List<Widget> _body(ProStatus s) {
    final canBuy = s.source != ProSource.granted;
    return [
      if (s.pro) ...[_StatusCard(status: s), const SizedBox(height: 14)],
      if (s.endsSoon && s.until != null) ...[
        _Note(
          key: const Key('pro.endsSoon'),
          text:
              'Pro ends on ${formatProDay(s.until!)}. Renew to keep Snap a meal and your analytics.',
        ),
        const SizedBox(height: 14),
      ],
      if (canBuy) ...[
        if (s.pro) ...[
          const FsEyebrow('Extend your Pro'),
          const SizedBox(height: 10),
        ],
        _plans(s.prices),
        const SizedBox(height: 14),
        _payArea(s.prices),
        const SizedBox(height: 20),
      ],
      const FsEyebrow('Unlocks today'),
      const SizedBox(height: 10),
      FsCard(
        key: const Key('pro.today'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final feature in _unlocks) _FeatureRow(label: feature),
          ],
        ),
      ),
    ];
  }

  Widget _plans(ProPrices p) {
    final locked = _pay != _Pay.idle;
    void pick(ProPlan plan) => setState(() => _plan = plan);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PlanCard(
            key: const Key('pro.plan.monthly'),
            title: 'Monthly',
            price: peso(p.monthly),
            note: 'per month',
            semanticsLabel: 'Monthly, ${peso(p.monthly)} a month',
            selected: _plan == ProPlan.monthly,
            onTap: locked ? null : () => pick(ProPlan.monthly),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: _PlanCard(
            key: const Key('pro.plan.annual'),
            title: 'Annual',
            price: peso(p.annualPerMonth),
            note: 'per month, billed ${peso(p.annual)} yearly',
            tag: '-${p.annualSavingPct}%',
            semanticsLabel:
                'Annual, ${peso(p.annualPerMonth)} a month, billed ${peso(p.annual)} yearly',
            selected: _plan == ProPlan.annual,
            onTap: locked ? null : () => pick(ProPlan.annual),
          ),
        ),
      ],
    );
  }

  Widget _payArea(ProPrices p) {
    final check = FsButton(
      key: const Key('pro.check'),
      label: 'Check payment',
      kind: FsButtonKind.secondary,
      busy: _checking,
      onPressed: _checking ? null : () => _check(userAsked: true),
    );
    final reopen = FsButton(
      key: const Key('pro.reopen'),
      label: 'Open payment page again',
      kind: _pay == _Pay.notCompleted
          ? FsButtonKind.primary
          : FsButtonKind.ghost,
      onPressed: _openPage,
    );
    final otherPlan = FsButton(
      key: const Key('pro.otherPlan'),
      label: 'Choose another plan',
      kind: FsButtonKind.ghost,
      onPressed: _reset,
    );
    switch (_pay) {
      case _Pay.idle:
      case _Pay.opening:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FsButton(
              key: const Key('pro.pay'),
              label: 'Pay ${peso(p.forPlan(_plan))} with PayMongo',
              busy: _pay == _Pay.opening,
              onPressed: _pay == _Pay.opening ? null : _start,
            ),
            if (_openError != null) ...[
              const SizedBox(height: 10),
              _Note(key: const Key('pro.openError'), text: _openError!),
            ],
          ],
        );
      case _Pay.waiting:
        return _Panel(
          key: const Key('pro.waiting'),
          text: "Finish paying on PayMongo's page. This screen updates by itself.",
          actions: [check, reopen, otherPlan],
        );
      case _Pay.notCompleted:
        return _Panel(
          key: const Key('pro.notCompleted'),
          title: 'Payment not completed',
          text: "PayMongo hasn't confirmed this payment yet.",
          actions: [reopen, check, otherPlan],
        );
      case _Pay.checkFailed:
        return _Panel(
          key: const Key('pro.checkFailed'),
          text: "Couldn't check your payment. Your money is safe — try again.",
          actions: [
            FsButton(
              key: const Key('pro.retry'),
              label: 'Try again',
              busy: _checking,
              onPressed: _checking ? null : () => _check(userAsked: true),
            ),
            otherPlan,
          ],
        );
    }
  }
}

/// "FitSync Pro (granted)", or "FitSync Pro · until 26 Nov 2026 · paid with GCash".
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final ProStatus status;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final until = status.until;
    final method = methodLabel(status.method);
    final text = status.source == ProSource.granted
        ? 'FitSync Pro (granted)'
        : [
            'FitSync Pro',
            if (until != null) 'until ${formatProDate(until)}',
            if (method != null) 'paid with $method',
          ].join(' · ');
    return FsCard(
      key: const Key('pro.status'),
      accent: true,
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 20, color: t.accentText),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: t.text,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A choosable plan. FsCard gives the button and selected state to a screen
/// reader; [semanticsLabel] says the whole price in one sentence.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    super.key,
    required this.title,
    required this.price,
    required this.note,
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
    this.tag,
  });

  final String title;
  final String price;
  final String note;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback? onTap;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return MergeSemantics(
      child: FsCard(
        small: true,
        accent: selected,
        selected: selected,
        onTap: onTap,
        child: Semantics(
          label: semanticsLabel,
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 11, color: t.text3),
                    ),
                  ),
                  if (tag != null) FsTag(tag!),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                price,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
              Text(
                note,
                style: TextStyle(fontSize: 10, color: t.text3, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A waiting / not completed / failed state, read out when it appears.
class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    this.title,
    required this.text,
    required this.actions,
  });

  final String? title;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return FsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: t.text2,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          for (final action in actions) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }
}

/// One line of news: a paid confirmation ([strong]), a reminder, an error.
class _Note extends StatelessWidget {
  const _Note({super.key, required this.text, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            strong ? Icons.check_circle : Icons.info_outline,
            size: 16,
            color: strong ? t.accentText : t.text3,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: strong ? t.text : t.text2,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 17, color: t.accentText),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: t.text, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
