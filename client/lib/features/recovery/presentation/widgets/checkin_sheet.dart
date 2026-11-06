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
import '../../../../core/api_exception.dart';
import '../../../../core/manila_day.dart';
import '../../../nutrition/presentation/error_snack_bar.dart'
    show showErrorSnackBar;
import '../../../plans/presentation/start_workout_sheet.dart'
    show lookUpPendingOutcome;
import '../../../profile/presentation/providers.dart'
    show injuryOptionsProvider;
import '../../../sessions/domain/session_outcome.dart';
import '../../../sessions/presentation/providers.dart'
    show pendingOutcomeProvider, sessionRepositoryProvider;

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

/// Shown once the sheet has closed, when the check-in saved but the pain
/// answer did not. The workout stays pending, so the question comes back.
const painNotSavedMessage =
    "Couldn't save the pain answer. We'll ask again next time.";

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The pain row's heading for a workout on [sessionDate], seen on [today],
/// both `YYYY-MM-DD` in Manila. The server only asks about a workout 1-7 days
/// back, so a weekday name is never ambiguous -- except exactly a week ago,
/// which shares today's name, so it says "last". Parsed as UTC dates so a
/// daylight-saving change in the phone's own zone cannot shift a day.
String painRowHeading(String sessionDate, String today) {
  DateTime day(String ymd) => DateTime.parse('${ymd}T00:00:00Z');
  final session = day(sessionDate);
  final daysAgo = day(today).difference(session).inDays;
  if (daysAgo == 1) return "After yesterday's workout";
  final name = _weekdays[session.weekday - 1];
  return daysAgo == 7 ? "After last $name's workout" : "After $name's workout";
}

