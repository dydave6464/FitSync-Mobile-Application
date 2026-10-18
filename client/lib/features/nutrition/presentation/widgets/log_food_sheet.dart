import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/numbers.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/nutrition.dart';
import 'fatsecret_attribution.dart';

class LogChoice {
  const LogChoice({required this.mealType, required this.servings, this.edited});

  final String mealType;
  final double servings;

  /// The user's own numbers for this food, per serving, when they changed
  /// them under "Edit numbers"; null when they logged the food as listed.
  final Food? edited;
}

Future<LogChoice?> showLogFoodSheet(BuildContext context, Food food, {required String mealType}) =>
    showModalBottomSheet<LogChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LogFoodSheet(food: food, mealType: mealType),
    );

String _g(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class LogFoodSheet extends StatefulWidget {
  const LogFoodSheet({super.key, required this.food, required this.mealType});

  final Food food;
  final String mealType;

  @override
  State<LogFoodSheet> createState() => _LogFoodSheetState();
}

class _LogFoodSheetState extends State<LogFoodSheet> {
  late String _meal = widget.mealType;
  double _servings = 1;

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

  void _step(double by) => setState(() => _servings = (_servings + by).clamp(0.5, 20));

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
    final noMacros = changed && p! + c! + fat! == 0;
    final canLog = !touched || (changed && !noMacros);
    // Any change, fiber/sugar/sodium alone included, is logged as the user's
    // own entry, and the server works out a manual entry's kcal as 4·4·9 --
    // so the preview does too. None of the three ever adds calories.
    final perKcal = changed ? manualKcal(p!, c!, fat!) : f.kcal;
    final shown = changed
        ? (p: p!, c: c!, f: fat!, fb: fiber, sg: sugar, na: sodium)
        : (p: f.proteinG, c: f.carbsG, f: f.fatG, fb: f.fiberG, sg: f.sugarG, na: f.sodiumMg);

    Widget gramsField(String label, String key, TextEditingController controller, {String hint = 'g'}) => Expanded(
      child: Column(
        key: Key(key),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.text2, fontSize: 12)),
          const SizedBox(height: 4),
          FsField(
            controller: controller,
            hint: hint,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (_) => setState(() {}),
          ),
        ],
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
            FsSegmented(
              options: [for (final m in mealTypes) (value: m, label: mealLabel(m))],
              selected: _meal,
              onSelected: (m) => setState(() => _meal = m),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Servings', style: TextStyle(color: t.text2))),
                IconButton(key: const Key('servings.minus'), onPressed: () => _step(-0.5), icon: const Icon(Icons.remove)),
                SizedBox(
                  width: 48,
                  child: Text(formatServings(_servings), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                ),
                IconButton(key: const Key('servings.plus'), onPressed: () => _step(0.5), icon: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${(perKcal * _servings).round()} kcal', style: theme.textTheme.titleLarge),
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
            if (changed)
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
              Row(children: [
                gramsField('Protein (g)', 'logSheet.protein', _protein),
                const SizedBox(width: 10),
                gramsField('Carbs (g)', 'logSheet.carbs', _carbs),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                gramsField('Fat (g)', 'logSheet.fat', _fat),
                const SizedBox(width: 10),
                gramsField('Fiber (g)', 'logSheet.fiber', _fiber),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                gramsField('Sugar (g)', 'logSheet.sugar', _sugar),
                const SizedBox(width: 10),
                gramsField('Sodium (mg)', 'logSheet.sodium', _sodium, hint: 'mg'),
              ]),
              if (touched && !gramsOk)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Each value must be 0–500 g', style: TextStyle(color: t.red, fontSize: 12)),
                )
              else if (touched && !sodiumOk)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Sodium must be 0–20,000 mg', style: TextStyle(color: t.red, fontSize: 12)),
                )
              else if (noMacros)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Add some protein, carbs or fat', style: TextStyle(color: t.red, fontSize: 12)),
                ),
            ],
            const SizedBox(height: 16),
            FsButton(
              key: const Key('logSheet.log'),
              label: 'Log',
              onPressed: !canLog
                  ? null
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
