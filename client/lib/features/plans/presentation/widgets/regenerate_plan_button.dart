import 'package:flutter/material.dart';

import '../../../../core/widgets/fs_kit.dart';
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
Future<void> openGenerator(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GeneratorScreen()),
    );

/// The Plan tab's way back to the generator.
///
/// Spelled out rather than drawn as an icon: the generator was only reachable
/// from a row inside the start-workout sheet, which is the right screen filed
/// under the wrong intent -- someone whose equipment just changed is not
/// trying to start a workout. A word needs no tooltip and no first-run hint
/// to explain it.
class RegeneratePlanButton extends StatelessWidget {
  const RegeneratePlanButton({super.key});

  @override
  Widget build(BuildContext context) => FsButton(
        key: const Key('plan.regenerate'),
        label: 'Regenerate',
        kind: FsButtonKind.ghost,
        small: true,
        onPressed: () => openGenerator(context),
      );
}
