import 'package:flutter/material.dart';

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
class RegeneratePlanButton extends StatelessWidget {
  const RegeneratePlanButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('plan.regenerate'),
    icon: const Icon(Icons.auto_awesome),
    tooltip: 'Regenerate plan',
    onPressed: () => openGenerator(context),
  );
}
