import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../exercises/presentation/exercise_list_screen.dart'
    show describeError;
import '../../../profile/domain/profile.dart';
import '../../../profile/presentation/providers.dart';
import '../../domain/split_style.dart';
import '../../domain/week_description.dart';
import '../providers.dart';

/// How long typing has to stop before the phone reads the sentence.
const kPhoneReadDelay = Duration(milliseconds: 400);

/// How long typing has to stop before the server's AI is asked.
const kAiReadDelay = Duration(milliseconds: 1500);

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The prototype's "Describe your week" card.
///
/// Read as it is typed: the phone's reader after a short pause, then the
/// server's AI after a longer one, and the lines under the field say what was
/// understood. A split or a length lands in the controls below, where the
/// user can see and correct it; weekdays and injuries are only offered, and
/// reach the profile on their own tap. Nothing here reaches the generator
/// directly: the payload carries the controls, not this sentence.
class DescribeWeekCard extends ConsumerStatefulWidget {
  const DescribeWeekCard({
    super.key,
    required this.composed,
    required this.options,
    required this.catalogueFailed,
    required this.trainingDays,
    required this.onSplit,
    required this.onLength,
    this.onDayCount,
  });

  /// The sentence "From profile" writes, composed from the live profile and
  /// plan. It is the baseline: read for its lines, never applied.
  final String composed;

  final List<InjuryOption> options;

  /// Whether the injury catalogue failed to load. Distinct from an empty
  /// catalogue: one means "nothing matched", the other means "nothing could
  /// be checked", and only one of those is safe to say.
  final bool catalogueFailed;

  /// The weekdays currently ticked below: whether named days are already
  /// the user's, and whether a day count has anywhere to land.
  final List<int> trainingDays;

  /// A split the sentence changed to.
  final ValueChanged<String> onSplit;

  /// A length (45 or 60) the sentence changed to.
  final ValueChanged<int> onLength;

  /// A day count the sentence changed to. The screen keeps it for when no
  /// weekday is ticked; while any is, the picker sets the count.
  final ValueChanged<int>? onDayCount;

  @override
  ConsumerState<DescribeWeekCard> createState() => _DescribeWeekCardState();
}

