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
Future<void> showHabitSheet(BuildContext context, {Habit? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    isScrollControlled: true,
    builder: (_) => _HabitSheet(existing: existing),
  );
}

class _HabitSheet extends ConsumerStatefulWidget {
  const _HabitSheet({this.existing});

  final Habit? existing;

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

  Future<void> _run(Future<void> Function(RoutineController c) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(routineTodayProvider.notifier));
      if (!mounted) return;
      Navigator.of(context).pop();
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
              hint: 'e.g. Morning mobility',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('habit.time'),
                    onPressed: _busy ? null : _pickTime,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(
                      _time == null ? 'Any time' : formatClock(_time!),
                    ),
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
                    hint: 'Minutes',
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
              Text(
                _error!,
                key: const Key('habit.error'),
                style: TextStyle(fontSize: 12, color: t.red),
              ),
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
                onPressed: _busy
                    ? null
                    : () => _run((c) => c.remove(existing.habitId)),
                child: Text('Delete habit', style: TextStyle(color: t.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
