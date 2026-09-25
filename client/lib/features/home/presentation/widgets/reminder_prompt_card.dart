import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/fs_kit.dart';
import '../../../reminders/data/reminder_prompt_store.dart';
import '../../../reminders/data/reminder_scheduler.dart';

/// Home's one-time nudge to turn reminders on.
///
/// Resolves permission and the answered flag once, on mount, rather than
/// watching either: this is a prompt shown at most once, not a status that
/// needs to track live OS state the way the Reminders screen's blocked
/// banner does. Renders nothing at all -- not an empty box -- until both
/// checks land, and nothing from then on if either says the prompt should
/// stay hidden, so it never nudges a spacing gap into Home's list by itself.
class ReminderPromptCard extends ConsumerStatefulWidget {
  const ReminderPromptCard({super.key});

  @override
  ConsumerState<ReminderPromptCard> createState() => _ReminderPromptCardState();
}

class _ReminderPromptCardState extends ConsumerState<ReminderPromptCard> {
  /// Null until both checks have landed. `false` covers both "permission
  /// already granted" and "already answered" -- the card treats them the
  /// same, so nothing downstream needs to tell them apart.
  bool? _show;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final granted = await ref
        .read(reminderSchedulerProvider)
        .permissionGranted();
    // Checked before the second read, not only at the end: this await can
    // outlive Home swapping this card out (a fast tab switch), and ref.read
    // throws on a disposed widget rather than returning stale data.
    if (!mounted) return;
    final bool answered;
    try {
      answered = await ref.read(reminderPromptStoreProvider).answered();
    } catch (error) {
      // Secure storage is a platform channel -- it can fail (a locked
      // keychain, a missing implementation). Unable to tell whether the
      // prompt was already answered, the safer default is to stay quiet
      // rather than risk nagging someone who already dismissed it.
      debugPrint('Reminder prompt: answered() failed: $error');
      if (mounted) setState(() => _show = false);
      return;
    }
    if (!mounted) return;
    setState(() => _show = !granted && !answered);
  }

  /// Marks the prompt answered and hides the card for good. Shared by both
  /// buttons -- Not now calls it directly, Turn on calls it after the system
  /// prompt closes -- since either tap is the user having decided, whatever
  /// they decided.
  ///
  /// A write failure still hides the card for this session -- there is
  /// nothing more useful to show -- but only `debugPrint`s rather than
  /// throwing, since the flag not landing just means the prompt asks again
  /// next time.
  Future<void> _hide() async {
    try {
      await ref.read(reminderPromptStoreProvider).markAnswered();
    } catch (error) {
      debugPrint('Reminder prompt: markAnswered() failed: $error');
    }
    if (!mounted) return;
    setState(() => _show = false);
  }

  Future<void> _turnOn() async {
    await ref.read(reminderSchedulerProvider).requestPermission();
    // The system prompt this just awaited can outlive the card -- Home
    // rebuilding out from under it, or the app backgrounding -- so nothing
    // below may touch ref once it is gone.
    if (!mounted) return;
    await _hide();
  }

  @override
  Widget build(BuildContext context) {
    if (_show != true) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FsCard(
          key: const Key('home.reminderPrompt'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Get reminders for your habits',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FsButton(
                    key: const Key('home.reminderPrompt.turnOn'),
                    label: 'Turn on',
                    small: true,
                    onPressed: _turnOn,
                  ),
                  FsButton(
                    key: const Key('home.reminderPrompt.notNow'),
                    label: 'Not now',
                    small: true,
                    kind: FsButtonKind.secondary,
                    onPressed: _hide,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
