import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/client_id.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/meal_suggestion.dart';
import '../../domain/nutrition.dart';
import '../../../profile/presentation/providers.dart' show profileProvider;
import '../providers.dart';

/// Both entries saved. [whileOpen]: the sheet was still open when the save
/// ended, so it is closing now; false when it was dragged away first.
typedef OnPlateLogged = void Function(List<FoodEntry> logged, {required bool whileOpen});

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
  SuggestedFood? riceFood,
  required double usualRiceCups,
  required OnPlateLogged onLogged,
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
      riceFood: riceFood,
      usualRiceCups: usualRiceCups,
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
    this.riceFood,
    required this.usualRiceCups,
    required this.onLogged,
    required this.onFailedAfterClose,
  });

  final MealSuggestion plate;
  final String meal;
  final String date;

  /// White rice, one cup: what the rice choice scales. Null: no choice.
  final SuggestedFood? riceFood;

  /// The user's usual cups, for "from now on".
  final double usualRiceCups;

  /// Both entries saved, whether or not the sheet is still open.
  final OnPlateLogged onLogged;

  /// The save failed after the sheet was dragged away, so it cannot show
  /// the message itself.
  final ValueChanged<String> onFailedAfterClose;

  @override
  ConsumerState<LogPlateSheet> createState() => _LogPlateSheetState();
}

class _LogPlateSheetState extends ConsumerState<LogPlateSheet> {
  // Made once: Retry sends the same ones, so an item that did save the first
  // time comes back rather than being saved twice.
  final String _dishId = newClientId();
  final String _riceId = newClientId();

  /// The cups chosen; starts at the plate's own (None when it came without).
  late double _cups = widget.plate.rice == null ? 0 : widget.plate.riceCups;

  /// Log plate was tapped once: the plate is fixed from then on, so Retry
  /// sends the same one.
  bool _attempted = false;

  bool get _offersRice => widget.plate.servedWithRice && widget.riceFood != null;

  /// The plate as it stands with the rice chosen.
  MealSuggestion get _plate => _offersRice ? withRiceCups(widget.plate, widget.riceFood!, _cups) : widget.plate;
  bool _busy = false;
  String? _failure;

  Future<void> _log() async {
    setState(() {
      _busy = true;
      _attempted = true;
      _failure = null;
    });
    final controller = ref.read(nutritionDayProvider.notifier);
    // Kept before the first await: the sheet may be gone when it ends.
    final onLogged = widget.onLogged;
    final onFailedAfterClose = widget.onFailedAfterClose;
    // Whether the sheet is still open is its route's to say, not `mounted`:
    // after a drag the sheet stays mounted for its exit animation while its
    // route is already popping.
    final route = ModalRoute.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final plate = _plate;
    final items = <(Food, double, String)>[
      (plate.food.toFood(), 1, _dishId),
      if (_offersRice && _cups > 0)
        (widget.riceFood!.toFood(), _cups, _riceId)
      else if (!_offersRice && plate.rice != null)
        (plate.rice!.toFood(), plate.riceCups, _riceId),
    ];
    final logged = <FoodEntry>[];
    try {
      for (final (food, servings, clientId) in items) {
        logged.add(await controller.log(
          food,
          mealType: widget.meal,
          servings: servings,
          date: widget.date,
          clientId: clientId,
        ));
      }
    } catch (error) {
      final message = "Couldn't log the plate. ${userMessage(error)}";
      if (!(route?.isActive ?? false)) {
        onFailedAfterClose(message);
        return;
      }
      setState(() {
        _busy = false;
        _failure = message;
      });
      return;
    }
    final open = route?.isCurrent ?? false;
    onLogged(logged, whileOpen: open);
    if (_offersRice && _cups != widget.usualRiceCups) unawaited(_remember(container, _cups));
    // Only the sheet's own route, while it is still on top: a pop once it
    // is closing would take the screen under it. (A current route's sheet
    // is always mounted; the check is for the analyzer.)
    if (mounted && open) Navigator.of(context).pop();
  }

  /// Makes [cups] the usual rice. Not awaited, and a failure is only logged:
  /// the plate is logged, and Settings > Rice with meals shows the amount
  /// kept (spec 2026-11-13, 1.3). The patch itself refetches the suggestions.
  static Future<void> _remember(ProviderContainer container, double cups) async {
    try {
      await container.read(profileProvider.notifier).patch({'usualRiceCups': cups});
    } catch (error) {
      debugPrint('Remembering $cups cups of rice failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final plate = _plate;
    return PopScope(
      // While saving, the ×, the barrier and Back do nothing. A drag still
      // closes the sheet (it pops the route directly, past PopScope); the
      // save carries on and its outcome still reaches the caller, and _log
      // asks the route, not `mounted`, whether the sheet is still open.
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
              if (_offersRice) ...[
                Text('Rice', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
                const SizedBox(height: 8),
                // Wraps at large text rather than shrinking a label.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final cups in riceChoices)
                      FsChip(
                        key: Key('logPlate.rice.$cups'),
                        label: cups == 0 ? 'None' : cupsLabel(cups),
                        selected: _cups == cups,
                        exclusive: true,
                        onTap: _attempted ? null : () => setState(() => _cups = cups),
                      ),
                  ],
                ),
                if (_cups != widget.usualRiceCups) ...[
                  const SizedBox(height: 6),
                  Text(riceNote(_cups), key: const Key('logPlate.rice.note'), style: TextStyle(fontSize: 12, color: t.text2)),
                ],
                const SizedBox(height: 8),
              ],
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
