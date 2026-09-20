import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../generator_screen.dart';

/// Opens the generator, from the Plan tab's header and from its empty state.
///
/// Nothing is confirmed on the way in. This opens the screen that asks for a
/// split, a session length and the days to train, and no plan is replaced
/// until that screen's own Generate button is pressed -- a question here
/// would be asking permission to open a form.
///
/// The one case that destroys work the user typed, replacing a plan they
/// built by hand, is refused by the server (`CUSTOM_PLAN_WOULD_BE_LOST`) and
/// raised from that refusal, so it already covers every caller rather than
/// relying on each new door remembering to ask.
Future<void> openGenerator(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const GeneratorScreen()));

/// The Plan tab's way back to the generator.
///
/// Icons.auto_awesome is the icon the start-workout sheet already puts on its
/// AI Workout Generator row. Both open the same screen, so wearing the same
/// icon is what stops them reading as two different features.
///
/// The tooltip carries the words the icon cannot, and is what a screen reader
/// announces -- an IconButton with no tooltip is unlabelled to anyone not
/// looking at it.
class RegeneratePlanButton extends StatefulWidget {
  const RegeneratePlanButton({super.key, this.playIntro = false});

  /// Plays the arrival animation: once on mount, and again whenever this
  /// goes from false to true.
  ///
  /// Decided by the Training shell rather than here. This widget is rebuilt
  /// from scratch every time the Plan sub-tab comes back into view, which is
  /// not the same event as the user opening Train -- and only the shell
  /// survives long enough to tell them apart.
  final bool playIntro;

  @override
  State<RegeneratePlanButton> createState() => _RegeneratePlanButtonState();
}

class _RegeneratePlanButtonState extends State<RegeneratePlanButton>
    with SingleTickerProviderStateMixin {
  /// Long enough to be seen, short enough that a user who already knows where
  /// the button is does not wait on it -- it is decoration over a control
  /// that works from the first frame either way.
  static const _duration = Duration(milliseconds: 900);

  /// Held back until the tab has arrived.
  ///
  /// IndexedStack swaps tabs with no transition, so the header, the tab row
  /// and every card of the Plan tab land in the same frame. An intro playing
  /// in that frame is motion among motion on a 24px icon in the corner, and
  /// goes unnoticed -- which is exactly what happened. Waiting until the
  /// screen is still is what makes the movement the only movement.
  static const _settleDelay = Duration(milliseconds: 350);

  /// Starts at 1, its resting value. The intro rewinds it to 0 and plays
  /// forward, so a button that is never asked to animate simply draws itself.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: 1,
  );

  /// easeOutBack overshoots before settling, which is what makes it read as a
  /// pop rather than a grow.
  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
  );

  /// A quarter turn anticlockwise into place. A sparkle is the one icon in
  /// the set where a spin looks like the thing itself rather than a loading
  /// indicator.
  late final Animation<double> _turns = Tween<double>(
    begin: -0.25,
    end: 0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  bool _mountHandled = false;
  Timer? _introTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than initState: this reads MediaQuery. Guarded so a theme
    // or metrics change cannot restart an intro that is already running.
    if (_mountHandled) return;
    _mountHandled = true;
    if (widget.playIntro) _startIntro();
  }

  @override
  void didUpdateWidget(RegeneratePlanButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell raises the flag for a single frame each time Train is
    // opened. Already mounted, this widget has no other way to hear about it.
    if (widget.playIntro && !oldWidget.playIntro) _startIntro();
  }

  void _startIntro() {
    // Reduce motion is a request, not a preference to weigh. The button stays
    // at its resting size and the user loses nothing but the flourish.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;

    // Restarts cleanly if Train is reopened mid-flight.
    _introTimer?.cancel();
    _introTimer = Timer(_settleDelay, () {
      if (mounted) _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    // Cancelled, not just left to fire: a pending timer outliving the tree is
    // a leak in the app and a hard failure in a widget test.
    _introTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: RotationTransition(
      turns: _turns,
      child: IconButton(
        key: const Key('plan.regenerate'),
        // The prototype's green, read from the theme so it follows light and
        // dark rather than picking a side.
        icon: Icon(Icons.auto_awesome, color: context.fs.accent),
        tooltip: 'Regenerate plan',
        onPressed: () => openGenerator(context),
      ),
    ),
  );
}
