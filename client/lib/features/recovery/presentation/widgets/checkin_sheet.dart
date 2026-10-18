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

/// One question's ENUM column, its on-screen label and its options, every
/// scale worst first. They used to run in mixed directions -- sleep from poor
/// up, soreness from none up -- so the same spot on two rows meant opposite
/// things, and a tap by habit gave the wrong answer.
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
    values: ['severe', 'moderate', 'mild', 'none'],
  ),
  (
    field: 'energy',
    label: 'Energy',
    values: ['very_low', 'low', 'moderate', 'high'],
  ),
  (
    field: 'stress',
    label: 'Stress',
    values: ['high', 'moderate', 'low', 'very_low'],
  ),
];

/// `very_low` -> `Very low`. Only the leading character is cased; the raw
/// value underneath is untouched and is what actually gets posted.
String _displayLabel(String value) {
  final spaced = value.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// The morning check-in sheet: four questions, four chip rows, one save.
///
/// Pass [existing] when the user already answered today and is revisiting --
/// Update then opens on what was actually answered. A new check-in opens with
/// nothing chosen: pre-selected answers were saved by anyone who tapped Save
/// straight away, and fed the estimate a morning nobody described.
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
    if (widget.existing case final existing?) ...{
      'sleepQuality': existing.sleepQuality,
      'muscleSoreness': existing.muscleSoreness,
      'energy': existing.energy,
      'stress': existing.stress,
    },
  };

  /// Save waits for all four: a partial check-in has nothing honest to put
  /// in the missing columns.
  bool get _complete => _questions.every((q) => _answers.containsKey(q.field));

  bool _busy = false;
  String? _failure;

  Future<void> _save() async {
    if (_busy) return;
    // Captured before the await for the same reason as generator_screen's
    // _generate and session_logger_screen's _addToPlan: nothing sets
    // isDismissible: false or blocks the back gesture here, so the sheet can
    // be swiped away while checkIn is still in flight. ref.invalidate would
    // throw against a disposed State -- the container outlives the widget,
    // so the refresh still lands even when the sheet is already gone, which
    // is what should happen: the check-in really did save.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      // Sent exactly as stored in _answers -- see the class comment on
      // _questions for why nothing here may reshape these strings.
      await ref.read(recoveryRepositoryProvider).checkIn(_answers);
      container.invalidate(recoveryOverviewProvider);
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

    // Scrolls, so at large text on a small phone Save is still reachable
    // rather than pushed off the bottom of the sheet.
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
            const SizedBox(height: 6),
            Text(
              "Four quick questions. Your answers feed today's injury-risk "
              'estimate.',
              style: TextStyle(fontSize: 13, color: t.text2, height: 1.4),
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
              // Small gaps around the row: each band is a full 48 dp tall,
              // so the pills already sit apart by the band's own slack, and
              // there is no run spacing for the same reason.
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in q.values)
                    _AnswerTarget(
                      key: Key('checkin.${q.field}.$value.target'),
                      label: '${q.label}: ${_displayLabel(value)}',
                      selected: _answers[q.field] == value,
                      onTap: () {
                        if (_busy) return;
                        setState(() => _answers[q.field] = value);
                      },
                      child: FsChip(
                        key: Key('checkin.${q.field}.$value'),
                        label: _displayLabel(value),
                        selected: _answers[q.field] == value,
                        onTap: () {
                          if (_busy) return;
                          setState(() => _answers[q.field] = value);
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (_failure != null) ...[
              Text(_failure!, style: TextStyle(fontSize: 12, color: t.red)),
              const SizedBox(height: 12),
            ],
            FsButton(
              key: const Key('checkin.save'),
              label: 'Save',
              busy: _busy,
              onPressed: _busy || !_complete ? null : _save,
            ),
            if (!_complete) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Answer all four to save.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One answer's tap band: the pill as drawn, inside a full-size target.
///
/// FsChip is drawn about 30 dp tall, short of the 48 dp a thumb needs, and
/// fs_kit's other chip rows rely on that size, so the band is added here
/// rather than there. A tap on the pill itself still reaches its own ink;
/// one in the slack around it answers the same way.
///
/// A screen reader hears the question with the answer -- "Sleep: Poor" --
/// rather than a bare "Moderate" that three of the four rows share.
class _AnswerTarget extends StatelessWidget {
  const _AnswerTarget({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  static const _minTarget = 48.0;

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _minTarget,
            minHeight: _minTarget,
          ),
          child: Align(widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    );
  }
}
