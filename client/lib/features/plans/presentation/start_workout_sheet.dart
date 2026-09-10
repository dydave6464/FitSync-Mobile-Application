import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';

/// The "+" chooser: how a workout starts.
///
/// Two rows, as the design draws them. "Log manually" is present and inert
/// because the exercise library it needs is slice 3 -- a greyed row with a
/// tag says the capability is planned, where omitting it would say nothing
/// at all and a chooser with one choice would be a worse screen.
Future<void> showStartWorkoutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _StartWorkoutSheet(),
  );
}

class _StartWorkoutSheet extends StatelessWidget {
  const _StartWorkoutSheet();

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: t.line2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Start a workout',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: t.text)),
                IconButton(
                  key: const Key('start.close'),
                  icon: const Icon(Icons.close, size: 18),
                  color: t.text3,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Row(
              rowKey: const Key('start.generator'),
              icon: Icons.auto_awesome,
              title: 'AI Workout Generator',
              body: 'Auto-build a plan from your profile, goals & recovery.',
              tag: 'Recommended',
              accent: true,
              onTap: () {},
            ),
            const SizedBox(height: 10),
            _Row(
              rowKey: const Key('start.manual'),
              icon: Icons.fitness_center,
              title: 'Log manually',
              body: 'Pick exercises from the library and track your own sets.',
              tag: 'Coming soon',
              accent: false,
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.body,
    required this.tag,
    required this.accent,
    required this.onTap,
  });

  final Key rowKey;
  final IconData icon;
  final String title;
  final String body;
  final String tag;
  final bool accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final dimmed = onTap == null;

    return Material(
      color: accent ? t.accentDim : t.surface,
      borderRadius: BorderRadius.circular(FsRadius.card),
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(FsRadius.card),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FsRadius.card),
            border: Border.all(color: accent ? t.accentLine : t.line),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: dimmed ? t.text3 : t.accent),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: dimmed ? t.text3 : t.text,
                        )),
                    const SizedBox(height: 3),
                    Text(body,
                        style: TextStyle(fontSize: 12, color: t.text3, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FsTag(tag),
            ],
          ),
        ),
      ),
    );
  }
}
