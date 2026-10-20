import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../providers.dart'
    show
        bodyWeightProvider,
        profileProvider,
        profileRepositoryProvider,
        weightUnitProvider;

/// The bound `server/src/db/body-weight.js` enforces (`MIN_KG`/`MAX_KG`).
/// Checked here too, so a typo reads as a plain-language message instead of
/// a round trip and a 400.
const _minKg = 20.0;
const _maxKg = 500.0;

/// The Progress tab's "Add entry" sheet: one weight field, one save button.
/// A save refreshes every period of [bodyWeightProvider].
Future<void> showLogBodyWeightSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
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

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;

    final unit = ref.read(weightUnitProvider);
    final kg = parseWeight(_weight.text, unit);
    if (kg == null) {
      setState(() => _error = 'Enter a weight to log.');
      return;
    }
    if (kg < _minKg || kg > _maxKg) {
      setState(
        () => _error =
            'Enter a weight between '
            '${formatWeight(_minKg, unit)} and ${formatWeight(_maxKg, unit)} '
            '${unit.api}.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(profileRepositoryProvider).logBodyWeight(kg);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
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
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const Key('bodyWeight.error'),
                  style: TextStyle(fontSize: 12.5, color: t.red),
                ),
              ],
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
