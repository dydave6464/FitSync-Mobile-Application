import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../health/domain/health_answers.dart';

/// The health check: a condition checklist, three warning-sign questions,
/// and, when anything is positive, the safety notices with the boxes that
/// let the answers be stored.
///
/// A pure content widget, like GoalStep: it takes the current value, reports
/// changes, and does not know whether it is inside onboarding or Settings.
/// Settings passes [allowOptOut] false: there, not saving is just leaving the
/// screen, and deleting has its own button.
class HealthStep extends StatelessWidget {
  const HealthStep({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowOptOut = true,
  });

  final HealthAnswers value;
  final ValueChanged<HealthAnswers> onChanged;
  final bool allowOptOut;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final ticked = [
      for (final c in healthConditions)
        if (value.conditions.contains(c.value)) c,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Your health', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'This helps us keep your plan safe.',
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
        const SizedBox(height: 20),
        Text('Do any of these apply to you?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in healthConditions)
              FsChip(
                key: Key('health.${c.value}'),
                label: c.label,
                selected: value.conditions.contains(c.value),
                showCheck: true,
                onTap: () => onChanged(value.toggle(c.value)),
              ),
            FsChip(
              key: const Key('health.none'),
              label: 'None of these',
              selected: value.noneOfThese,
              showCheck: true,
              onTap: () => onChanged(value.toggleNone()),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'In the last 12 months, have you had:',
          style: theme.textTheme.titleMedium,
        ),
        for (final q in healthQuestions) ...[
          const SizedBox(height: 12),
          Text(q.label, style: TextStyle(fontSize: 13.5, color: t.text)),
          const SizedBox(height: 8),
          Row(
            children: [
              FsChip(
                key: Key('health.${q.field}.yes'),
                label: 'Yes',
                selected: value.valueOf(q.field) == true,
                small: true,
                onTap: () => onChanged(value.answer(q.field, true)),
              ),
              const SizedBox(width: 8),
              FsChip(
                key: Key('health.${q.field}.no'),
                label: 'No',
                selected: value.valueOf(q.field) == false,
                small: true,
                onTap: () => onChanged(value.answer(q.field, false)),
              ),
            ],
          ),
        ],
        if (value.hasWarning) ...[
          const SizedBox(height: 20),
          const _WarningCard(),
        ],
        if (ticked.isNotEmpty) ...[
          const SizedBox(height: 20),
          _ConditionCard(ticked: ticked),
        ],
        if (value.isPositive || value.optedOut) ...[
          const SizedBox(height: 12),
          if (!value.optedOut) ...[
            CheckboxListTile(
              key: const Key('health.ack'),
              value: value.acknowledged,
              onChanged: (v) => onChanged(value.withAcknowledged(v ?? false)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text("I understand, and I'll check with my doctor."),
            ),
            CheckboxListTile(
              key: const Key('health.consent'),
              value: value.consent,
              onChanged: (v) => onChanged(value.withConsent(v ?? false)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'I agree FitSync stores these answers to keep my plan safe. '
                'Only I can see them, and I can delete them in Settings.',
              ),
            ),
          ] else
            Text(
              "We won't save these answers, and your plan stays as it is. "
              'You can answer again in Settings.',
              style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
            ),
          if (allowOptOut)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('health.optOut'),
                onPressed: () => onChanged(value.withOptedOut(!value.optedOut)),
                child: Text(
                  value.optedOut ? 'Save my answers instead' : "Don't save my answers",
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Shown on any Yes, above the condition card.
class _WarningCard extends StatelessWidget {
  const _WarningCard();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return DecoratedBox(
      key: const Key('health.notice.warning'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FsRadius.md),
        border: Border.all(color: t.red),
        color: t.red.withValues(alpha: 0.08),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please get medical clearance before you start training',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Stop and get help if you have chest pain, fainting or severe '
              'breathlessness.',
              style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when any condition is ticked: one line and one tip per condition.
class _ConditionCard extends StatelessWidget {
  const _ConditionCard({required this.ticked});

  final List<HealthCondition> ticked;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final body = TextStyle(fontSize: 12.5, color: t.text2, height: 1.5);

    return FsCard(
      key: const Key('health.notice.condition'),
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Check with your doctor first', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'You told us about: ${ticked.map((c) => c.label).join(', ')}.',
            style: body,
          ),
          for (final c in ticked) ...[
            const SizedBox(height: 10),
            Text(c.line, style: body),
            const SizedBox(height: 4),
            Text(c.tip, style: body.copyWith(color: t.text)),
          ],
          const SizedBox(height: 10),
          Text(
            "We'll keep your plan gentle: 2 sets per exercise, shorter sessions.",
            style: body,
          ),
          const SizedBox(height: 10),
          Text(
            'This is general safety guidance, not medical advice.',
            style: TextStyle(fontSize: 11, color: t.text3),
          ),
        ],
      ),
    );
  }
}
