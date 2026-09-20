import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
// describeError lives beside the catalogue list rather than in core/ -- it is
// the one place that turns an ApiException into a sentence, and every screen
// imports it from there with `show`.
import '../../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../providers.dart';

/// The sections a report can carry, in the order the page draws them.
///
/// Personal records and nutrition are in the prototype's list and not here:
/// neither exists in the app, and a toggle that produces an empty section is
/// worse than no toggle.
const _sections = [
  (key: 'volume', label: 'Training volume', pro: false),
  (key: 'bodyWeight', label: 'Body weight', pro: false),
  (key: 'muscles', label: 'Muscle balance', pro: true),
  (key: 'sessions', label: 'Recent sessions', pro: false),
];

/// The expiry as a plain date, e.g. "October 19, 2026".
///
/// Built from the DateTime's own fields: there is no date formatting package
/// in this app, and pulling one in for a single sentence would be the larger
/// change. Local time, because the date the user is being told about is the
/// one their own calendar shows.
String formatShareExpiry(DateTime when) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final local = when.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

Future<void> showShareReportSheet(
  BuildContext context, {
  required String period,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // The surface goes on the sheet's own Material, the way ExerciseJumpSheet
    // is shown, rather than the Colors.transparent-plus-Container arrangement
    // the body-weight and start-workout sheets use. Those draw custom rows;
    // this one's rows are SwitchListTiles, which paint their background and
    // ink splashes on the nearest Material ancestor -- a coloured box between
    // tile and Material hides the splashes and trips an assertion. Transparent
    // with nothing painting in its place is what left the sheet see-through.
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    // Matches showLogBodyWeightSheet: full height rather than the default
    // 9/16 cap, so a wide accessibility text scale cannot push the button
    // past the bottom edge.
    isScrollControlled: true,
    builder: (_) => _ShareReportSheet(period: period),
  );
}

class _ShareReportSheet extends ConsumerStatefulWidget {
  const _ShareReportSheet({required this.period});

  final String period;

  @override
  ConsumerState<_ShareReportSheet> createState() => _ShareReportSheetState();
}

class _ShareReportSheetState extends ConsumerState<_ShareReportSheet> {
  final _include = {for (final s in _sections) s.key: true};
  bool _busy = false;
  String? _failure;

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      final report = await ref
          .read(sessionRepositoryProvider)
          .shareReport(period: widget.period, include: _include);
      await Clipboard.setData(ClipboardData(text: report.url));
      if (!mounted) return;
      Navigator.of(context).pop();
      // The real expiry, not a hardcoded "30 days". The server already sends
      // it, SharedReport already parses it, and a literal here is a fourth
      // copy of a constant that only the server is entitled to decide -- one
      // that goes quietly wrong the day the TTL changes.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Link copied. It works until ${formatShareExpiry(report.expiresAt)}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // describeError(Object) already falls back for anything that is not
        // an ApiException, so there is no second branch to write.
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
          18, 10, 18, MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FsEyebrow('Share with coach'),
            const SizedBox(height: 6),
            Text(
              'A link to this window, frozen as it is now.',
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
            const SizedBox(height: 14),
            for (final s in _sections)
              SwitchListTile(
                key: Key('share.toggle.${s.key}'),
                contentPadding: EdgeInsets.zero,
                value: _include[s.key]!,
                onChanged: _busy
                    ? null
                    : (on) => setState(() => _include[s.key] = on),
                title: Row(
                  children: [
                    Text(s.label, style: TextStyle(fontSize: 13.5, color: t.text)),
                    if (s.pro) ...[
                      const SizedBox(width: 8),
                      const FsTag('Pro'),
                    ],
                  ],
                ),
              ),
            if (_failure != null) ...[
              const SizedBox(height: 8),
              Text(_failure!, style: TextStyle(fontSize: 12, color: t.red)),
            ],
            const SizedBox(height: 14),
            FsButton(
              key: const Key('share.create'),
              label: 'Create link',
              busy: _busy,
              onPressed: _busy ? null : _create,
            ),
          ],
        ),
      ),
    );
  }
}
