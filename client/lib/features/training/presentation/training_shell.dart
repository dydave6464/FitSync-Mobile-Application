import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../plans/presentation/plan_screen.dart';

/// Plan · Progress · Recovery under one header.
///
/// Progress and Recovery ship as real tabs with empty states rather than being
/// hidden: a tab bar that renders two of three tabs is worse than one that is
/// honest about what is coming. Their content is the next slice, and Recovery
/// additionally waits on a check-in that does not exist yet.
class TrainingShell extends StatefulWidget {
  const TrainingShell({super.key, this.onGoToProfile});

  final VoidCallback? onGoToProfile;

  @override
  State<TrainingShell> createState() => _TrainingShellState();
}

class _TrainingShellState extends State<TrainingShell> {
  int _index = 0;

  static const _tabs = [
    ('plan', 'Plan'),
    ('progress', 'Progress'),
    ('recovery', 'Recovery'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text('Training', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    GestureDetector(
                      key: Key('tab.${_tabs[i].$1}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _index = i),
                      child: Container(
                        margin: const EdgeInsets.only(right: 20),
                        padding: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 2,
                              color: i == _index ? t.accent : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Text(
                          _tabs[i].$2,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: i == _index ? t.text : t.text3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: t.line),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  PlanScreen(onGoToProfile: widget.onGoToProfile),
                  const _ComingSoon(
                    icon: Icons.show_chart,
                    title: 'Progress',
                    body: 'Volume, sessions and personal records appear here '
                        'once you have logged a few workouts.',
                  ),
                  const _ComingSoon(
                    icon: Icons.favorite_outline,
                    title: 'Recovery',
                    body: 'Recovery and injury-risk estimates need a daily '
                        'check-in, which is not built yet.',
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

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FsIconTile(icon: icon, size: 52),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}
