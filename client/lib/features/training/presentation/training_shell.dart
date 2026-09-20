import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../plans/presentation/plan_screen.dart';
import '../../plans/presentation/widgets/regenerate_plan_button.dart';
import '../../sessions/presentation/progress_screen.dart';

/// Plan · Progress · Recovery under one header.
///
/// Progress is live: it reads finished sessions and what they added up to.
///
/// Recovery still ships as a real tab with an empty state rather than being
/// hidden -- a tab bar that renders two of three tabs is worse than one that
/// is honest about what is coming -- and it waits on a daily check-in that
/// does not exist yet.
class TrainingShell extends StatefulWidget {
  const TrainingShell({super.key, this.onGoToProfile, this.openCount = 0});

  /// Bumped by NavShell every time the Train tab is selected.
  ///
  /// Defaulted so a test (or any other caller) can mount this shell directly
  /// without inventing a number; it then simply plays the intro once, on
  /// mount, the way a first visit does.
  final int openCount;

  final VoidCallback? onGoToProfile;

  @override
  State<TrainingShell> createState() => _TrainingShellState();
}

class _TrainingShellState extends State<TrainingShell> {
  int _index = 0;

  /// True for one frame each time the Train tab is opened.
  ///
  /// The decision lives here rather than in the button because the two are
  /// rebuilt on different rhythms: the button is torn down and remade every
  /// time the Plan sub-tab comes back, while this shell survives for as long
  /// as the app does. Only this side can tell "the user opened Train" from
  /// "the user flicked back from Progress", and the first replays while the
  /// second does not.
  bool _introPending = true;

  /// The [TrainingShell.openCount] the intro has already been armed for, so
  /// one open arms it once however many times this rebuilds.
  int? _armedFor;

  @override
  void initState() {
    super.initState();
    _armIntro();
  }

  @override
  void didUpdateWidget(TrainingShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openCount != oldWidget.openCount) _armIntro();
  }

  void _armIntro() {
    if (_armedFor == widget.openCount) return;
    _armedFor = widget.openCount;
    _introPending = true;
    // Cleared after the frame rather than when the animation ends: the button
    // has already started by then, and a rebuild with a false flag does not
    // stop a controller that is already running. It also leaves the flag
    // ready to go true again on the next open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _introPending = false);
    });
  }

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
              child: Row(
                children: [
                  Text('Training', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  // Per tab rather than shared. This header sits above all
                  // three tabs, so an action parked here unconditionally
                  // would offer to regenerate a plan while the user is
                  // looking at Progress or Recovery. Keyed on the tab's name,
                  // not its index, so reordering _tabs cannot move it.
                  if (_tabs[_index].$1 == 'plan')
                    RegeneratePlanButton(playIntro: _introPending),
                ],
              ),
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
                              color: i == _index
                                  ? t.accent
                                  : Colors.transparent,
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
                  const ProgressScreen(),
                  const _ComingSoon(
                    icon: Icons.favorite_outline,
                    title: 'Recovery',
                    body:
                        'Recovery and injury-risk estimates need a daily '
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
  const _ComingSoon({
    required this.icon,
    required this.title,
    required this.body,
  });

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
