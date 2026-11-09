import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../pro/presentation/pro_screen.dart';
// describeError lives beside the catalogue list rather than in core/ -- it is
// the one place that turns an ApiException into a sentence, and every screen
// imports it from there with `show`.
import '../../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../../profile/presentation/providers.dart'
    show bodyWeightProvider, profileProvider;
import '../../domain/share_preview.dart';
import '../../domain/shared_report.dart';
import '../../domain/volume_labels.dart' show volumeToday;
import '../providers.dart';
import '../share_actions.dart';
import 'progress_cards.dart' show periodProgressWords;
import 'share_preview_card.dart';

/// The sections a report can carry, in the order the page draws them.
///
/// Personal records and nutrition are in the prototype's list and not here:
/// neither exists in the app, and a toggle that produces an empty section is
/// worse than no toggle.
const _sections = [
  (key: 'volume', label: 'Training volume', pro: false, icon: Icons.show_chart),
  (
    key: 'bodyWeight',
    label: 'Body weight',
    pro: false,
    icon: Icons.monitor_weight_outlined,
  ),
  (
    key: 'muscles',
    label: 'Muscle balance',
    pro: true,
    icon: Icons.accessibility_new,
  ),
  (
    key: 'sessions',
    label: 'Recent sessions',
    pro: false,
    icon: Icons.event_note_outlined,
  ),
];

const _periodNames = {'week': 'Week', 'month': 'Month', 'year': 'Year'};

/// The expiry as a plain date, e.g. "October 19, 2026".
///
/// Built from the DateTime's own fields: there is no date formatting package
/// in this app, and pulling one in for a single sentence would be the larger
/// change. Local time, because the date the user is being told about is the
/// one their own calendar shows.
String formatShareExpiry(DateTime when) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
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
    // FsSheetHeader draws the handle (PT-22).
    showDragHandle: false,
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

/// The sections only a Pro account may share.
final _proKeys = {
  for (final s in _sections)
    if (s.pro) s.key,
};

class _ShareReportSheetState extends ConsumerState<_ShareReportSheet> {
  /// What the user asked for, entitlement aside. A Pro section stays true in
  /// here for a free account and is masked on the way out, so nothing has to
  /// be re-toggled if that account later becomes Pro.
  final _include = {for (final s in _sections) s.key: true};

  bool _busy = false;
  String? _failure;

  /// An inline confirmation ("Link copied."). Not a SnackBar: the sheet now
  /// stays open, and a SnackBar would sit behind it.
  String? _notice;

  /// The link this sheet made, once it has made one. Every Share, Copy and
  /// Open after that reuses it -- one POST per sheet -- and the switches lock,
  /// so the link always matches what they show.
  SharedReport? _link;

  /// True while Share, Copy or Open is running. A second tap in that time is
  /// ignored: before the link exists it would make a second one, and after
  /// it a second share replaces the open menu -- on Android share_plus then
  /// answers the first as unavailable, and the sheet would say the menu
  /// failed while it is on screen. Not drawn, so no setState: the buttons
  /// stay as they are and the tap simply does nothing.
  bool _acting = false;

  /// The include map the link was made with, entitlement mask applied. Once
  /// the link exists the rows draw from this, not from [_include] and the
  /// live Pro flag: an account that buys Pro (or lapses) with the sheet open
  /// must still see what the frozen link carries.
  Map<String, bool>? _sent;

  /// Read from the provider where it is needed rather than cached in
  /// initState: profileProvider is an AsyncNotifier, so at initState it is
  /// still loading and its value is null -- a field seeded there reads
  /// "free" for every account, Pro included.
  bool get _premium => ref.read(profileProvider).value?.isPremium ?? false;

  String get _window => shareWindowLabel(widget.period, volumeToday());

