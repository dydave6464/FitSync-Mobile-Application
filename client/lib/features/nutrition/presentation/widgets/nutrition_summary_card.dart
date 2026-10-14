import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_charts.dart' show FsRing;
import '../../../../core/widgets/fs_kit.dart' show FsCard;
import '../../../sessions/presentation/progress_screen.dart' show groupThousands;
import '../../domain/nutrition.dart';

/// The prototype's top card: a calorie ring, and Protein / Carbs / Fat bars.
class NutritionSummaryCard extends StatelessWidget {
  const NutritionSummaryCard({super.key, required this.day, this.onGoToProfile});

  final NutritionDay day;
  final VoidCallback? onGoToProfile;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final target = day.target;
    final eaten = day.totals;
    final missing = describeMissing(day.targetMissing);

    final ring = FsRing(
      size: 76,
      stroke: 9,
      color: t.accent,
      value: target == null || target.kcal == 0 ? 0 : eaten.kcal / target.kcal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(child: Text(groupThousands(eaten.kcal.toDouble()),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          FittedBox(child: Text(target == null ? 'kcal' : '/ ${groupThousands(target.kcal.toDouble())} kcal',
              style: TextStyle(fontSize: 9, color: t.text3))),
        ],
      ),
    );

    final bars = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MacroBar(label: 'Protein', eaten: eaten.proteinG, target: target?.proteinG, color: t.accent),
        _MacroBar(label: 'Carbs', eaten: eaten.carbsG, target: target?.carbsG, color: t.blue),
        _MacroBar(label: 'Fat', eaten: eaten.fatG, target: target?.fatG, color: t.violet),
      ],
    );

    return FsCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A row, as in the prototype: the ring, then the bars filling the
          // rest. Not a Wrap: the bars' column stretches to whatever width it
          // is offered, so a Wrap always pushed them onto a line of their own.
          Row(
            children: [ring, const SizedBox(width: 16), Expanded(child: bars)],
          ),
          if (missing != null) ...[
            const SizedBox(height: 12),
            Text(missing, style: TextStyle(color: t.text2, fontSize: 13)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onGoToProfile, child: const Text('Update profile')),
            ),
          ],
        ],
      ),
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({required this.label, required this.eaten, required this.target, required this.color});

  final String label;
  final double eaten;
  final int? target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final shown = eaten.round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(target == null ? '$shown g' : '$shown / $target g', style: TextStyle(fontSize: 11, color: t.text3)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: target == null || target == 0 ? 0 : (eaten / target!).clamp(0, 1),
              backgroundColor: t.surface2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
