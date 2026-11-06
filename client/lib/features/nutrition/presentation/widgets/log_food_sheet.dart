import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/numbers.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/nutrition.dart';
import 'fatsecret_attribution.dart';
import 'meal_chips.dart';
import 'number_box.dart';

class LogChoice {
  const LogChoice({required this.mealType, required this.servings, this.edited});

  final String mealType;
  final double servings;

  /// The user's own numbers for this food, per serving, when they changed
  /// them under "Edit numbers"; null when they logged the food as listed.
  final Food? edited;
}

/// With [changing], the sheet edits a logged food: it opens on the entry's
/// meal and [servings], its button says "Save changes", and saving with
/// nothing changed returns null, as closing does.
Future<LogChoice?> showLogFoodSheet(BuildContext context, Food food,
        {required String mealType, double servings = 1, bool changing = false}) =>
    showModalBottomSheet<LogChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LogFoodSheet(food: food, mealType: mealType, servings: servings, changing: changing),
    );

String _g(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class LogFoodSheet extends StatefulWidget {
  const LogFoodSheet({super.key, required this.food, required this.mealType, this.servings = 1, this.changing = false});

  final Food food;
  final String mealType;
  final double servings;

  /// Editing a logged food rather than logging a new one.
  final bool changing;

  @override
  State<LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends State<LogFoodSheet> {
  late String _meal = widget.mealType;
  late double _servings = widget.servings;

  /// "Edit numbers" is hidden until asked for: most people log a food as
  /// listed, and four boxes on every log would be noise.
  bool _editing = false;
  late final _protein = TextEditingController(text: _plain(widget.food.proteinG));
  late final _carbs = TextEditingController(text: _plain(widget.food.carbsG));
  late final _fat = TextEditingController(text: _plain(widget.food.fatG));
  late final _fiber = TextEditingController(text: widget.food.fiberG == null ? '' : _plain(widget.food.fiberG!));
  late final _sugar = TextEditingController(text: widget.food.sugarG == null ? '' : _plain(widget.food.sugarG!));
  late final _sodium = TextEditingController(text: widget.food.sodiumMg == null ? '' : _plain(widget.food.sodiumMg!));

  @override
  void dispose() {
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    _fiber.dispose();
    _sugar.dispose();
    _sodium.dispose();
    super.dispose();
  }

  /// One step of the servings stepper, read out as servings and what they
  /// come to. An announcement rather than a live region: the kcal also
  /// follows the numbers typed under "Edit numbers", and a live region would
  /// speak again on every keystroke there.
  void _step(double by, int perKcal) {
    setState(() => _servings = (_servings + by).clamp(_minServings, _maxServings));
    SemanticsService.sendAnnouncement(View.of(context), _amountLabel(perKcal), Directionality.of(context));
  }

  String _amountLabel(int perKcal) =>
      '${formatServings(_servings)} ${_servings == 1 ? 'serving' : 'servings'} · ${(perKcal * _servings).round()} kcal';

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final f = widget.food;

    final p = _grams(_protein), c = _grams(_carbs), fat = _grams(_fat);
    final fiber = _optionalNumber(_fiber);
    final sugar = _optionalNumber(_sugar), sodium = _optionalNumber(_sodium);
    final gramsOk = [p, c, fat].every((g) => g != null && g >= 0 && g <= 500) &&
        [fiber, sugar].every((g) => g == null || (g >= 0 && g <= 500));
    final sodiumOk = sodium == null || (sodium >= 0 && sodium <= 20000);
    // Only a real change makes this the user's own entry; opening the boxes
    // and logging untouched still logs the listed food, whatever its numbers
    // (a 0-macro drink, or a listed value over 500 g). Unreadable text (null,
    // or NaN for an optional field) differs from any listed value, so it
    // counts as one.
    final touched = _editing &&
        (p != f.proteinG || c != f.carbsG || fat != f.fatG || fiber != f.fiberG ||
            sugar != f.sugarG || sodium != f.sodiumMg);
    final changed = touched && gramsOk && sodiumOk;
    // Any change, fiber/sugar/sodium alone included, is logged as the user's
    // own entry. The server keeps the listed kcal -- which may count what
    // 4·4·9 can't, like a beer's alcohol -- while protein, carbs and fat are
    // as listed and it has something to compare with: the logged entry on an
    // edit or from Recents, or the FitSync food by its id. Otherwise it works
    // out 4·4·9, so the preview does too. Fiber, sugar and sodium never add
    // calories.
    final hasBasis = widget.changing || f.id != null || f.entryId != null;
    final macrosChanged = changed &&
        (!hasBasis || !sameGrams(p!, f.proteinG) || !sameGrams(c!, f.carbsG) || !sameGrams(fat!, f.fatG));
    // 0/0/0 is fine only when the kept kcal says the food has calories (a spirit).
    final noMacros = changed && p! + c! + fat! == 0 && (macrosChanged || f.kcal <= 0);
    final canLog = !touched || (changed && !noMacros);
    final perKcal = macrosChanged ? manualKcal(p!, c!, fat!) : f.kcal;
    final shown = changed
        ? (p: p!, c: c!, f: fat!, fb: fiber, sg: sugar, na: sodium)
        : (p: f.proteinG, c: f.carbsG, f: f.fatG, fb: f.fiberG, sg: f.sugarG, na: f.sodiumMg);

    // Errors only once something changed: a listed value the user left
    // alone never blocks Log, so it is never marked wrong either.
    Widget gramsField(String label, String key, TextEditingController controller, {bool sodium = false}) => Expanded(
      child: NumberBox(
        key: Key(key),
        label: label,
        controller: controller,
        hint: sodium ? 'mg' : 'g',
        error: !touched ? null : (sodium ? sodiumError(controller.text) : gramsError(controller.text)),
        onChanged: (_) => setState(() {}),
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(f.name, style: theme.textTheme.titleMedium),
            Text('Per ${f.servingDesc ?? 'serving'}${f.source == 'manual' ? ' · your entry' : ''}',
                style: TextStyle(color: t.text2, fontSize: 13)),
            const SizedBox(height: 16),
            MealChips(keyPrefix: 'logSheet.meal', selected: _meal, onSelected: (m) => setState(() => _meal = m)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Servings', style: TextStyle(color: t.text2))),
                IconButton(
                  key: const Key('servings.minus'),
                  tooltip: 'Fewer servings',
                  onPressed: _servings > _minServings ? () => _step(-0.5, perKcal) : null,
                  icon: const Icon(Icons.remove),
                ),
                // At least 48 dp, and the figure shrinks rather than breaking
                // "1.5" over two lines at large text. The live region below
                // speaks it, so it is not a second, bare node.
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48),
                  child: ExcludeSemantics(
                    child: Center(
                      widthFactor: 1,
                      child: FsOneLine(formatServings(_servings), style: theme.textTheme.titleMedium!),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('servings.plus'),
                  tooltip: 'More servings',
                  onPressed: _servings < _maxServings ? () => _step(0.5, perKcal) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // How many servings and what they come to, never a bare number;
            // _step reads the same words out after every step.
            Semantics(
              key: const Key('logSheet.amount'),
              container: true,
              label: _amountLabel(perKcal),
              excludeSemantics: true,
              child: Text('${(perKcal * _servings).round()} kcal', style: theme.textTheme.titleLarge),
            ),
            Text(
              'Protein ${_g(shown.p * _servings)} g · Carbs ${_g(shown.c * _servings)} g · Fat ${_g(shown.f * _servings)} g'
              '${shown.fb == null ? '' : ' · Fiber ${_g(shown.fb! * _servings)} g'}',
              style: TextStyle(color: t.text2, fontSize: 13),
            ),
            if (shown.sg != null || shown.na != null)
              Text(
                [
                  if (shown.sg != null) 'Sugar ${_g(shown.sg! * _servings)} g',
                  if (shown.na != null) 'Sodium ${groupThousands(shown.na! * _servings)} mg',
                ].join(' · '),
                key: const Key('logSheet.extras'),
                // text2, not text3: this line carries data (not a caption),
                // so it needs to clear AA contrast. Staying smaller than the
                // 13 sp macro line above is what keeps it visually quieter.
                style: TextStyle(color: t.text2, fontSize: 12),
              ),
            if (macrosChanged)
              Text('Calories worked out from protein, carbs and fat.',
                  style: TextStyle(color: t.text3, fontSize: 12)),
            if (!_editing)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('logSheet.edit'),
                  onPressed: () => setState(() => _editing = true),
                  child: const Text('Edit numbers'),
                ),
              )
            else ...[
              const SizedBox(height: 12),
              Text('Your numbers, per serving', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              // Two rows of two, not one row of four: four boxes in a row
              // overflow a narrow phone at large text.
              // Tops aligned, so an error under one box never shifts its pair.
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                gramsField('Protein (g)', 'logSheet.protein', _protein),
                const SizedBox(width: 10),
                gramsField('Carbs (g)', 'logSheet.carbs', _carbs),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                gramsField('Fat (g)', 'logSheet.fat', _fat),
                const SizedBox(width: 10),
                gramsField('Fiber (g)', 'logSheet.fiber', _fiber),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                gramsField('Sugar (g)', 'logSheet.sugar', _sugar),
                const SizedBox(width: 10),
                gramsField('Sodium (mg)', 'logSheet.sodium', _sodium, sodium: true),
              ]),
              if (noMacros) ...[
                const SizedBox(height: 8),
                const FsErrorLine('Add some protein, carbs or fat'),
              ],
            ],
            const SizedBox(height: 16),
            FsButton(
              key: const Key('logSheet.log'),
              label: widget.changing ? 'Save changes' : 'Log',
              onPressed: !canLog
                  ? null
                  // Nothing to save: close as if dismissed, so no request goes.
                  : widget.changing && !changed && _meal == widget.mealType && _servings == widget.servings
                  ? () => Navigator.of(context).pop()
                  : () => Navigator.of(context).pop(LogChoice(
                        mealType: _meal,
                        servings: _servings,
                        edited: changed
                            ? Food(
                                source: 'manual',
                                // A FatSecret name or serving can be longer
                                // than a manual entry may be.
                                name: _clip(f.name, _maxName),
                                servingDesc: f.servingDesc == null ? null : _clip(f.servingDesc!, _maxServingDesc),
                                kcal: perKcal,
                                proteinG: p!,
                                carbsG: c!,
                                fatG: fat!,
                                fiberG: fiber,
                                sugarG: sugar,
                                sodiumMg: sodium,
                                basedOnFoodId: f.id,
                                entryId: f.entryId,
                              )
                            : null,
                      )),
            ),
            if (f.isFatsecret) const FatsecretAttribution(),
          ],
        ),
      ),
    );
  }
}

/// The fewest and most servings the sheet steps between.
const _minServings = 0.5;
const _maxServings = 20.0;

/// The longest name and serving a manual entry may have
/// (server/src/routes/nutrition.js).
const _maxName = 100;
const _maxServingDesc = 60;

/// [text], trimmed and cut to at most [max] UTF-16 units -- what the server's
/// length check counts -- without splitting a character, then trimmed again.
String _clip(String text, int max) {
  final trimmed = text.trim();
  if (trimmed.length <= max) return trimmed;
  final out = StringBuffer();
  for (final ch in trimmed.characters) {
    if (out.length + ch.length > max) break;
    out.write(ch);
  }
  return out.toString().trimRight();
}

/// 4.3 -> "4.3", 28.0 -> "28": a number as someone would type it.
String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// An empty box counts as 0; anything unreadable as null (invalid).
double? _grams(TextEditingController c) => c.text.trim().isEmpty ? 0 : double.tryParse(c.text.trim());

/// Blank is unknown (null); anything else unreadable is NaN, which fails
/// every range check.
double? _optionalNumber(TextEditingController c) {
  final text = c.text.trim();
  return text.isEmpty ? null : (double.tryParse(text) ?? double.nan);
}
