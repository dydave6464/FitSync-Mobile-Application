import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../providers.dart';

/// The default rests on offer: every 30 seconds from 0:30 to 5:00.
const restPresets = [30, 60, 90, 120, 150, 180, 210, 240, 270, 300];

/// What Custom accepts. Matches the server's REST_INVALID bounds.
const restMinSeconds = 10;
const restMaxSeconds = 600;

/// "1:30" for 90.
String formatRest(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// Reads "1:45" or plain "45" as seconds, or null when it is neither. Range
/// is the caller's to check.
int? parseRest(String text) {
  final value = text.trim();
  if (RegExp(r'^\d{1,3}$').hasMatch(value)) return int.parse(value);
  final match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(value);
  if (match == null) return null;
  return int.parse(match[1]!) * 60 + int.parse(match[2]!);
}

/// What a sheet opened from a running rest can do to that rest.
class RestCountdown {
  const RestCountdown({
    required this.remaining,
    required this.onAdjust,
    required this.onSkip,
  });

  /// Seconds left, ticking. Reaching zero closes the sheet.
  final ValueListenable<int> remaining;

  /// Adds (or with a negative value, takes) seconds from this rest only.
  final void Function(int seconds) onAdjust;

  final VoidCallback onSkip;
}

/// The rest controls, as a bottom sheet so the logger itself stays as
/// uncluttered as it was: the app bar keeps one small tag, and everything
/// adjustable lives here.
///
/// Opened from the tag mid-rest with a [countdown] -- the live time, ±30s
/// and Skip -- or from the logger's menu without one, to set the default
/// before the first set.
Future<void> showRestSheet(BuildContext context, {RestCountdown? countdown}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.fs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => RestSheet(countdown: countdown),
    );

class RestSheet extends ConsumerStatefulWidget {
  const RestSheet({super.key, this.countdown});

  final RestCountdown? countdown;

  @override
  ConsumerState<RestSheet> createState() => _RestSheetState();
}

class _RestSheetState extends ConsumerState<RestSheet> {
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.countdown?.remaining.addListener(_onTick);
  }

  @override
  void dispose() {
    // Safe even once the timer has disposed its notifier: removeListener
    // returns immediately after dispose.
    widget.countdown?.remaining.removeListener(_onTick);
    super.dispose();
  }

  /// A rest that runs out -- or is cut to nothing with −30s -- takes its
  /// sheet with it: a countdown sitting at 0:00 has nothing left to control.
  void _onTick() {
    if (widget.countdown!.remaining.value > 0) return;
    _close();
  }

  /// Closes this sheet and only this sheet. Removed by route rather than by
  /// a bare pop, because a rest can end under the Custom dialog, and a pop
  /// there would close the dialog and leave the sheet.
  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _save(int seconds) async {
    setState(() => _error = null);
    try {
      await ref.read(restSecondsProvider.notifier).set(seconds);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = "Couldn't save your rest time. ${describeError(error)}",
      );
    }
  }

  Future<void> _custom(int current) async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _CustomRestDialog(initial: current),
    );
    if (chosen != null && mounted) await _save(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final countdown = widget.countdown;
    final saved = ref.watch(restSecondsProvider).value ?? defaultRestSeconds;
    final isPreset = restPresets.contains(saved);

    return SafeArea(
      key: const Key('rest.sheet'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (countdown != null) ...[
              Center(child: Text('Rest', style: fsEyebrow(t))),
              const SizedBox(height: 6),
              Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: countdown.remaining,
                  builder: (_, seconds, _) => Text(
                    formatRest(seconds),
                    key: const Key('rest.sheet.remaining'),
                    style: TextStyle(
                      fontFamily: fsMonoFamily,
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: t.amber,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FsButton(
                      key: const Key('rest.minus'),
                      label: '−30s',
                      kind: FsButtonKind.secondary,
                      onPressed: () => countdown.onAdjust(-30),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FsButton(
                      key: const Key('rest.plus'),
                      label: '+30s',
                      kind: FsButtonKind.secondary,
                      onPressed: () => countdown.onAdjust(30),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FsButton(
                key: const Key('rest.skip'),
                label: 'Skip rest',
                onPressed: () {
                  countdown.onSkip();
                  _close();
                },
              ),
              const SizedBox(height: 22),
            ],
            const FsEyebrow('Rest between sets'),
            const SizedBox(height: 4),
            Text(
              'Used from your next rest.',
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final seconds in restPresets)
                  FsChip(
                    key: Key('rest.preset.$seconds'),
                    label: formatRest(seconds),
                    selected: seconds == saved,
                    small: true,
                    onTap: () => _save(seconds),
                  ),
                FsChip(
                  key: const Key('rest.custom'),
                  label: isPreset ? 'Custom…' : 'Custom (${formatRest(saved)})',
                  selected: !isPreset,
                  small: true,
                  onTap: () => _custom(saved),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(fontSize: 12, color: t.red)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks for any rest from 0:10 to 10:00, typed as "1:45" or "105".
class _CustomRestDialog extends StatefulWidget {
  const _CustomRestDialog({required this.initial});

  final int initial;

  @override
  State<_CustomRestDialog> createState() => _CustomRestDialogState();
}

class _CustomRestDialogState extends State<_CustomRestDialog> {
  late final _field = TextEditingController(text: formatRest(widget.initial));
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final seconds = parseRest(_field.text);
    if (seconds == null ||
        seconds < restMinSeconds ||
        seconds > restMaxSeconds) {
      setState(() => _error = 'Enter a time from 0:10 to 10:00.');
      return;
    }
    Navigator.of(context).pop(seconds);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Custom rest'),
    content: TextField(
      key: const Key('rest.custom.field'),
      controller: _field,
      autofocus: true,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        hintText: '1:45',
        helperText: 'Minutes:seconds, or seconds',
        errorText: _error,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('rest.custom.save'),
        onPressed: _submit,
        child: const Text('Save'),
      ),
    ],
  );
}