class _DescribeWeekCardState extends ConsumerState<DescribeWeekCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.composed,
  );

  /// The sentence written for the user (on open, by following an untouched
  /// box, or by From profile). Its reading shows lines and applies nothing,
  /// and it is never sent to the AI.
  late String _baseline;

  /// The reading on screen and the text it was read from. Each new reading
  /// applies only what changed from this one, so a chip tapped by hand
  /// survives typing that does not mention it.
  WeekDescription? _shown;
  String _shownText = '';

  /// The last text sent to the AI, so the same text is not asked twice.
  String? _lastSent;

  /// The server said the day's AI readings are used up: say so once and stop
  /// asking from this screen.
  bool _limitReached = false;

  Timer? _phoneTimer;
  Timer? _aiTimer;

  /// Regions the user has dismissed by adding them, kept so the offer goes
  /// away the moment the write succeeds rather than waiting for the profile
  /// to come back round.
  final Set<int> _added = {};

  int? _adding;
  bool _savingDays = false;

  @override
  void initState() {
    super.initState();
    _setBaseline(widget.composed);
  }

  @override
  void didUpdateWidget(DescribeWeekCard old) {
    super.didUpdateWidget(old);
    // The profile is fetched separately from the plan, so the first build of
    // this card routinely happens before there is a goal to write about. The
    // box has to follow what it describes until the user takes it over --
    // comparing against the PREVIOUS sentence is what tells those apart:
    // still untouched means still ours to fill, edited means hands off.
    if (widget.composed != old.composed && _controller.text == old.composed) {
      _controller.text = widget.composed;
      _setBaseline(widget.composed);
    }
  }

  @override
  void dispose() {
    _phoneTimer?.cancel();
    _aiTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Makes [text] the baseline and shows its reading, applying nothing.
  /// Called from initState and didUpdateWidget too, so it sets fields
  /// without setState: those rebuild anyway.
  void _setBaseline(String text) {
    _phoneTimer?.cancel();
    _aiTimer?.cancel();
    _baseline = text;
    _shown = parseWeekDescription(text, widget.options);
    _shownText = text;
  }

  void _onChanged(String text) {
    _phoneTimer?.cancel();
    _aiTimer?.cancel();
    _phoneTimer = Timer(
      kPhoneReadDelay,
      () => _read(text, parseWeekDescription(text, widget.options)),
    );
    _aiTimer = Timer(kAiReadDelay, () {
      if (text == _baseline ||
          text.trim().split(RegExp(r'\s+')).length < 2 ||
          text == _lastSent ||
          _limitReached) {
        return;
      }
      _askAi(text);
    });
  }

  /// Shows [next] and applies what changed from the reading it replaces,
  /// unless [text] is the baseline.
  void _read(String text, WeekDescription next) {
    if (!mounted) return;
    final previous = _shown;
    if (text != _baseline) {
      final split = next.splitStyle;
      if (split != null && split != previous?.splitStyle) {
        widget.onSplit(split);
      }
      final length = next.sessionLengthMin;
      if (length != null && length != previous?.sessionLengthMin) {
        widget.onLength(length);
      }
      final count = next.daysPerWeek;
      if (count != null && count != previous?.daysPerWeek) {
        widget.onDayCount?.call(count);
      }
    }
    setState(() {
      _shown = next;
      _shownText = text;
    });
  }

  Future<void> _askAi(String text) async {
    _lastSent = text;
    try {
      final reading = await ref.read(planRepositoryProvider).readWeek(text);
      // Typing went on while the AI read: its answer is for words that are
      // no longer there.
      if (!mounted || _controller.text != text) return;
      _read(text, reading);
    } on ApiException catch (error) {
      if (error.code == 'READ_LIMIT' && mounted) {
        setState(() => _limitReached = true);
      }
      // Anything else (busy, offline): the phone's lines stay, unremarked.
    } catch (_) {
      // As above: the AI is an extra, and its failure says nothing.
    }
  }

  Future<void> _useDays(List<int> days) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingDays = true);
    try {
      await ref.read(profileProvider.notifier).setTrainingDays(days);
    } catch (error) {
      if (!mounted) return;
      // The button stays: nothing was saved, so nothing should look saved.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not save your training days. ${describeError(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDays = false);
    }
  }

  Future<void> _add(SelectedInjury injury) async {
    final messenger = ScaffoldMessenger.of(context);
    final current =
        ref.read(profileProvider).value?.injuries ?? const <SelectedInjury>[];
    setState(() => _adding = injury.injuryId);
    try {
      // PUT /profile/injuries replaces the whole set, so the existing
      // injuries go back with it. Sending only the new region would delete
      // every other injury the user has.
      await ref.read(profileProvider.notifier).setInjuries([
        ...current,
        injury,
      ]);
      if (!mounted) return;
      setState(() {
        _added.add(injury.injuryId);
        _adding = null;
      });
    } catch (error) {
      if (!mounted) return;
      // The offer stays: nothing was saved, so nothing should look saved.
      setState(() => _adding = null);
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  /// Regions the sentence named that the profile does not already carry.
  List<({InjuryOption option, SelectedInjury injury})> _offers(
    WeekDescription reading,
  ) {
    final held = {
      for (final i
          in ref.watch(profileProvider).value?.injuries ??
              const <SelectedInjury>[])
        i.injuryId,
    };

    return [
      for (final injury in reading.injuries)
        if (!held.contains(injury.injuryId) &&
            !_added.contains(injury.injuryId))
          for (final option in widget.options)
            if (option.injuryId == injury.injuryId)
              (option: option, injury: injury),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final lines = _lines(t);

    return FsCard(
      // While the chip ends the card, the card's padding below it, outside
      // the Column, is its room. Once the lines end the card, a tap there
      // lands on the last line, and under an offer's centred button it
      // answers nothing.
      child: FsTapRoom(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FsEyebrow('Describe your week'),
            const SizedBox(height: 8),
            FsField(
              key: const Key('gen.describe.field'),
              controller: _controller,
              hint: 'e.g. full body, 4 days a week, protecting my lower back',
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              // A sentence needs no new lines, so Return is Done; it and a
              // tap anywhere else close the keyboard and bring Generate back.
              textInputAction: TextInputAction.done,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 10),
            FsTapRoom(
              // An action, not a choice: as the prototype's sm chips, off,
              // and announced with no selected state.
              child: FsChip(
                key: const Key('gen.describe.fromProfile'),
                label: 'From profile',
                selected: false,
                toggle: false,
                onTap: () => setState(() {
                  _controller.text = widget.composed;
                  _setBaseline(widget.composed);
                  _added.clear();
                }),
              ),
            ),
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 6),
              // One polite announcement per reading, not per keystroke: the
              // lines only change when a reading lands.
              Semantics(
                key: const Key('gen.describe.lines'),
                liveRegion: true,
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: lines,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// What the reading on screen understood, in the spec's order.
  List<Widget> _lines(FsTokens t) {
    final reading = _shown;
    final note = TextStyle(fontSize: 12, color: t.text3, height: 1.35);
    final limit = _limitReached
        ? Padding(
            key: const Key('gen.describe.limit'),
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'AI reading is used up for today. Showing the quick reading.',
              style: note,
            ),
          )
        : null;

    // An empty box says nothing: its hint is already the example.
    if (reading == null || _shownText.trim().isEmpty) {
      return [?limit];
    }

    final understood = <Widget>[];

    final split = reading.splitStyle;
    if (split != null) {
      understood.add(
        _line(t, Icons.view_week_outlined, 'Split: ${splitLabel(split)}'),
      );
    }

    final length = reading.sessionLengthMin;
    if (length != null) {
      final requested = reading.requestedMinutes;
      understood.add(
        _line(
          t,
          Icons.timer_outlined,
          requested == null || requested == length
              ? 'Length: $length min'
              : 'Length: $length min (nearest to $requested)',
        ),
      );
    }

    final weekdays = [
      for (final d in reading.weekdays)
        if (d >= 1 && d <= 7) d,
    ];
    if (weekdays.isNotEmpty) {
      final named =
          'Days: ${weekdays.map((d) => _weekdayNames[d - 1]).join(' · ')}';
      final ticked = widget.trainingDays.toList()..sort();
      understood.add(
        listEquals(weekdays, ticked)
            ? _line(
                t,
                Icons.calendar_month_outlined,
                '$named (already your days)',
              )
            : _line(
                t,
                Icons.calendar_month_outlined,
                named,
                action: FsButton(
                  key: const Key('gen.describe.useDays'),
                  label: 'Use these days',
                  small: true,
                  // Read whole at large text, rather than cut to "Use th…".
                  wrapLabel: true,
                  kind: FsButtonKind.secondary,
                  busy: _savingDays,
                  onPressed: () => _useDays(weekdays),
                ),
              ),
      );
    }

    final count = reading.daysPerWeek;
    // A count that matches the ticked days was not overruled, so there is
    // nothing to say about it. The filled-in sentence is the common case: it
    // writes its count from those same days.
    if (count != null &&
        weekdays.isEmpty &&
        count != widget.trainingDays.length) {
      understood.add(
        _line(
          t,
          Icons.date_range_outlined,
          widget.trainingDays.isEmpty
              ? '${daysAWeek(count)}: tick which days below'
              : 'How many days you train follows the weekdays you have '
                    'chosen below, so that count was not applied.',
        ),
      );
    }

    // Said whatever else was read: the catalogue is what injury matching
    // depends on, so without it "no regions matched" is a claim this card
    // cannot support.
    if (widget.catalogueFailed) {
      understood.add(
        const Padding(
          key: Key('gen.describe.catalogueError'),
          padding: EdgeInsets.only(top: 6),
          child: FsErrorLine(
            "Couldn't check that against your injuries. Anything you wrote "
            'about them has been left alone.',
          ),
        ),
      );
    }

    for (final offer in _offers(reading)) {
      understood.add(
        _line(
          t,
          Icons.shield_outlined,
          // Names the consequence, not the database state. Whether a row
          // exists in the profile is not what the user is deciding; whether
          // their plan works around the region is, and only the profile
          // drives that -- /regenerate reads injuries server-side and never
          // from this screen.
          '${injuryLabel(offer.option, offer.injury)} '
          'is not in your injuries. Add it and every plan from now on will '
          'work around it.',
          iconColor: t.red,
          action: FsButton(
            key: Key('gen.describe.add.${offer.option.injuryId}'),
            label: 'Add',
            small: true,
            wrapLabel: true,
            kind: FsButtonKind.secondary,
            busy: _adding == offer.option.injuryId,
            onPressed: () => _add(offer.injury),
          ),
        ),
      );
    }

    if (reading.mentionsGoal) {
      understood.add(
        _line(t, Icons.flag_outlined, 'Goals are set in your profile.'),
      );
    }

    // The example is for a sentence that said nothing the card knows, not
    // for one whose every part needs no line: a day count matching the
    // ticked days, or a region the profile already holds.
    final recognisedSilently =
        reading.daysPerWeek != null || reading.injuries.isNotEmpty;

    return [
      if (understood.isEmpty && !recognisedSilently)
        _line(
          t,
          Icons.info_outline,
          "Nothing to change yet. Try: 'ppl, 45 min, protect my knee'.",
          muted: true,
        )
      else
        ...understood,
      if (reading.source == WeekSource.ai)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            key: const Key('gen.describe.ai'),
            children: [
              ExcludeSemantics(
                child: Icon(Icons.auto_awesome, size: 14, color: t.text3),
              ),
              const SizedBox(width: 5),
              Text(
                'Read by AI',
                style: TextStyle(fontSize: 11, color: t.text3, height: 1.35),
              ),
            ],
          ),
        ),
      ?limit,
    ];
  }

  /// One understood line: a 16 px icon, kept out of the reading, the words,
  /// and the button that acts on them, if any.
  ///
  /// The button sits at the end of the line while both fit, and drops under
  /// the words when they do not: a long offer, or large text on a narrow
  /// phone, where a row would push the button off the card.
  Widget _line(
    FsTokens t,
    IconData icon,
    String text, {
    Color? iconColor,
    Widget? action,
    bool muted = false,
  }) {
    final words = Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: muted ? t.text3 : t.text2,
        height: 1.35,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 16, color: iconColor ?? t.text3),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: action == null
                ? words
                : Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [words, action],
                  ),
          ),
        ],
      ),
    );
  }
}
