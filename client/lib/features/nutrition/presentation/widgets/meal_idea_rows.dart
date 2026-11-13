import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/meal_suggestion.dart';
import '../../domain/nutrition.dart' show FoodEntry;
import '../error_snack_bar.dart';
import '../providers.dart';

/// Changes whenever what the rows show changes, and only then: the key the
/// cross-fade switches on.
String suggestionSignature(MealSuggestions data) => [
  data.state.name,
  data.share?.kcal,
  data.share?.proteinG,
  for (final s in data.suggestions) '${s.food.foodId}+${s.rice?.foodId}:${s.total.kcal}',
].join('|');

/// "Logged to lunch" with Undo, replacing whatever message is up. Undo
/// deletes the plate's entries as the meal list's ✕ would.
void showPlateLoggedSnackBar(
  ScaffoldMessengerState messenger,
  NutritionDayController controller,
  String meal,
  List<FoodEntry> logged, {
  required bool screenReader,
}) {
  // Replacing, not queueing behind, whatever message is up.
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 4),
    // An action keeps a SnackBar up by default; only a screen reader,
    // which takes longer than four seconds to reach Undo, keeps it here.
    persist: screenReader,
    content: Text('Logged to $meal'),
    action: SnackBarAction(label: 'Undo', onPressed: () => _undo(messenger, controller, logged)),
  ));
}

/// Undo deletes both entries, as the meal list's ✕ would.
Future<void> _undo(
  ScaffoldMessengerState messenger,
  NutritionDayController controller,
  List<FoodEntry> logged,
) async {
  try {
    for (final entry in logged) {
      await controller.remove(entry);
    }
  } catch (_) {
    showErrorSnackBar(messenger, "Couldn't undo. Remove the plate from the meal list.");
  }
}

/// One plate: the whole row is the button. One screen-reader node, its words
/// said once in the label; the + is decoration.
class PlateRow extends StatefulWidget {
  const PlateRow({
    super.key,
    required this.index,
    required this.plate,
    required this.meal,
    required this.onTap,
    this.focusNode,
  });

  final int index;
  final MealSuggestion plate;
  final String meal;
  final VoidCallback? onTap;

  /// The card's keyboard focus, for a page that moves focus onto this row;
  /// the row's own otherwise. Either way the row's one node reports it, so
  /// the row stays one screen-reader node and one Tab stop.
  final FocusNode? focusNode;

  @override
  State<PlateRow> createState() => _PlateRowState();
}

class _PlateRowState extends State<PlateRow> {
  FocusNode? _own;

  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'plate row'));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(PlateRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.focusNode ?? _own;
    if (was != _focus) {
      was?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _own?.dispose();
    super.dispose();
  }

  void _focusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final PlateRow(:index, :plate, :meal, :onTap) = widget;
    final meta = plateMeta(plate);
    final focusable = onTap != null;
    return Semantics(
      key: Key('suggest.row.$index'),
      container: true,
      button: true,
      enabled: onTap != null,
      label: plateSpoken(plate),
      hint: 'Log to $meal',
      onTap: onTap,
      // The card's InkWell holds the focus, but its Focus's node is excluded
      // below with the rest, so this one node reports it as Focus would.
      focusable: focusable,
      focused: focusable ? _focus.hasPrimaryFocus : null,
      onFocus: focusable && defaultTargetPlatform != TargetPlatform.iOS ? _focus.requestFocus : null,
      excludeSemantics: true,
      // Faded like a disabled FsButton while the tab loads a day; eased so
      // a quick reload does not flash, at once with reduced motion.
      child: AnimatedOpacity(
        opacity: onTap == null ? fsDisabledOpacity : 1,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 150),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: FsCard(
            small: true,
            onTap: onTap,
            focusNode: _focus,
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plateTitle(plate),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 12, color: t.text2),
                          children: [
                            TextSpan(text: '${meta.lead} · '),
                            // The Protein bar's green, and never without its
                            // number: colour is not the only cue.
                            TextSpan(
                              text: meta.protein,
                              style: TextStyle(color: t.accentText, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        key: Key('suggest.meta.$index'),
                      ),
                      if (plate.highProtein) ...[
                        const SizedBox(height: 6),
                        const FsTag('High protein'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.add, size: 18, color: t.text2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three row-shaped blocks where the rows will be, so nothing jumps and no
/// spinner flashes. Said once, as "Loading suggestions".
class SuggestionPlaceholders extends StatelessWidget {
  const SuggestionPlaceholders({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Semantics(
      key: const Key('suggest.loading'),
      container: true,
      label: 'Loading suggestions',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            SizedBox(height: i == 0 ? 10 : 8),
            Container(
              key: Key('suggest.placeholder.$i'),
              height: 64,
              decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(FsRadius.md)),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line with Retry; the rest of the screen carries on.
class SuggestionErrorLine extends StatelessWidget {
  const SuggestionErrorLine({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text("Couldn't load suggestions.", style: TextStyle(fontSize: 12.5, color: t.text2)),
          ),
        ),
        TextButton(key: const Key('suggest.retry'), onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