/// The morning check-in sheet: four questions, four chip rows, one save --
/// plus an optional pain question when a workout is waiting for one.
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
  /// The answers already stored: nothing, for a new check-in. One map seeds
  /// [_answers] and is what [_dirty] compares against, so a question added
  /// here is counted by both.
  late final Map<String, String> _saved = {
    if (widget.existing case final existing?) ...{
      'sleepQuality': existing.sleepQuality,
      'muscleSoreness': existing.muscleSoreness,
      'energy': existing.energy,
      'stress': existing.stress,
    },
  };

  late final Map<String, String> _answers = {..._saved};

  /// Save waits for all four: a partial check-in has nothing honest to put
  /// in the missing columns.
  bool get _complete => _questions.every((q) => _answers.containsKey(q.field));

  /// Whether closing now would throw answers away: any answer that differs
  /// from what was saved (nothing, for a new check-in), or a pain answer not
  /// yet stored. Never while a save is in flight -- that save still lands
  /// after the sheet has gone.
  bool get _dirty {
    if (_busy) return false;
    final changed =
        _answers.length != _saved.length ||
        _answers.entries.any((e) => _saved[e.key] != e.value);
    return changed || (_painLevel != null && !_painSaved);
  }

  /// How far the current drag has pulled the sheet down, while [_dirty]
  /// holds the drag back from the sheet itself.
  double _dragDown = 0;

  /// The workout the pain row asks about, once [lookUpPendingOutcome] has
  /// answered; null hides the row. Held here rather than watched: the save
  /// refreshes pendingOutcomeProvider, and the row must not vanish under the
  /// user mid-save or after a failed check-in.
  PendingOutcome? _pending;

  /// Optional, and nothing starts selected -- outcome_sheet.dart's reason: a
  /// default "none" would record "nothing hurt" for anyone tapping through.
  String? _painLevel;
  int? _injuryId;

  /// Set once this sheet has stored the pain answer, so a retry after a
  /// failed check-in does not post it a second time.
  bool _painSaved = false;

  bool get _hasPain => _painLevel != null && _painLevel != 'none';

  /// The pain row never blocks Save on its own -- only a pain level still
  /// waiting for its region does.
  bool get _painReady => !_hasPain || _injuryId != null;

  @override
  void initState() {
    super.initState();
    // After the first frame: the lookup may refresh pendingOutcomeProvider,
    // and a provider may not be modified while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Captured before the awaits: the sheet can be swiped away meanwhile.
      final container = ProviderScope.containerOf(context, listen: false);
      var pending = await lookUpPendingOutcome(context);
      if (pending == null) {
        // The cached answer can be stale: after DayRollover invalidates the
        // provider the next read is yesterday's settled null, still
        // refreshing, so the first check-in of the morning would miss the
        // workout that just became askable. Wait for the fresh lookup too;
        // a failure or a slow answer just leaves the row hidden.
        try {
          pending = await container
              .read(pendingOutcomeProvider.future)
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          pending = null;
        }
      }
      if (mounted && !_busy && _pending == null && pending != null) {
        setState(() => _pending = pending);
      }
    });
  }

  void _pickPain(String level) {
    if (_busy || _painSaved) return;
    setState(() {
      if (_painLevel == level) {
        // Tapping the chosen answer again takes the optional question back.
        _painLevel = null;
        _injuryId = null;
      } else {
        _painLevel = level;
        // A region belongs to pain; keeping it through "none" would let a
        // later severity tap resubmit a region nobody re-confirmed.
        if (level == 'none') _injuryId = null;
      }
    });
  }

  void _pickRegion(int injuryId) {
    if (_busy || _painSaved) return;
    setState(() => _injuryId = injuryId);
  }

  /// Posts the pain answer when one was given and this sheet has not stored
  /// it yet. Answers whether it failed. A 409 is not a failure: an earlier
  /// tap, or the start-workout sheet, already stored an answer for this
  /// workout.
  Future<bool> _savePain(ProviderContainer container) async {
    final pending = _pending;
    final level = _painLevel;
    if (pending == null || level == null || _painSaved) return false;
    try {
      await container
          .read(sessionRepositoryProvider)
          .recordOutcome(
            pending.sessionId,
            painLevel: level,
            injuryId: _hasPain ? _injuryId : null,
          );
    } on ApiException catch (error) {
      if (error.code != 'OUTCOME_EXISTS') return true;
    } catch (_) {
      return true;
    }
    if (mounted) {
      setState(() => _painSaved = true);
    } else {
      _painSaved = true;
    }
    // The start-workout sheet answers from this provider's settled value, so
    // a stored answer must replace it or that sheet asks about this workout
    // again.
    container.refresh(pendingOutcomeProvider);
    return false;
  }

  bool _busy = false;
  String? _failure;

  Future<void> _save() async {
    if (_busy) return;
    // Captured before the awaits for the same reason as generator_screen's
    // _generate and session_logger_screen's _addToPlan: the discard guard
    // stands down during a save, so the sheet can still be swiped away
    // while the request is in flight. ref would throw
    // against a disposed State -- the container outlives the widget, so the
    // refresh still lands even when the sheet is already gone, which is what
    // should happen: the check-in really did save. The messenger is the
    // screen's underneath, which is where a message must show once the sheet
    // has closed.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _busy = true;
      _failure = null;
    });

    // First, so the estimate the check-in triggers already counts this pain.
    final painNotSaved = await _savePain(container);

    try {
      // Sent exactly as stored in _answers -- see the class comment on
      // _questions for why nothing here may reshape these strings.
      await container.read(recoveryRepositoryProvider).checkIn(_answers);
      container.invalidate(recoveryOverviewProvider);
      if (mounted) Navigator.of(context).pop();
      if (painNotSaved && messenger != null) {
        showErrorSnackBar(messenger, painNotSavedMessage);
      }
    } catch (error) {
      if (!mounted) {
        // Dismissed mid-save: the error line went with the sheet, so the
        // failure is said on the screen underneath instead.
        if (messenger != null) {
          showErrorSnackBar(
            messenger,
            "Your check-in wasn't saved. ${describeError(error)}",
          );
        }
        return;
      }
      setState(() {
        _busy = false;
        _failure = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    // Answers given and not saved make back, a tap on the scrim and a swipe
    // down ask before throwing them away. FsDiscardGuard covers back and the
    // scrim, which both ask the route to pop. A drag down never asks: the
    // bottom sheet pops its route itself once the drag ends. So while dirty
    // the drag is claimed here first -- the innermost vertical-drag
    // recognizer wins the arena, as in exercise_swap_sheet -- and a clear
    // pull down asks the route to pop, which the guard turns into the
    // question.
    final dirty = _dirty;
    return FsDiscardGuard(
      dirty: dirty,
      message: "Your check-in answers won't be saved.",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Kept out of semantics: otherwise a dirty sheet tells a screen
        // reader it scrolls, and a scroll gesture runs these callbacks into
        // the discard question. Screen readers close the sheet through back,
        // escape or the scrim, which the guard already covers.
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
        child: _content(t),
      ),
    );
  }

  /// The tallest the sheet grows, as the How to read sheet: a strip of the
  /// Recovery tab stays in view above it, and its title never slides under
  /// the status bar.
  static const _maxHeightFraction = 0.9;

  Widget _content(FsTokens t) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _maxHeightFraction,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The handle the How to read sheet draws, so the two sheets on
            // this tab look and close alike.
            Center(
              child: Container(
                key: const Key('checkin.handle'),
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  color: t.line2,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            // Everything below the handle scrolls, so at large text on a
            // small phone Save is still reachable rather than pushed off the
            // bottom of the sheet.
            Flexible(child: _questionsAndSave(t)),
          ],
        ),
      ),
    );
  }

  Widget _questionsAndSave(FsTokens t) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Morning check-in',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // One short line, the same with or without the pain question:
          // why the sheet asks, not how many questions it has -- the
          // questions are right below, and the pain one has its own heading.
          Text(
            "Helps estimate today's injury risk.",
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
          if (_pending case final pending?) ..._painRow(pending, t),
          if (_failure != null) ...[
            // A live region: a screen reader says the failure when it
            // appears, not just the button's loading ending.
            FsErrorLine(_failure!, key: const Key('checkin.error')),
            const SizedBox(height: 12),
          ],
          FsButton(
            key: const Key('checkin.save'),
            label: 'Save',
            busy: _busy,
            onPressed: _busy || !_complete || !_painReady ? null : _save,
          ),
          if (!_complete || !_painReady) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                !_complete
                    ? 'Answer all four to save.'
                    : 'Pick where it hurts, or tap '
                          '${_displayLabel(_painLevel!)} again to skip this '
                          'question.',
                key: const Key('checkin.hint'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: t.text2),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // A button as well as the drag, the scrim and back, so closing
          // never depends on a swipe. It asks the route to pop, so answers
          // given still meet the discard question first. Off mid-save: the
          // guard stands down then, and closing would not stop the save, so
          // a Cancel there would cancel nothing.
          FsButton(
            key: const Key('checkin.cancel'),
            label: 'Cancel',
            kind: FsButtonKind.ghost,
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  /// The optional pain question: a heading naming the workout's day, the
  /// four levels, and -- once there is pain -- where.
  List<Widget> _painRow(PendingOutcome pending, FsTokens t) {
    final label = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: t.text,
    );
    return [
      const SizedBox(height: 4),
      Divider(color: t.line2, height: 1),
      const SizedBox(height: 14),
      Text.rich(
        key: const Key('checkin.painHeading'),
        TextSpan(
          children: [
            TextSpan(
              text: painRowHeading(
                pending.sessionDate,
                manilaDayOf(DateTime.now()),
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.text2,
              ),
            ),
            TextSpan(
              text: ' · optional',
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      // Once stored, the answer cannot change from here, so the chips go
      // rather than sit there looking tappable while ignoring taps.
      if (_painSaved) ...[
        Text(
          'Pain answer saved.',
          style: TextStyle(fontSize: 13, color: t.text2),
        ),
        const SizedBox(height: 8),
      ] else
        ..._painQuestion(label),
    ];
  }

  /// The pain row's question itself: the four levels and -- once there is
  /// pain -- where.
  List<Widget> _painQuestion(TextStyle label) {
    return [
      Text('Any pain since?', style: label),
      const SizedBox(height: 2),
      Wrap(
        spacing: 8,
        children: [
          for (final level in painLevels)
            _AnswerTarget(
              key: Key('checkin.pain.$level.target'),
              label: 'Any pain since: ${_displayLabel(level)}',
              selected: _painLevel == level,
              onTap: () => _pickPain(level),
              child: FsChip(
                key: Key('checkin.pain.$level'),
                label: _displayLabel(level),
                selected: _painLevel == level,
                onTap: () => _pickPain(level),
              ),
            ),
        ],
      ),
      if (_hasPain) ...[
        const SizedBox(height: 8),
        Text('Where?', style: label),
        const SizedBox(height: 2),
        ref
            .watch(injuryOptionsProvider)
            .when(
              data: (options) => Wrap(
                spacing: 8,
                children: [
                  for (final option in options)
                    _AnswerTarget(
                      key: Key('checkin.region.${option.injuryId}.target'),
                      label: 'Where: ${option.name}',
                      selected: _injuryId == option.injuryId,
                      onTap: () => _pickRegion(option.injuryId),
                      child: FsChip(
                        key: Key('checkin.region.${option.injuryId}'),
                        label: option.name,
                        selected: _injuryId == option.injuryId,
                        onTap: () => _pickRegion(option.injuryId),
                      ),
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
              // The provider is not autoDispose, so without a retry the
              // error would stay cached until the app restarts. Tapping the
              // pain level again still frees Save meanwhile.
              error: (_, _) => FsRetry(
                message: "Couldn't load body regions.",
                buttonKey: const Key('checkin.regions.retry'),
                onRetry: () => ref.invalidate(injuryOptionsProvider),
              ),
            ),
      ],
      const SizedBox(height: 8),
    ];
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
