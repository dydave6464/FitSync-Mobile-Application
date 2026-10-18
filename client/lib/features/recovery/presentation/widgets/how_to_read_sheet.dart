import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/recovery.dart';

/// "How to read this": what the injury-risk estimate is, what each level
/// means, what moves it, and what it is not.
///
/// Written for the capstone teacher's request for an interpretation of the
/// estimate. How the score is computed (the rules, and the model trained on
/// simulated data) is left out: a user acts on the level, not the mechanism.
Future<void> showHowToReadSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // The surface goes on the sheet's own Material, as the check-in sheet
    // does, rather than a transparent sheet around a coloured Container.
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    isScrollControlled: true,
    builder: (_) => const _HowToReadSheet(),
  );
}

/// The three levels, lowest risk first, each with the Readiness range it
/// shows as. The ranges follow [InjuryRiskEstimate.readiness]: risk is
/// moderate from 40 and high from 70, and readiness is 100 minus the score
/// rounded up.
const _levels = <({String level, String readiness})>[
  (level: 'low', readiness: 'Readiness 61–100'),
  (level: 'moderate', readiness: 'Readiness 31–60'),
  (level: 'high', readiness: 'Readiness 0–30'),
];

class _HowToReadSheet extends StatelessWidget {
  const _HowToReadSheet();

  /// The tallest the sheet grows: a strip of the Recovery tab stays in view
  /// above it, so it reads as a sheet over the tab rather than a new screen.
  static const _maxHeightFraction = 0.9;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return ConstrainedBox(
      key: const Key('howto.sheet'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _maxHeightFraction,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  color: t.line2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            // Everything below the handle scrolls: at large text on a small
            // phone the guide is several screens long.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'How to read this',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Paragraph(
                      'The injury-risk estimate is a rough guide to how likely '
                      "today's training is to lead to an injury. Readiness is "
                      'the same estimate the other way up: higher is better.',
                      t: t,
                    ),
                    _Heading('What each level means', t: t),
                    for (final l in _levels) _LevelRow(l.level, l.readiness),
                    _Heading('What moves it', t: t),
                    _Bullet(
                      'Your check-ins over the last 3 days: sleep, soreness, '
                      'energy and stress.',
                      t: t,
                    ),
                    _Bullet(
                      "This week's training compared with your usual week.",
                      t: t,
                    ),
                    _Bullet(
                      'Past injuries on your profile, and pain you reported '
                      'after a recent workout.',
                      t: t,
                    ),
                    const SizedBox(height: 4),
                    _Paragraph(
                      "A rough morning or a big week alone can't make it High.",
                      t: t,
                    ),
                    _Paragraph(
                      'In your first week there is no usual week to compare '
                      'with, so training load adds nothing. After that, your '
                      'usual week is the average of the weeks you have '
                      'trained before this one, up to three.',
                      t: t,
                    ),
                    _Heading('What it is not', t: t),
                    Text(
                      key: const Key('howto.disclaimer'),
                      'This is not a medical diagnosis. If something hurts, '
                      'stop and see a doctor or physiotherapist. The estimate '
                      'is only as accurate as your check-ins.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // A button as well as the drag and the scrim, so closing
                    // never depends on a swipe.
                    FsButton(
                      key: const Key('howto.close'),
                      label: 'Got it',
                      kind: FsButtonKind.secondary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.t});

  final String text;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text, {required this.t});

  final String text;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 13.5, height: 1.45, color: t.text2),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {required this.t});

  final String text;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text(
              '•  ',
              style: TextStyle(fontSize: 13.5, height: 1.45, color: t.text2),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, height: 1.45, color: t.text2),
            ),
          ),
        ],
      ),
    );
  }
}

/// One level of the table: its name, the Readiness range it shows as, and
/// the advice the card gives for it. Stacked rather than in columns, so at
/// large text on a narrow phone nothing has to squeeze beside anything else.
class _LevelRow extends StatelessWidget {
  const _LevelRow(this.level, this.readiness);

  final String level;
  final String readiness;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    // Built from the same model the card uses, so the table and the line
    // under the ring can never word a level differently.
    final estimate = InjuryRiskEstimate(
      riskLevel: level,
      trainingLoadScore: null,
      checkinDate: '',
    );
    final color = switch (level) {
      'high' => t.red,
      'moderate' => t.amber,
      _ => t.accent,
    };

    return Container(
      key: Key('howto.level.$level'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.line),
      ),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colour only repeats the name beside it, so it is decoration.
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 10),
              child: ExcludeSemantics(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    estimate.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  Text(
                    readiness,
                    style: TextStyle(fontSize: 12.5, color: t.text2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    estimate.levelAdvice,
                    style: TextStyle(fontSize: 13.5, color: t.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
