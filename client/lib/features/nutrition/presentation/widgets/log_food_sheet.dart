import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  /// listed, and three boxes on every log would be noise.
  bool _editing = false;
  late final _protein = TextEditingController(text: _plain(widget.food.proteinG));
  late final _carbs = TextEditingController(text: _plain(widget.food.carbsG));
  late final _fat = TextEditingController(text: _plain(widget.food.fatG));

  @override
  void dispose() {
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  void _step(double by) => setState(() => _servings = (_servings + by).clamp(0.5, 20));

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final f = widget.food;

    final p = _grams(_protein), c = _grams(_carbs), fat = _grams(_fat);
    final gramsOk = [p, c, fat].every((g) => g != null && g >= 0 && g <= 500);
    // Only a real change makes this the user's own entry; opening the boxes
    // and logging untouched still logs the listed food.
    final changed = _editing && gramsOk && (p != f.proteinG || c != f.carbsG || fat != f.fatG);
    final canLog = !_editing || (gramsOk && p! + c! + fat! > 0);
    final perKcal = changed ? manualKcal(p!, c!, fat!) : f.kcal;
    final shown = changed ? (p: p!, c: c!, f: fat!) : (p: f.proteinG, c: f.carbsG, f: f.fatG);

    Widget gramsField(String label, String key, TextEditingController controller) => Expanded(
      child: Column(
        key: Key(key),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.text2, fontSize: 12)),
          const SizedBox(height: 4),
          FsField(
            controller: controller,
            hint: 'g',
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
              'Protein ${_g(shown.p * _servings)} g · Carbs ${_g(shown.c * _servings)} g · Fat ${_g(shown.f * _servings)} g',
              style: TextStyle(color: t.text2, fontSize: 13),
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
              Row(children: [
                gramsField('Protein (g)', 'logSheet.protein', _protein),
                const SizedBox(width: 10),
                gramsField('Carbs (g)', 'logSheet.carbs', _carbs),
                const SizedBox(width: 10),
                gramsField('Fat (g)', 'logSheet.fat', _fat),
              ]),
              if (!gramsOk)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Each value must be 0–500 g', style: TextStyle(color: t.red, fontSize: 12)),
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
                                name: f.name,
                                servingDesc: f.servingDesc,
                                kcal: perKcal,
                                proteinG: p!,
                                carbsG: c!,
                                fatG: fat!,
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

/// 4.3 -> "4.3", 28.0 -> "28": a number as someone would type it.
String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// An empty box counts as 0; anything unreadable as null (invalid).
double? _grams(TextEditingController c) => c.text.trim().isEmpty ? 0 : double.tryParse(c.text.trim());
