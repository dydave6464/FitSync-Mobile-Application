import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../../plans/presentation/widgets/training_days_row.dart';
import '../../domain/routine.dart';
import '../providers.dart';

/// Adds a habit, or edits [existing] (with Delete). Closes on a save that
/// lands; stays open, saying why, on one that does not -- the check-in
/// sheet's rule.
///
/// [announceRepeats]: after a save that does not repeat on the day this
/// sheet opened on, say which days it does. Off where the caller already
/// shows the habit's days (All habits).
Future<void> showHabitSheet(
  BuildContext context, {
  Habit? existing,
  bool announceRepeats = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    isScrollControlled: true,
    builder: (_) =>
        _HabitSheet(existing: existing, announceRepeats: announceRepeats),
  );
}

class _HabitSheet extends ConsumerStatefulWidget {
  const _HabitSheet({this.existing, required this.announceRepeats});

  final Habit? existing;
  final bool announceRepeats;

  @override
  ConsumerState<_HabitSheet> createState() => _HabitSheetState();
}

class _HabitSheetState extends ConsumerState<_HabitSheet> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _duration = TextEditingController(
    text: widget.existing?.durationMin?.toString(),
  );
  late String? _time = widget.existing?.time;
  late List<int> _weekdays = [
    ...(widget.existing?.weekdays ?? const [1, 2, 3, 4, 5, 6, 7]),
  ];
  bool _busy = false;
  String? _error;

  /// Whether closing now would throw away what was typed or picked: any
  /// field that differs from what the sheet opened with. Never while a save
  /// is in flight -- that save still lands after the sheet has gone.
  bool get _dirty {
    if (_busy) return false;
    final existing = widget.existing;
    final days = existing?.weekdays ?? const [1, 2, 3, 4, 5, 6, 7];
    return _title.text != (existing?.title ?? '') ||
        _duration.text != (existing?.durationMin?.toString() ?? '') ||
        _time != existing?.time ||
        !(_weekdays.toSet().length == days.toSet().length &&
            _weekdays.toSet().containsAll(days));
  }

  /// How far the current drag has pulled the sheet down, while [_dirty]
  /// holds the drag back from the sheet itself.
  double _dragDown = 0;

  /// The weekday of the day the routine screen was showing when this sheet
  /// opened, 1-7. Read once, in initState, rather than each time it is
  /// needed: the provider may have already moved on to a different day by the
  /// time a slow save resolves, and what matters is what day the person who
  /// tapped Save was looking at. Not a lazy initialiser -- that would first
  /// run after the save's own reload, and so read the new day.
  late final int? _openedOnWeekday;

  @override
  void initState() {
    super.initState();
    _openedOnWeekday = DateTime.tryParse(
      ref.read(routineTodayProvider).value?.date ?? '',
    )?.weekday;
    // The fields are not rebuilt by typing; whether closing asks first
    // depends on what is in them.
    _title.addListener(_refresh);
    _duration.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    super.dispose();
  }

  /// The draft to send, or null after setting [_error]. Mirrors the server's
  /// rules so the common mistakes are caught without a round trip; the
  /// server still checks everything.
  HabitDraft? _draft() {
    final title = _title.text.trim();
    if (title.isEmpty) return _fail('Give the habit a name.');
    if (title.length > 60) return _fail('Keep the name to 60 characters.');
    final raw = _duration.text.trim();
    final duration = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty &&
        (duration == null || duration < 1 || duration > 600)) {
      return _fail('Duration is 1 to 600 minutes.');
    }
    if (_weekdays.isEmpty) return _fail('Pick at least one day.');
    return HabitDraft(
      title: title,
      time: _time,
      durationMin: duration,
      weekdays: _weekdays,
    );
  }

  HabitDraft? _fail(String message) {
    setState(() => _error = message);
    return null;
  }

  /// [action] returns the saved habit for add/edit, or null for remove --
  /// only a save that repeats on a day other than the one this sheet opened
  /// on gets a snackbar, telling the person what just happened to a habit
  /// that then dropped out of today's list with nothing else to say so.
  Future<void> _run(Future<Habit?> Function(RoutineController c) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Captured before the await: by the time it resolves this sheet's own
    // context may already be gone, popped off by the Navigator call below.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await action(ref.read(routineTodayProvider.notifier));
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.announceRepeats &&
          saved != null &&
          _openedOnWeekday != null &&
          !saved.weekdays.contains(_openedOnWeekday)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Saved — repeats ${formatWeekdays(saved.weekdays)}'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _save() async {
    final draft = _draft();
    if (draft == null) return;
    final existing = widget.existing;
    await _run(
      (c) => existing == null ? c.add(draft) : c.edit(existing.habitId, draft),
    );
  }

  /// Asks first: a mis-tap just under Save would otherwise remove the habit
  /// with nothing to say so and no way back.
  Future<void> _delete(Habit existing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this habit?'),
        content: Text('“${existing.title}” leaves your routine.'),
        actions: [
          TextButton(
            key: const Key('habit.delete.keep'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            key: const Key('habit.delete.confirm'),
            style: TextButton.styleFrom(foregroundColor: dialogContext.fs.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run((c) async {
      await c.remove(existing.habitId);
      return null;
    });
  }

  Future<void> _pickTime() async {
    final initial = _time == null
        ? const TimeOfDay(hour: 7, minute: 0)
        : TimeOfDay(
            hour: int.parse(_time!.substring(0, 2)),
            minute: int.parse(_time!.substring(3, 5)),
          );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    setState(() {
      _time =
          '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    // Typed or picked and not saved: back, a tap on the scrim and a swipe
    // down ask before throwing it away, as the check-in sheet does.
    // FsDiscardGuard covers back and the scrim, which ask the route to pop.
    // A drag down never asks -- the bottom sheet pops its route itself once
    // the drag ends -- so while dirty the drag is claimed here first and a
    // clear pull down asks the route to pop, which the guard turns into the
    // question.
    final dirty = _dirty;
    return FsDiscardGuard(
      dirty: dirty,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Kept out of semantics, so a dirty sheet does not tell a screen
        // reader it scrolls; screen readers close it through back or the
        // scrim, which the guard covers.
        excludeFromSemantics: true,
        onVerticalDragStart: dirty ? (_) => _dragDown = 0 : null,
        onVerticalDragUpdate: dirty
            ? (details) => _dragDown += details.primaryDelta ?? 0
            : null,
        onVerticalDragEnd: dirty
            ? (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (_dragDown > 48 || velocity > 700) {
                  Navigator.of(context).maybePop();
                }
              }
            : null,
        child: _content(),
      ),
    );
  }

  Widget _content() {
    final t = context.fs;
    final existing = widget.existing;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          10,
          18,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              existing == null ? 'New habit' : 'Edit habit',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 16),
            FsField(
              controller: _title,
              fieldKey: const Key('habit.title'),
              label: 'Name',
              hint: 'e.g. Morning mobility',
            ),
            const SizedBox(height: 12),
            Row(
              // The time button lines up with the duration box, not with
              // the duration's label above it.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  // The kit's secondary button: text-coloured on the
                  // surface, like the field beside it, where M3's outlined
                  // button fell back to the brand green (2.87:1 on white).
                  child: FsButton(
                    key: const Key('habit.time'),
                    kind: FsButtonKind.secondary,
                    small: true,
                    // Grows rather than cutting '7:00 AM' to '7:00 …' at
                    // large text, which would lose the AM/PM.
                    wrapLabel: true,
                    onPressed: _busy ? null : _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: _time == null ? 'Any time' : formatClock(_time!),
                  ),
                ),
                if (_time != null)
                  IconButton(
                    key: const Key('habit.time.clear'),
                    tooltip: 'Clear time',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _time = null),
                  ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: FsField(
                    controller: _duration,
                    fieldKey: const Key('habit.duration'),
                    label: 'Duration',
                    // No placeholder: the eyebrow names the field, and the
                    // 'min' suffix keeps its room even while hidden, so in
                    // 120 dp any word was cut off ('Optional' at 1x).
                    hint: '',
                    suffix: 'min',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const FsEyebrow('Repeat on'),
            const SizedBox(height: 8),
            TrainingDaysRow(
              selected: _weekdays,
              enabled: !_busy,
              onChanged: (days) => setState(() => _weekdays = days),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              FsErrorLine(_error!, key: const Key('habit.error')),
            ],
            const SizedBox(height: 18),
            FsButton(
              key: const Key('habit.save'),
              label: 'Save',
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
            if (existing != null) ...[
              const SizedBox(height: 6),
              TextButton(
                key: const Key('habit.delete'),
                onPressed: _busy ? null : () => _delete(existing),
                child: Text('Delete habit', style: TextStyle(color: t.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
