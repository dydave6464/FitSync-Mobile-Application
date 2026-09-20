import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
// describeError lives beside the catalogue list rather than in core/ -- it is
// the one place that turns an ApiException into a sentence, and every screen
// imports it from there with `show`.
import '../../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../domain/recovery.dart';
import '../providers.dart';

/// One question's ENUM column, its on-screen label and its options in the
/// order the design shows them.
///
/// [values] are the server's own spellings -- ml/app/risk.py looks each one
/// up with a defaulting get, so anything sent that is not exactly one of
/// these strings scores a silent zero rather than raising. The chip's label
/// may be prettified; the value handed to [RecoveryRepository.checkIn] must
/// never be.
const _questions = <({String field, String label, List<String> values})>[
  (
    field: 'sleepQuality',
    label: 'Sleep',
    values: ['poor', 'fair', 'good', 'excellent'],
  ),
  (
    field: 'muscleSoreness',
    label: 'Soreness',
    values: ['none', 'mild', 'moderate', 'severe'],
  ),
  (
    field: 'energy',
    label: 'Energy',
    values: ['very_low', 'low', 'moderate', 'high'],
  ),
  (
    field: 'stress',
    label: 'Stress',
    values: ['very_low', 'low', 'moderate', 'high'],
  ),
];

/// The neutral-ish default for each scale, used when there is no [MorningCheckin]
/// to seed from yet.
const _defaults = <String, String>{
  'sleepQuality': 'good',
  'muscleSoreness': 'none',
  'energy': 'moderate',
  'stress': 'low',
};

/// `very_low` -> `Very low`. Only the leading character is cased; the raw
/// value underneath is untouched and is what actually gets posted.
String _displayLabel(String value) {
  final spaced = value.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// The morning check-in sheet: four questions, four chip rows, one save.
///
/// Pass [existing] when the user already answered today and is revisiting --
/// Update then opens on what was actually answered rather than the defaults.
Future<void> showCheckinSheet(
  BuildContext context, {
  MorningCheckin? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // The surface goes on the sheet's own Material -- see share_report_sheet's
    // note on the same choice. This sheet's chips are InkWells on a Material
    // too, so Colors.transparent-plus-Container would only relocate the same
    // bug that once made a copy of that pattern render see-through.
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    isScrollControlled: true,
    builder: (_) => _CheckinSheet(existing: existing),
  );
}

class _CheckinSheet extends ConsumerStatefulWidget {
  const _CheckinSheet({this.existing});

  final MorningCheckin? existing;

  @override
  ConsumerState<_CheckinSheet> createState() => _CheckinSheetState();
}

class _CheckinSheetState extends ConsumerState<_CheckinSheet> {
  late final Map<String, String> _answers = {
    'sleepQuality': widget.existing?.sleepQuality ?? _defaults['sleepQuality']!,
    'muscleSoreness':
        widget.existing?.muscleSoreness ?? _defaults['muscleSoreness']!,
    'energy': widget.existing?.energy ?? _defaults['energy']!,
    'stress': widget.existing?.stress ?? _defaults['stress']!,
  };

  bool _busy = false;
  String? _failure;

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      // Sent exactly as stored in _answers -- see the class comment on
      // _questions for why nothing here may reshape these strings.
      await ref.read(recoveryRepositoryProvider).checkIn(_answers);
      ref.invalidate(recoveryOverviewProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          10,
          18,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Morning check-in',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 16),
            for (final q in _questions) ...[
              Text(
                q.label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in q.values)
                    FsChip(
                      key: Key('checkin.${q.field}.$value'),
                      label: _displayLabel(value),
                      selected: _answers[q.field] == value,
                      onTap: () {
                        if (_busy) return;
                        setState(() => _answers[q.field] = value);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_failure != null) ...[
              Text(_failure!, style: TextStyle(fontSize: 12, color: t.red)),
              const SizedBox(height: 12),
            ],
            FsButton(
              key: const Key('checkin.save'),
              label: 'Save',
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
