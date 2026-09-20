import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';

/// What Pro unlocks today, in the order a user meets it.
///
/// One feature, gated in two places. `VolumeByMuscleCard` on the Progress tab
/// draws placeholder bars behind a lock for a free account, and
/// `buildReportSnapshot` leaves the muscle section out of a shared report
/// entirely unless the sharer is premium -- so a coach opening a free user's
/// link never receives it, rather than receiving it hidden.
const _unlockedToday = [
  'Volume by muscle on the Progress tab',
  'The same muscle breakdown in reports you share with a coach',
];

/// What the prototype sells that the app cannot yet do.
///
/// Listed because the business model is four features wide and the panel
/// should see it, and kept strictly apart from the list above because none of
/// this exists: there is no nutrition feature at all, no advertising to
/// remove, and coaching cues are free to everyone today -- the cue "gate" is
/// an injury-safety check, not a paywall.
const _planned = [
  'Ad-free training',
  'Unlimited AI coaching cues',
  'Food photo recognition',
  'Filipino meal planning',
];

/// The prototype's prices, and the ones `subscriptions.price_php` is waiting
/// for -- that table has existed since the original schema with no rows and
/// no readers.
const _monthlyPhp = 249;
const _annualMonthlyPhp = 149;

/// Opens the Pro screen.
///
/// Every lock in the app routes through here. Until this screen existed the
/// locks were deliberately inert -- VolumeByMuscleCard's row and the share
/// sheet's Pro section both stated the benefit and offered nothing to tap,
/// because there was nowhere to send anyone.
Future<void> openProScreen(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ProScreen()));

/// What Pro costs and what it buys. Nothing here sells it.
///
/// The prototype's `ScreenSubscription` ends in a "Start 7-day free trial"
/// button and a "Restore" link. Neither can work: no code reads or writes the
/// `subscriptions` table, and `is_premium` is deliberately outside the
/// profile PATCH allowlist, so the app cannot grant itself Pro. A button that
/// cannot do its job is a worse answer than a sentence saying there isn't one
/// yet, so this screen says it plainly instead.
class ProScreen extends StatelessWidget {
  const ProScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        leading: IconButton(
          key: const Key('pro.close'),
          icon: const Icon(Icons.close),
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
                    'Train with deeper insight into where your work is '
                    'going.',
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
          Row(
            children: [
              const Expanded(
                child: _PriceCard(
                  plan: 'Monthly',
                  php: _monthlyPhp,
                  note: 'per month',
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: _PriceCard(
                  plan: 'Annual',
                  php: _annualMonthlyPhp,
                  note: 'per month, billed yearly',
                  accent: true,
                  // The prototype's saving, recomputed rather than copied so
                  // the two prices above cannot drift away from it.
                  tag:
                      '-${(100 - (_annualMonthlyPhp / _monthlyPhp * 100)).round()}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const FsEyebrow('Unlocks today'),
          const SizedBox(height: 10),
          FsCard(
            key: const Key('pro.today'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final feature in _unlockedToday)
                  _FeatureRow(label: feature, available: true),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const FsEyebrow('Planned'),
          const SizedBox(height: 10),
          FsCard(
            key: const Key('pro.planned'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final feature in _planned)
                  _FeatureRow(label: feature, available: false),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            key: const Key('pro.notYet'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 15, color: t.text3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'There is no way to buy Pro yet. These prices are what it '
                  'will cost when there is.',
                  style: TextStyle(fontSize: 11.5, color: t.text3, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.plan,
    required this.php,
    required this.note,
    this.accent = false,
    this.tag,
  });

  final String plan;
  final int php;
  final String note;
  final bool accent;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      small: true,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan,
                  style: TextStyle(fontSize: 11, color: t.text3),
                ),
              ),
              if (tag != null) FsTag(tag!),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '₱$php',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          Text(note, style: TextStyle(fontSize: 10, color: t.text3)),
        ],
      ),
    );
  }
}

/// A tick for what you get, a dash for what is coming.
///
/// Deliberately different marks rather than the same tick greyed out: a
/// greyed tick still reads as "included", and this list must never be
/// mistaken for the one above it.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label, required this.available});

  final String label;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            available ? Icons.check_circle : Icons.remove_circle_outline,
            size: 17,
            color: available ? t.accent : t.text3,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: available ? t.text : t.text3,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
