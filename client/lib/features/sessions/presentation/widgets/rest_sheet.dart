import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_charts.dart' show FsRing;
import '../../../../core/widgets/fs_kit.dart' hide FsRing;
import '../../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../data/rest_alerts.dart';
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

/// A running rest as the tag and the sheet draw it: the whole seconds left,
/// and the share of the rest still to go (the ring's sweep).
typedef RestReading = ({int secondsLeft, double fractionLeft});

/// "1 minute 30 seconds" for 90 -- what a screen reader says, where "1:30"
/// would be read as a clock time.
String spokenRest(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
  if (minutes == 0) return unit(rest, 'second');
  if (rest == 0) return unit(minutes, 'minute');
  return '${unit(minutes, 'minute')} ${unit(rest, 'second')}';
}

/// What a sheet opened from a running rest can do to that rest.
class RestCountdown {
  const RestCountdown({
    required this.reading,
    required this.onAdjust,
    required this.onSkip,
  });

  /// The rest's time left, repainted every second. Null once the rest is
  /// over, however it ended -- which closes the sheet.
  final ValueListenable<RestReading?> reading;

  /// Adds (or with a negative value, takes) seconds from this rest only.
  final void Function(int seconds) onAdjust;

  final VoidCallback onSkip;
}

/// The rest controls, as a bottom sheet so the logger itself stays as
/// uncluttered as it was: the app bar keeps one small tag, and everything
/// adjustable lives here.
///
/// Opened from the tag mid-rest with a [countdown], or from the logger's
/// menu without one, to set the default before the first set. Top to
/// bottom:
///  1. a running rest's countdown: the ring, ±30s and Skip;
///  2. the alert switch;
///  3. the default, folded mid-rest and open from the menu.
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
  late bool _defaultsOpen = widget.countdown == null;

  @override
  void initState() {
    super.initState();
    widget.countdown?.reading.addListener(_onTick);
  }

  @override
  void dispose() {
    // Safe even once the logger has disposed its notifier: removeListener
    // returns immediately after dispose.
    widget.countdown?.reading.removeListener(_onTick);
    super.dispose();
  }

  /// A rest that ends -- run out, skipped, or cut to nothing with −30s --
  /// takes its sheet with it: there is nothing left to control.
  void _onTick() {
    if (widget.countdown!.reading.value != null) return;
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

  /// "Default rest: 1:30 ▸". Mid-rest the sheet is about this rest, and the
  /// eleven chips that set every later one fold behind this row; tapping a
  /// chip looked like it changed the rest running now, and did not.
  Widget _defaultsRow(FsTokens t, int saved) => Semantics(
    button: true,
    expanded: _defaultsOpen,
    child: InkWell(
      key: const Key('rest.defaults'),
      onTap: () => setState(() => _defaultsOpen = !_defaultsOpen),
      borderRadius: BorderRadius.circular(FsRadius.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Default rest: ${formatRest(saved)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
            Icon(
              _defaultsOpen ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: t.text2,
            ),
          ],
        ),
      ),
    ),
  );

  /// A chip is painted small; its tap area is not. The chip's own ripple
  /// still answers a tap on the chip, and this catches the band around it.
  /// The band stays out of the semantics tree, so a screen reader stops on
  /// the labelled chip once rather than on a blank wrapper as well.
  Widget _chipTarget({
    required Key key,
    required VoidCallback onTap,
    required Widget chip,
  }) => GestureDetector(
    key: key,
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Center(widthFactor: 1, child: chip),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final countdown = widget.countdown;
    final saved = ref.watch(restSecondsProvider).value ?? defaultRestSeconds;
    final isPreset = restPresets.contains(saved);

    return SafeArea(
      key: const Key('rest.sheet'),
      // Scrolls only when it must: at the largest text on a small phone the
      // ring, the switch and the default together run taller than the
      // screen, and the last of them would otherwise be cut off.
      child: SingleChildScrollView(
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
              const SizedBox(height: 10),
              Center(
                child: ValueListenableBuilder<RestReading?>(
                  valueListenable: countdown.reading,
                  builder: (_, reading, _) {
                    final seconds = reading?.secondsLeft ?? 0;
                    // One spoken label, not a live region: it is read when
                    // focused, never every second.
                    return Semantics(
                      label: '${spokenRest(seconds)} of rest left',
                      excludeSemantics: true,
                      // Steps once a second with no tween, so Reduce Motion
                      // has nothing to switch off.
                      child: FsRing(
                        key: const Key('rest.ring'),
                        value: reading?.fractionLeft ?? 0,
                        color: t.amber,
                        // The ring stays 132 at any text size, so the
                        // number shrinks to fit inside the stroke rather
                        // than wrapping or running under it; at normal
                        // sizes it already fits and is left alone.
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18, // 11 stroke + air
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formatRest(seconds),
                              key: const Key('rest.sheet.remaining'),
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontFamily: fsMonoFamily,
                                fontSize: 40,
                                fontWeight: FontWeight.w700,
                                // Amber numbers measured 2.95:1 on the light
                                // sheet; the ring carries the amber.
                                color: t.text,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Remove 30 seconds',
                      excludeSemantics: true,
                      onTap: () => countdown.onAdjust(-30),
                      child: FsButton(
                        key: const Key('rest.minus'),
                        label: '−30s',
                        kind: FsButtonKind.secondary,
                        onPressed: () => countdown.onAdjust(-30),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Add 30 seconds',
                      excludeSemantics: true,
                      onTap: () => countdown.onAdjust(30),
                      child: FsButton(
                        key: const Key('rest.plus'),
                        label: '+30s',
                        kind: FsButtonKind.secondary,
                        onPressed: () => countdown.onAdjust(30),
                      ),
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
              const SizedBox(height: 18),
            ],
            const _RestAlertRow(),
            const SizedBox(height: 8),
            _defaultsRow(t, saved),
            if (_defaultsOpen) ...[
              const SizedBox(height: 4),
              Text(
                'Used from your next rest.',
                // text2, not text3: this line is the whole difference
                // between "this rest" and "every rest from now".
                style: TextStyle(fontSize: 12, color: t.text2),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final seconds in restPresets)
                    _chipTarget(
                      key: Key('rest.preset.$seconds.target'),
                      onTap: () => _save(seconds),
                      chip: FsChip(
                        key: Key('rest.preset.$seconds'),
                        label: formatRest(seconds),
                        selected: seconds == saved,
                        small: true,
                        onTap: () => _save(seconds),
                      ),
                    ),
                  _chipTarget(
                    key: const Key('rest.custom.target'),
                    onTap: () => _custom(saved),
                    chip: FsChip(
                      key: const Key('rest.custom'),
                      label: isPreset
                          ? 'Custom…'
                          : 'Custom (${formatRest(saved)})',
                      selected: !isPreset,
                      small: true,
                      onTap: () => _custom(saved),
                    ),
                  ),
                ],
              ),
            ],
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

/// "Alert me when rest ends": whether a rest that ends while the phone is
/// away sends a notification. On this phone only (RestAlertStore). When the
/// phone blocks notifications it says so and points to the phone's
/// settings, since FitSync asks for the permission once and never nags.
class _RestAlertRow extends ConsumerStatefulWidget {
  const _RestAlertRow();

  @override
  ConsumerState<_RestAlertRow> createState() => _RestAlertRowState();
}

class _RestAlertRowState extends ConsumerState<_RestAlertRow> {
  bool _granted = true;
  bool _asked = false;

  // "Open settings" leaves the app; on the way back the permission may have
  // changed, so the open sheet reads it again rather than going stale.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  // Both read what they need before the first wait: the sheet closes itself
  // when the rest runs out, which can land mid-wait, and `ref` is gone then.
  Future<void> _refresh() async {
    final scheduler = ref.read(restAlertSchedulerProvider);
    final store = ref.read(restAlertStoreProvider);
    final granted = await scheduler.permissionGranted();
    if (!mounted) return;
    final asked = await store.asked();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _asked = asked;
    });
  }

  Future<void> _set(bool on) async {
    final enabled = ref.read(restAlertEnabledProvider.notifier);
    final scheduler = ref.read(restAlertSchedulerProvider);
    final store = ref.read(restAlertStoreProvider);
    await enabled.set(on);
    if (!mounted) return;
    if (on && !_granted && !_asked) {
      await store.markAsked();
      if (!mounted) return;
      await scheduler.requestPermission();
      if (!mounted) return;
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final on = ref.watch(restAlertEnabledProvider).value ?? true;
    final blocked = on && !_granted && _asked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Alert me when rest ends',
                  style: TextStyle(fontSize: 14, color: t.text),
                ),
              ),
              Switch(key: const Key('rest.alert'), value: on, onChanged: _set),
            ],
          ),
        ),
        if (blocked)
          Column(
            key: const Key('rest.alert.blocked'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Notifications are blocked for FitSync. Allow them in your "
                "phone's settings to get rest alerts.",
                style: TextStyle(fontSize: 12, color: t.text2),
              ),
              TextButton(
                key: const Key('rest.alert.settings'),
                onPressed: () =>
                    ref.read(restAlertSchedulerProvider).openSettings(),
                child: const Text('Open settings'),
              ),
            ],
          ),
      ],
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
