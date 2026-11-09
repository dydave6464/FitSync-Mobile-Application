import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/client_id.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/meal_suggestion.dart';
import '../../domain/nutrition.dart';
import '../providers.dart';

/// Opens "Log to Lunch" for [plate] on [date] (the suggestions' own day, the
/// server's today). The sheet tells the caller how the save ended rather
/// than the route's pop value, because a drag can close the sheet while it
/// saves and the save still finishes: [onLogged] gets the entries logged --
/// the dish, then its rice -- and [onFailedAfterClose] a message for a
/// failure the closed sheet can no longer show. Closed without logging,
/// neither is called.
Future<void> showLogPlateSheet(
  BuildContext context, {
  required MealSuggestion plate,
  required String meal,
  required String date,
  required ValueChanged<List<FoodEntry>> onLogged,
  required ValueChanged<String> onFailedAfterClose,
}) => showModalBottomSheet<void>(
  context: context,
  // FsSheetHeader draws the handle.
  showDragHandle: false,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FsSheetHeightCap(
    child: LogPlateSheet(
      plate: plate,
      meal: meal,
      date: date,
      onLogged: onLogged,
      onFailedAfterClose: onFailedAfterClose,
    ),
  ),
);

/// 26.0 -> "26", 6.3 -> "6.3": an item's own figures, as Log food shows them.
String _g(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// One line per item with its kcal, protein, carbs and fat, the plate's
/// total, and Log plate. Logging is two normal entries through the day's
/// controller, each with its own client id, made once: Retry sends the same
/// ones, so an item that did save the first time comes back rather than
/// being saved twice.
class LogPlateSheet extends ConsumerStatefulWidget {
  const LogPlateSheet({
    super.key,
    required this.plate,
    required this.meal,
    required this.date,
    required this.onLogged,
    required this.onFailedAfterClose,
  });

  final MealSuggestion plate;
  final String meal;
  final String date;

  /// Both entries saved, whether or not the sheet is still open.
  final ValueChanged<List<FoodEntry>> onLogged;

  /// The save failed after the sheet was dragged away, so it cannot show
  /// the message itself.
  final ValueChanged<String> onFailedAfterClose;

  @override
  ConsumerState<LogPlateSheet> createState() => _LogPlateSheetState();
}

class _LogPlateSheetState extends ConsumerState<LogPlateSheet> {
  late final List<String> _clientIds = [for (final _ in widget.plate.items) newClientId()];
  bool _busy = false;
  String? _failure;

  Future<void> _log() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final controller = ref.read(nutritionDayProvider.notifier);
    // Kept before the first await: the sheet may be gone when it ends.
    final onLogged = widget.onLogged;
    final onFailedAfterClose = widget.onFailedAfterClose;
    final logged = <FoodEntry>[];
    try {
      for (final (i, item) in widget.plate.items.indexed) {
        logged.add(await controller.log(
          item.toFood(),
          mealType: widget.meal,
          servings: 1,
          date: widget.date,
          clientId: _clientIds[i],
        ));
      }
    } catch (error) {
      final message = "Couldn't log the plate. ${userMessage(error)}";
      if (!mounted) {
        onFailedAfterClose(message);
        return;
      }
      setState(() {
        _busy = false;
        _failure = message;
      });
      return;
    }
    onLogged(logged);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final plate = widget.plate;
    return PopScope(
      // While saving, the ×, the barrier and Back do nothing. A drag still
      // closes the sheet (it pops the route directly, past PopScope); the
      // save carries on and its outcome still reaches the caller.
      canPop: !_busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            FsSheetHeader.sideInset,
            10,
            FsSheetHeader.sideInset,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FsSheetHeader(title: 'Log to ${mealLabel(widget.meal)}'),
              const SizedBox(height: 8),
              for (final item in plate.items)
                _ItemLine(
                  key: Key('logPlate.item.${item.foodId}'),
                  name: item.name,
                  serving: item.servingDesc ?? '1 serving',
                  kcal: item.kcal,
                  macros: 'Protein ${_g(item.proteinG)} g · Carbs ${_g(item.carbsG)} g · Fat ${_g(item.fatG)} g',
                ),
              Divider(height: 1, thickness: 1, color: t.line),
              _ItemLine(
                key: const Key('logPlate.total'),
                name: 'Plate total',
                kcal: plate.total.kcal,
                // Whole grams, so the protein is the row's own figure.
                macros: 'Protein ${plateProteinG(plate)} g · Carbs ${plate.total.carbsG.round()} g · '
                    'Fat ${plate.total.fatG.round()} g',
                strong: true,
              ),
              if (_failure != null) ...[
                const SizedBox(height: 8),
                FsErrorLine(_failure!),
              ],
              const SizedBox(height: 16),
              FsButton(
                key: const Key('logPlate.log'),
                label: _failure == null ? 'Log plate' : 'Retry',
                busy: _busy,
                onPressed: _busy ? null : _log,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One item, or the plate total: its name and kcal, then its serving (an
/// item only), then protein, carbs and fat. Read as one line by a screen reader.
class _ItemLine extends StatelessWidget {
  const _ItemLine({
    super.key,
    required this.name,
    this.serving,
    required this.kcal,
    required this.macros,
    this.strong = false,
  });

  final String name;
  final String? serving;
  final int kcal;

  /// "Protein 26 g · Carbs 8 g · Fat 14 g".
  final String macros;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final heading = TextStyle(fontSize: 14, fontWeight: strong ? FontWeight.w700 : FontWeight.w600, color: t.text);
    final detail = TextStyle(fontSize: 12, color: t.text2);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(name, style: heading)),
                const SizedBox(width: 8),
                Text('$kcal kcal', style: heading),
              ],
            ),
            if (serving != null) Text(serving!, style: detail),
            Text(macros, style: detail),
          ],
        ),
      ),
    );
  }
}
