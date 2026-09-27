import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_charts.dart' show FsRing;
import '../../../../core/widgets/fs_kit.dart' hide FsRing;
import '../../../recovery/domain/recovery.dart';
import '../../../sessions/presentation/widgets/share_report_sheet.dart'
    show formatShareExpiry;

/// Home's readiness hero, as the prototype draws it: a 0-100 READY score in
/// a ring, a recovery tag and a line of guidance.
///
/// Readiness is the injury-risk score the other way up (see
/// [InjuryRiskEstimate.readiness]) -- one score, two readings -- so this card
/// also names the injury-risk level it comes from, and the Recovery tab keeps
/// the injury-risk estimate as its headline, as the manuscript's "View
/// Injury-Risk Estimate" has it. The ring fills as readiness rises.
class ReadinessCard extends StatelessWidget {
  const ReadinessCard({
    super.key,
    required this.estimate,
    required this.todayCheckin,
    required this.onCheckIn,
    required this.onTap,
  });

  final InjuryRiskEstimate? estimate;
  final MorningCheckin? todayCheckin;
  final VoidCallback onCheckIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final estimate = this.estimate;
    final today = todayCheckin;
    // Whether the estimate came from today's check-in. Otherwise it is an
    // earlier day's -- no check-in yet today, or today's was saved while the
    // ML service was down -- and none of the per-level "today" advice holds.
    final isToday =
        estimate != null &&
        today != null &&
        estimate.checkinDate == today.checkinDate;

    final chip = FsChip(
      key: const Key('home.readiness.checkin'),
      // Recovery's own spellings: an existing check-in is updated, not
      // repeated, and nobody who already checked in today should be asked
      // to check in again.
      label: todayCheckin != null ? 'Update' : 'Check in',
      selected: false,
      small: true,
      onTap: onCheckIn,
    );

    return FsCard(
      key: const Key('home.readiness'),
      accent: true,
      onTap: onTap,
      child: estimate == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FsEyebrow('Readiness'),
                const SizedBox(height: 8),
                Text(
                  'Check in this morning to get your first score.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 12),
                chip,
              ],
            )
          : Row(
              children: [
                _ReadinessRing(estimate: estimate, isToday: isToday),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FsTag(estimate.recoveryLabel),
                      const SizedBox(height: 8),
                      Text(
                        !isToday
                            ? (today == null
                                  ? "Check in for today's estimate"
                                  : "Today's estimate is unavailable")
                            : estimate.readinessHeadline,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isToday
                            ? 'Injury risk: ${estimate.label.toLowerCase()} · '
                                  "from your training load & today's check-in"
                            : 'Injury risk: ${estimate.label.toLowerCase()}',
                        style: TextStyle(fontSize: 11.5, color: t.text2),
                      ),
                      // Recovery's rule: an estimate from today's check-in
                      // is already dated by "today"; any other says its day.
                      if (!isToday) ...[
                        const SizedBox(height: 2),
                        Text(
                          'From ${formatShareExpiry(DateTime.parse(estimate.checkinDate))}',
                          style: TextStyle(fontSize: 11.5, color: t.text3),
                        ),
                      ],
                      const SizedBox(height: 10),
                      chip,
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// The READY ring: readiness out of 100, coloured by the risk level it comes
/// from -- or greyed out when the estimate is an earlier day's, so its number
/// is not read as today's. An estimate saved without a score has no number to
/// show, so the ring takes its level's share and the centre shows a dash
/// rather than invent one.
class _ReadinessRing extends StatelessWidget {
  const _ReadinessRing({required this.estimate, required this.isToday});

  final InjuryRiskEstimate estimate;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final readiness = estimate.readiness;
    return FsRing(
      value: readiness == null ? 1 - estimate.ringValue : readiness / 100,
      color: !isToday
          ? t.text3
          : switch (estimate.riskLevel) {
              'high' => t.red,
              'moderate' => t.amber,
              _ => t.accent,
            },
      size: 78,
      stroke: 9,
      // The ring is a fixed 78dp while system text can double, so the
      // centre shrinks to fit inside the stroke rather than spill past it.
      child: Padding(
        padding: const EdgeInsets.all(12),
        // One phrase for a screen reader, not "82" then "READY".
        child: Semantics(
          label: readiness == null
              ? 'Readiness not scored'
              : 'Readiness $readiness out of 100',
          excludeSemantics: true,
          child: FittedBox(fit: BoxFit.scaleDown, child: _centre(readiness, t)),
        ),
      ),
    );
  }

  Widget _centre(int? readiness, FsTokens t) => readiness == null
      ? Text('–', style: TextStyle(fontSize: 20, color: t.text3))
      : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$readiness',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.text,
              ),
            ),
            Text(
              'READY',
              style: TextStyle(
                fontSize: 8.5,
                letterSpacing: 0.7,
                color: t.text3,
              ),
            ),
          ],
        );
}
