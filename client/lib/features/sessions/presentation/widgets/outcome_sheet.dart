import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../profile/presentation/providers.dart'
    show injuryOptionsProvider;
import '../../domain/session_outcome.dart';
import '../providers.dart' show sessionRepositoryProvider;

/// Shown after a save that did not land. The session stays pending, so the
/// question comes back next time; nothing is queued.
const outcomeNotSavedMessage = "Couldn't save that. We'll ask again next time.";

/// `none` -> `None`. The label only; the raw value is what gets posted.
String _displayLabel(String value) =>
    value[0].toUpperCase() + value.substring(1);

/// "How did your last workout leave you?" -- one severity row, then a region
/// row once there is pain.
///
/// Completes when the sheet closes, however it closes: answered, dismissed,
/// or a save that failed. The caller opens the start sheet next either way.
Future<void> showOutcomeSheet(BuildContext context, PendingOutcome pending) {
  return showModalBottomSheet<void>(
    context: context,
    // The surface on the sheet's own Material, as checkin_sheet.dart does and
    // for its reason: the chips are InkWells and need a Material under them.
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    isScrollControlled: true,
    builder: (_) => _OutcomeSheet(pending: pending),
  );
}

class _OutcomeSheet extends ConsumerStatefulWidget {
  const _OutcomeSheet({required this.pending});

  final PendingOutcome pending;

  @override
  ConsumerState<_OutcomeSheet> createState() => _OutcomeSheetState();
}

class _OutcomeSheetState extends ConsumerState<_OutcomeSheet> {
  // Deliberately unlike checkin_sheet.dart, which seeds every question from a
  // _defaults map: nothing starts selected here. A default "none" would turn
  // everyone who taps through into a recorded "nothing hurt", manufacturing
  // exactly the false negatives this label exists to be free of.
  String? _painLevel;
  int? _injuryId;
  bool _busy = false;

  bool get _hasPain => _painLevel != null && _painLevel != 'none';

  bool get _complete => _painLevel == 'none' || (_hasPain && _injuryId != null);

  void _pickPain(String value) {
    if (_busy) return;
    setState(() {
      _painLevel = value;
      // A region belongs to pain; keeping it through "none" would let a
      // later severity tap resubmit a region nobody re-confirmed.
      if (value == 'none') _injuryId = null;
    });
  }

  Future<void> _submit() async {
    if (_busy || !_complete) return;
    // Captured before the await: the sheet can be swiped away mid-save, and
    // the snackbar belongs to the screen underneath, which outlives it.
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);

    Object? failure;
    try {
      await ref
          .read(sessionRepositoryProvider)
          .recordOutcome(
            widget.pending.sessionId,
            painLevel: _painLevel!,
            injuryId: _injuryId,
          );
    } catch (error) {
      failure = error;
    }

    // 409 means an earlier tap already stored this answer -- saved, not failed.
    final alreadyStored =
        failure is ApiException && failure.code == 'OUTCOME_EXISTS';
    if (failure != null && !alreadyStored) {
      messenger?.showSnackBar(
        const SnackBar(content: Text(outcomeNotSavedMessage)),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final regions = ref.watch(injuryOptionsProvider);

    TextStyle label() =>
        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text);

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
              'How did your last workout leave you?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.pending.title} · ${widget.pending.sessionDate}',
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
            const SizedBox(height: 16),
            Text('Any pain since?', style: label()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final level in painLevels)
                  FsChip(
                    key: Key('outcome.pain.$level'),
                    label: _displayLabel(level),
                    selected: _painLevel == level,
                    onTap: () => _pickPain(level),
                  ),
              ],
            ),
            if (_hasPain) ...[
              const SizedBox(height: 16),
              Text('Where?', style: label()),
              const SizedBox(height: 8),
              regions.when(
                data: (options) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in options)
                      FsChip(
                        key: Key('outcome.region.${option.injuryId}'),
                        label: option.name,
                        selected: _injuryId == option.injuryId,
                        onTap: () {
                          if (_busy) return;
                          setState(() => _injuryId = option.injuryId);
                        },
                      ),
                  ],
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                // Without regions a pain answer cannot be completed, so Save
                // stays off; "Not now" still gets the user to their workout.
                error: (_, _) => Text(
                  "Couldn't load body regions.",
                  style: TextStyle(fontSize: 12, color: t.red),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FsButton(
              key: const Key('outcome.submit'),
              label: 'Save',
              busy: _busy,
              onPressed: _busy || !_complete ? null : _submit,
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                key: const Key('outcome.skip'),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text('Not now', style: TextStyle(color: t.text3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
