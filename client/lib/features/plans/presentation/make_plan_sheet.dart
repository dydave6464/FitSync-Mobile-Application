import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/split_style.dart';
import '../domain/workout_plan.dart';

/// Asks how a finished workout should become the user's plan, and whether
/// they mean it.
///
/// The one place the split is asked for a hand-picked workout. It used to be
/// asked on a setup screen before a single exercise was picked, which made
/// logging a workout feel like planning one -- and most workouts are only
/// logged, so most of those answers went nowhere. Here it is asked only of
/// the workout someone has chosen to keep, at the moment the answer is used:
/// `POST /plans/from-session` names the plan and its days from it.
///
/// [replacing] is the plan that goes when this one is made, or null when
/// there is none. Replacing it cannot be undone -- plan history is out of
/// scope -- so the sheet names it and the confirming button is red.
///
/// Resolves to the chosen split's slug, or null for Cancel and for any
/// dismissal (a swipe, a tap outside, back): only the button writes.
Future<String?> showMakePlanSheet(
  BuildContext context, {
  WorkoutPlan? replacing,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  // At large text on a small phone the chips, the warning and both buttons
  // are taller than the default 9/16 cap; the scroll view below takes the
  // rest.
  isScrollControlled: true,
  builder: (_) => _MakePlanSheet(replacing: replacing),
);

class _MakePlanSheet extends StatefulWidget {
  const _MakePlanSheet({this.replacing});

  final WorkoutPlan? replacing;

  @override
  State<_MakePlanSheet> createState() => _MakePlanSheetState();
}

class _MakePlanSheetState extends State<_MakePlanSheet> {
  /// Full body until changed: it is the split a single hand-picked workout
  /// most often is, and the one the setup screen used to start on.
  String _split = splitStyles.first.value;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final replacing = widget.replacing;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Make this your plan',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            if (replacing != null) ...[
              const SizedBox(height: 6),
              Text(
                'This replaces "${replacing.name}". You can\'t get it back.',
                key: const Key('makePlan.replaces'),
                style: TextStyle(fontSize: 13, color: t.text2, height: 1.35),
              ),
            ],
            const SizedBox(height: 18),
            const FsEyebrow('Split style'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in splitStyles)
                  FsChip(
                    key: Key('makePlan.split.${style.value}'),
                    label: style.label,
                    selected: style.value == _split,
                    onTap: () => setState(() => _split = style.value),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Names your plan and its days.',
              style: TextStyle(fontSize: 12, color: t.text2, height: 1.35),
            ),
            const SizedBox(height: 22),
            // The answer first, then the way out, as the review screen's
            // question orders them. Both wrap rather than ending in an
            // ellipsis: at the largest text sizes a cut-off "Replace my…"
            // hides what the tap does.
            if (replacing != null)
              FsButton(
                key: const Key('makePlan.confirm'),
                label: 'Replace my plan',
                kind: FsButtonKind.ghost,
                danger: true,
                wrapLabel: true,
                onPressed: () => Navigator.of(context).pop(_split),
              )
            else
              FsButton(
                key: const Key('makePlan.confirm'),
                label: 'Make it my plan',
                wrapLabel: true,
                onPressed: () => Navigator.of(context).pop(_split),
              ),
            const SizedBox(height: 8),
            FsButton(
              key: const Key('makePlan.cancel'),
              label: 'Cancel',
              kind: FsButtonKind.secondary,
              wrapLabel: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