  /// The existing link, or a new one. Null when making it failed; the
  /// failure is already on screen.
  Future<SharedReport?> _ensureLink() async {
    final existing = _link;
    if (existing != null) return existing;

    setState(() {
      _busy = true;
      _failure = null;
      _notice = null;
    });

    try {
      // Masked rather than sent raw: buildReportSnapshot answers null for a
      // Pro section without Pro however it is asked, so sending true would
      // promise the coach a section the report cannot contain.
      final premium = _premium;
      final include = {
        for (final entry in _include.entries)
          entry.key: entry.value && (premium || !_proKeys.contains(entry.key)),
      };

      final report = await ref
          .read(sessionRepositoryProvider)
          .shareReport(period: widget.period, include: include);
      if (!mounted) return null;
      setState(() {
        _link = report;
        _sent = include;
        _busy = false;
      });
      return report;
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _busy = false;
        // describeError(Object) already falls back for anything that is not
        // an ApiException, so there is no second branch to write.
        _failure = describeError(error);
      });
      return null;
    }
  }

  Future<void> _share() async {
    if (_acting) return;
    _acting = true;
    try {
      final link = await _ensureLink();
      if (link == null || !mounted) return;

      // No name in the message: chat apps build preview cards server-side,
      // the same reason the page's <title> carries none.
      final text = 'My FitSync training report, $_window: ${link.url}';
      var opened = false;
      try {
        opened = await ref.read(shareActionsProvider).share(text);
      } catch (_) {
        opened = false;
      }
      if (!mounted || opened) return;

      await _copyToClipboard(
        link,
        notice: "Couldn't open the share menu, so the link was copied instead.",
        failure: "Couldn't open the share menu or copy the link. Try again.",
      );
    } finally {
      _acting = false;
    }
  }

  Future<void> _copy() async {
    if (_acting) return;
    _acting = true;
    try {
      final link = await _ensureLink();
      if (link == null || !mounted) return;
      await _copyToClipboard(
        link,
        notice: 'Link copied.',
        failure: "Couldn't copy the link. Try again.",
      );
    } finally {
      _acting = false;
    }
  }

  /// Puts the link on the clipboard and says [notice], or shows [failure]
  /// inline when the platform refuses -- not an unhandled error with
  /// nothing on screen.
  Future<void> _copyToClipboard(
    SharedReport link, {
    required String notice,
    required String failure,
  }) async {
    try {
      await Clipboard.setData(ClipboardData(text: link.url));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notice = null;
        _failure = failure;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _failure = null;
      _notice = notice;
    });
  }

  Future<void> _openPage() async {
    final link = _link;
    if (link == null || _acting) return;
    _acting = true;
    try {
      var opened = false;
      try {
        opened = await ref.read(shareActionsProvider).open(Uri.parse(link.url));
      } catch (_) {
        opened = false;
      }
      if (!mounted || opened) return;
      setState(
        () => _notice = "Couldn't open the browser. Copy the link instead.",
      );
    } finally {
      _acting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final premium = ref.watch(profileProvider).value?.isPremium ?? false;
    final link = _link;
    final locked = _busy || link != null;
    final shown = _sent ?? _include;

    final tiles = sharePreviewTiles(
      period: widget.period,
      summary: ref.watch(trainingSummaryProvider).value,
      analytics: ref.watch(trainingAnalyticsProvider(widget.period)).value,
      bodyWeight: ref.watch(bodyWeightProvider(widget.period)).value,
      includeVolume: shown['volume']!,
      includeBodyWeight: shown['bodyWeight']!,
    );

    // Scrolls once large text makes it taller than the sheet may be.
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FsSheetHeader.sideInset,
          10,
          FsSheetHeader.sideInset,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FsSheetHeader(
              title: 'Share with coach',
              leading: Icon(Icons.ios_share, size: 19, color: t.accentText),
            ),
            Text(
              'A link to ${periodProgressWords(widget.period)}, '
              'frozen as it is now.',
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
            const SizedBox(height: 12),
            SharePreviewCard(
              key: const Key('share.preview'),
              heading:
                  '${_periodNames[widget.period] ?? widget.period} · $_window',
              tiles: tiles,
            ),
            const SizedBox(height: 18),
            const FsEyebrow('Include in report'),
            const SizedBox(height: 2),
            Text(
              'Summary is always included.',
              style: TextStyle(fontSize: 11.5, color: t.text2),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _sections.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: t.line),
              _sectionRow(
                _sections[i],
                premium: premium,
                locked: locked,
                sent: _sent,
              ),
            ],
            if (_failure != null) ...[
              const SizedBox(height: 8),
              FsErrorLine(_failure!),
            ],
            const SizedBox(height: 16),
            if (link == null) ...[
              FsButton(
                key: const Key('share.share'),
                label: 'Share report',
                icon: const Icon(Icons.ios_share, size: 17),
                busy: _busy,
                onPressed: _busy ? null : _share,
              ),
              const SizedBox(height: 10),
              FsButton(
                key: const Key('share.copy'),
                label: 'Copy link',
                kind: FsButtonKind.secondary,
                onPressed: _busy ? null : _copy,
              ),
            ] else ...[
              Text(
                'Works until ${formatShareExpiry(link.expiresAt)}',
                key: const Key('share.ready'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: t.text2),
              ),
              const SizedBox(height: 10),
              FsButton(
                key: const Key('share.share'),
                label: 'Share again',
                icon: const Icon(Icons.ios_share, size: 17),
                onPressed: _share,
              ),
              const SizedBox(height: 10),
              FsButton(
                key: const Key('share.copy'),
                label: 'Copy link',
                kind: FsButtonKind.secondary,
                onPressed: _copy,
              ),
              const SizedBox(height: 10),
              FsButton(
                key: const Key('share.open'),
                label: 'See what your coach sees',
                kind: FsButtonKind.ghost,
                wrapLabel: true,
                onPressed: _openPage,
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Text(
                  _notice!,
                  key: const Key('share.notice'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: t.text2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionRow(
    ({String key, String label, bool pro, IconData icon}) s, {
    required bool premium,
    required bool locked,
    required Map<String, bool>? sent,
  }) {
    final t = context.fs;
    // Once the link exists, a Pro section it carries keeps its (disabled)
    // switch even if Pro has since lapsed, and one it was masked out of
    // shows as off even if Pro was bought since: the row says what the link
    // holds. Before that, the live entitlement decides.
    final carried = sent?[s.key];
    if (s.pro && !premium && carried != true) {
      return _LockedSection(label: s.label, sectionKey: s.key);
    }
    return SwitchListTile(
      key: Key('share.toggle.${s.key}'),
      contentPadding: EdgeInsets.zero,
      secondary: Icon(s.icon, size: 17, color: t.text2),
      value: carried ?? _include[s.key]!,
      onChanged: locked ? null : (on) => setState(() => _include[s.key] = on),
      // The label wraps rather than pushing the Pro tag past the switch:
      // 'Muscle balance' and its tag need about 270 dp at 2.0x text.
      title: Row(
        children: [
          Flexible(
            child: Text(
              s.label,
              style: TextStyle(fontSize: 13.5, color: t.text),
            ),
          ),
          if (s.pro) ...[const SizedBox(width: 8), const FsTag('Pro')],
        ],
      ),
    );
  }
}

/// A Pro section a free account cannot share, shown rather than hidden.
///
/// Same treatment as VolumeByMuscleCard on the Progress tab: the badge stays,
/// because it is what says the feature exists, and the line names what Pro
/// would add. The whole row opens the Pro screen.
///
/// A disabled switch was the other option and is worse: it reads as a setting
/// that failed rather than one that is not yours yet.
class _LockedSection extends StatelessWidget {
  const _LockedSection({required this.label, required this.sectionKey});

  final String label;
  final String sectionKey;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return InkWell(
      key: Key('share.locked.$sectionKey'),
      onTap: () => openProScreen(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 15, color: t.text3),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(fontSize: 13.5, color: t.text2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const FsTag('Pro'),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Unlock with Pro to show your coach where your volume goes.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: t.text3,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
