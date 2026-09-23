import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../plans/presentation/plan_screen.dart';
import '../../plans/presentation/widgets/regenerate_plan_button.dart';
import '../../recovery/presentation/recovery_screen.dart';
import '../../sessions/presentation/progress_screen.dart';

/// A request, from outside, to show one of Train's tabs.
///
/// [serial] is what makes a repeat of the same tab a new request: the shell
/// acts when it changes, not when [tab] does, so asking for Progress twice in
/// a row still lands on Progress the second time after the user moved away.
class TrainTabRequest {
  const TrainTabRequest(this.tab, this.serial);

  /// One of `_tabs`' names: 'plan', 'progress' or 'recovery'.
  final String tab;
  final int serial;
}

/// Plan · Progress · Recovery under one header.
///
/// All three are live: Progress reads finished sessions and what they added
/// up to, and Recovery reads the daily check-in and the injury-risk estimate
/// it produces.
class TrainingShell extends StatefulWidget {
  const TrainingShell({
    super.key,
    this.onGoToProfile,
    this.openCount = 0,
    this.tabRequest,
  });

  /// Bumped by NavShell every time the Train tab is selected.
  ///
  /// Defaulted so a test (or any other caller) can mount this shell directly
  /// without inventing a number; it then simply plays the intro once, on
  /// mount, the way a first visit does.
  final int openCount;

  /// Set by NavShell when another screen asks for a particular tab -- Home's
  /// readiness and progress cards. Null opens wherever the user left it.
  final TrainTabRequest? tabRequest;

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
    _applyTabRequest(widget.tabRequest);
  }

  @override
  void didUpdateWidget(TrainingShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openCount != oldWidget.openCount) _armIntro();
    if (widget.tabRequest?.serial != oldWidget.tabRequest?.serial) {
      _applyTabRequest(widget.tabRequest);
    }
  }

  /// No setState: both callers run before the next build anyway. An unknown
  /// name is ignored rather than guessed at.
  void _applyTabRequest(TrainTabRequest? request) {
    if (request == null) return;
    final i = _tabs.indexWhere((tab) => tab.$1 == request.tab);
    if (i >= 0) _index = i;
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
                  const RecoveryScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
