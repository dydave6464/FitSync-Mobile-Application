import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/dates.dart';
import '../../../../core/manila_day.dart';
import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/body_weight.dart';
import '../providers.dart'
    show
        bodyWeightClockProvider,
        bodyWeightProvider,
        profileProvider,
        profileRepositoryProvider,
        weightUnitProvider;

/// Opens the list of the user's weigh-ins, where a mistaken one can be
/// deleted (PS-20). Reached from the body-weight card's "All weigh-ins".
Future<void> showWeighInsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // FsSheetHeader draws the handle (PT-22).
    showDragHandle: false,
    // A year of weigh-ins can be a long list; the sheet sets its own
    // ceiling (FsSheetHeightCap) rather than Material's 9/16.
    isScrollControlled: true,
    backgroundColor: context.fs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _WeighInsSheet(),
  );
}

/// The day a weigh-in is for, named: "Wed, Nov 4", with its year when it is
/// not this one. The confirm message reads "… on Wed, Nov 4", where "on
/// Today" would not.
String _namedDay(DateTime day, DateTime today) {
  final named = '${weekdayShort[day.weekday - 1]}, ${shortDate(day)}';
  return day.year == today.year ? named : '$named, ${day.year}';
}

class _WeighInsSheet extends ConsumerStatefulWidget {
  const _WeighInsSheet();

  @override
  ConsumerState<_WeighInsSheet> createState() => _WeighInsSheetState();
}

class _WeighInsSheetState extends ConsumerState<_WeighInsSheet> {
  /// The day being deleted; while set, every other delete waits.
  String? _deleting;

  /// Why the last delete failed, shown under the title.
  String? _error;

  DateTime _today() =>
      DateTime.parse(manilaDayOf(ref.read(bodyWeightClockProvider)()));

  /// Asks, then deletes [point]. [newest] is the list newest first, so the
  /// weight the profile goes back to can be named.
  Future<void> _delete(
    BodyWeightPoint point,
    List<BodyWeightPoint> newest,
    WeightUnit unit,
  ) async {
    if (_deleting != null) return;
    final today = _today();
    String named(BodyWeightPoint p) =>
        _namedDay(DateTime.parse(p.loggedOn), today);

    var message =
        '${formatWeightWithUnit(point.weightKg, unit)} on ${named(point)} '
        'comes off your chart.';
    if (point.loggedOn == newest.first.loggedOn && newest.length > 1) {
      final previous = newest[1];
      message +=
          ' Your weight goes back to '
          '${formatWeightWithUnit(previous.weightKg, unit)}, '
          'from ${named(previous)}.';
    }

    final confirmed = await confirmDestructive(
      context,
      keyPrefix: 'weighIn.delete',
      title: 'Delete this weigh-in?',
      message: message,
      cancel: 'Keep',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _deleting = point.loggedOn;
      _error = null;
    });
    // Captured before the await: the sheet closes on success, and its own
    // context goes with it.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    String done;
    try {
      await ref
          .read(profileRepositoryProvider)
          .deleteBodyWeight(point.loggedOn);
      done = 'Weigh-in deleted';
    } on ApiException catch (error) {
      if (error.code != 'WEIGH_IN_NOT_FOUND') {
        _failed(error);
        return;
      }
      done = 'That weigh-in was already deleted.';
    } catch (error) {
      debugPrint('Weigh-in delete failed: $error');
      _failed(error);
      return;
    }

    // The same pair the add sheet refreshes: every period's chart, and the
    // profile weight the server may have moved back to the previous entry.
    ref.invalidate(bodyWeightProvider);
    ref.invalidate(profileProvider);
    if (!mounted) return;
    // Closed first, so the snackbar is not drawn under the sheet, where it
    // would be neither seen nor read out.
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  }

  void _failed(Object error) {
    if (!mounted) return;
    setState(() {
      _deleting = null;
      _error = userMessage(error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final unit = ref.watch(weightUnitProvider);
    final series = ref.watch(bodyWeightProvider('year'));

    return FsSheetHeightCap(
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                FsSheetHeader.sideInset,
                10,
                FsSheetHeader.sideInset,
                4,
              ),
              child: FsSheetHeader(title: 'Your weigh-ins'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FsSheetHeader.sideInset,
                  4,
                  FsSheetHeader.sideInset,
                  8,
                ),
                child: FsErrorLine(_error!, key: const Key('weighIns.error')),
              ),
            Flexible(
              child: series.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(FsSheetHeader.sideInset),
                  child: FsRetry(
                    message: userMessage(e),
                    onRetry: () => ref.invalidate(bodyWeightProvider('year')),
                  ),
                ),
                data: (data) => _list(t, data, unit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(FsTokens t, BodyWeightSeries data, WeightUnit unit) {
    final newest = data.points.reversed.toList(growable: false);
    final hint = TextStyle(fontSize: 12, color: t.text2, height: 1.4);

    if (newest.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          FsSheetHeader.sideInset,
          8,
          FsSheetHeader.sideInset,
          16,
        ),
        child: Text('No weigh-ins yet.', style: hint),
      );
    }

    final only = newest.length == 1;
    final today = _today();
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < newest.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: FsSheetHeader.sideInset,
                endIndent: FsSheetHeader.sideInset,
                color: t.line,
              ),
            _row(t, newest[i], newest, unit, today, deletable: !only),
          ],
          if (only)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FsSheetHeader.sideInset,
                8,
                FsSheetHeader.sideInset,
                4,
              ),
              child: Text(
                'To fix your only weigh-in, log the right weight for that '
                'day. It replaces the old one.',
                key: const Key('weighIns.onlyHint'),
                style: hint,
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    FsTokens t,
    BodyWeightPoint point,
    List<BodyWeightPoint> newest,
    WeightUnit unit,
    DateTime today, {
    required bool deletable,
  }) {
    final day = calendarDayLabel(DateTime.parse(point.loggedOn), today);
    final busy = _deleting == point.loggedOn;
    return Padding(
      key: ValueKey('weighIns.row.${point.loggedOn}'),
      padding: const EdgeInsets.only(
        left: FsSheetHeader.sideInset,
        // The 48 dp button's own room is the gap at the end.
        right: FsSheetHeader.sideInset - 12,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatWeightWithUnit(point.weightKg, unit),
              style: TextStyle(fontSize: 13.5, color: t.text2),
            ),
            if (deletable)
              IconButton(
                key: Key('weighIns.delete.${point.loggedOn}'),
                tooltip: 'Delete weigh-in for $day',
                color: t.text2,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: _deleting != null
                    ? null
                    : () => _delete(point, newest, unit),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, size: 20),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
