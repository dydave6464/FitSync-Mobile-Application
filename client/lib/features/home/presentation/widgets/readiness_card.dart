import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_charts.dart' show FsRing;
import '../../../../core/widgets/fs_kit.dart' hide FsRing;
import '../../../recovery/domain/recovery.dart';
import '../../../sessions/presentation/widgets/share_report_sheet.dart'
    show formatShareExpiry;

/// Home's readiness hero: the latest injury-risk estimate, in the Recovery
/// tab's own ring.
///
/// The prototype draws a 0-100 "READY" score here. The app has no such score
/// -- it has a low/moderate/high estimate -- so this shows that, with the same
/// ring value, colour and label Recovery uses, and says what it is: an injury
/// risk. The ring fills as risk rises, so calling it readiness would read
/// backwards.
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
                const FsEyebrow('Injury-risk estimate'),
                const SizedBox(height: 8),
                // Recovery's own empty-state sentence, verbatim.
                Text(
                  'Check in this morning to get your first estimate.',
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
                FsRing(
                  value: estimate.ringValue,
                  color: switch (estimate.riskLevel) {
                    'high' => t.red,
                    'moderate' => t.amber,
                    _ => t.accent,
                  },
                  size: 78,
                  stroke: 9,
                  child: Text(
                    estimate.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FsEyebrow('Injury-risk estimate'),
                      const SizedBox(height: 6),
                      Text(
                        // With no check-in today, the estimate may be from an
                        // earlier day, so none of the per-level "today"
                        // advice can be claimed.
                        todayCheckin == null
                            ? "Check in for today's estimate"
                            : switch (estimate.riskLevel) {
                                'high' => 'Consider a lighter day',
                                'moderate' => 'Worth easing in today',
                                _ => 'Load and check-ins look manageable',
                              },
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      // Recovery's rule: today's check-in already dates it.
                      if (todayCheckin == null) ...[
                        const SizedBox(height: 4),
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
