import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/dates.dart';
import '../../../../core/manila_day.dart';
import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../providers.dart'
    show
        bodyWeightClockProvider,
        bodyWeightProvider,
        profileProvider,
        profileRepositoryProvider,
        weightUnitProvider;

/// The bound `server/src/db/body-weight.js` enforces (`MIN_KG`/`MAX_KG`).
/// Checked here too, so a typo reads as a plain-language message instead of
/// a round trip and a 400.
const _minKg = 20.0;
const _maxKg = 500.0;

/// The Progress tab's "Add entry" sheet: one weight field, the day it is
/// for (today unless a past day is picked), one save button. A save
/// refreshes every period of [bodyWeightProvider].
Future<void> showLogBodyWeightSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // It draws its own handle (PT-22).
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    // Matches showStartWorkoutSheet: full height rather than the default
    // 9/16 cap, so a wide accessibility text scale cannot push the field or
    // the save button past the bottom edge.
    isScrollControlled: true,
    builder: (_) => const _LogBodyWeightSheet(),
  );
}

class _LogBodyWeightSheet extends ConsumerStatefulWidget {
  const _LogBodyWeightSheet();

  @override
  ConsumerState<_LogBodyWeightSheet> createState() =>
      _LogBodyWeightSheetState();
}

class _LogBodyWeightSheetState extends ConsumerState<_LogBodyWeightSheet> {
  final _weight = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The day picked, as a Manila calendar date; null is today, which is
  /// left for the server to fill in, as it always has.
  DateTime? _day;

  /// What was typed when [_error] was about the number itself (empty, or
  /// out of range), which also flags the card; null for any other error.
  String? _flagged;

  @override
  void initState() {
    super.initState();
    _weight.addListener(_onTyped);
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  /// A changed number is a new answer: its flag and message go.
  void _onTyped() {
    if (_flagged == null || _weight.text == _flagged) return;
    setState(() {
      _flagged = null;
      _error = null;
    });
  }

  void _flag(String message) => setState(() {
    _error = message;
    _flagged = _weight.text;
  });

  /// Today in Manila, the day the server calls today, as a date.
  DateTime _today() =>
      DateTime.parse(manilaDayOf(ref.read(bodyWeightClockProvider)()));

  /// A year back at most: the chart's widest period.
  Future<void> _pickDay() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? today,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() => _day = picked == today ? null : picked);
  }

  /// "Today", "Yesterday", "Wed, Nov 4", with the year when it is not this
  /// one.
  String _dayLabel() {
    final day = _day;
    if (day == null) return 'Today';
    final today = _today();
    // By calendar date, not a duration: a day across a clock change is not
    // 24 hours long.
    if (DateUtils.isSameDay(
      day,
      DateTime(today.year, today.month, today.day - 1),
    )) {
      return 'Yesterday';
    }
    final date = '${weekdayShort[day.weekday - 1]}, ${shortDate(day)}';
    return day.year == today.year ? date : '$date ${day.year}';
  }

  /// The picked day as the server takes it, `YYYY-MM-DD`; null for today.
  String? get _loggedOn {
    final day = _day;
    if (day == null) return null;
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${day.year}-${pad(day.month)}-${pad(day.day)}';
  }

  Future<void> _save() async {
    if (_busy) return;

    final unit = ref.read(weightUnitProvider);
    final kg = parseWeight(_weight.text, unit);
    if (kg == null) {
      _flag('Enter a weight to log.');
      return;
    }
    if (kg < _minKg || kg > _maxKg) {
      _flag(
        'Enter a weight between '
        '${formatWeight(_minKg, unit)} and ${formatWeight(_maxKg, unit)} '
        '${unit.api}.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _flagged = null;
    });

    try {
      await ref
          .read(profileRepositoryProvider)
          .logBodyWeight(kg, loggedOn: _loggedOn);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userMessage(error);
        _busy = false;
      });
      return;
    }

    if (!mounted) return;
    // Every period holds the new point -- a week's weigh-in is in the month
    // and the year too -- and the family is kept alive, so refreshing only
    // the one on screen left the others showing the old weight and change.
    ref.invalidate(bodyWeightProvider);
    // The server's writeEntry also overwrites users.weight_kg when this is
    // the newest entry, so Profile and Settings -- both backed by
    // profileProvider, an AsyncNotifier that never refetches on its own --
    // would otherwise keep showing the pre-save weight for the rest of the
    // session, disagreeing with the log this sheet just wrote to.
    ref.invalidate(profileProvider);
    Navigator.of(context).pop();
  }

  /// The day, drawn as the About step draws date of birth: one button,
  /// said as what it sets.
  Widget _dayCard(FsTokens t) {
    final label = _dayLabel();
    return FsCard(
      key: const Key('bodyWeight.date'),
      small: true,
      onTap: _busy ? null : _pickDay,
      child: Semantics(
        label: 'Date',
        value: label,
        hint: 'Opens a date picker',
        excludeSemantics: true,
        child: Row(
          children: [
            const FsIconTile(icon: Icons.calendar_today_outlined, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                key: const Key('bodyWeight.dateText'),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: t.text3),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final unit = ref.watch(weightUnitProvider);

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          // Padding rather than a Scaffold's own inset handling: this is a
          // bare Container, not a Scaffold, so nothing else lifts the field
          // clear of the keyboard.
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: t.line2,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Log your weight',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('bodyWeight.close'),
                    icon: const Icon(Icons.close, size: 18),
                    // The sheet's only escape: without a name a screen
                    // reader announced just "Button".
                    tooltip: 'Close',
                    color: t.text3,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FsStatField(
                fieldKey: const Key('bodyWeight.field'),
                label: 'Weight',
                unit: unit.api,
                controller: _weight,
                error: _flagged != null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                FsErrorLine(_error!, key: const Key('bodyWeight.error')),
              ],
              const SizedBox(height: 14),
              _dayCard(t),
              const SizedBox(height: 8),
              Text(
                _day == null
                    ? "Logging again today replaces today's entry."
                    : 'Logging again for this day replaces its entry.',
                style: TextStyle(fontSize: 12, color: t.text2, height: 1.4),
              ),
              const SizedBox(height: 16),
              FsButton(
                key: const Key('bodyWeight.save'),
                label: 'Save',
                busy: _busy,
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
