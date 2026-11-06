import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/nutrition.dart';
import 'error_snack_bar.dart';
import 'providers.dart';
import 'widgets/meal_chips.dart';
import 'widgets/number_box.dart';

class AddFoodManuallyScreen extends ConsumerStatefulWidget {
  const AddFoodManuallyScreen({super.key, required this.mealType, this.onLogged, this.pick = false});

  final String mealType;

  /// Called once the food is saved, with the day it went to.
  final void Function(FoodEntry entry, String date)? onLogged;

  /// Choosing for Snap a meal: the typed food (per serving) is popped back,
  /// not logged, and the meal is left to the confirm screen.
  final bool pick;

  @override
  ConsumerState<AddFoodManuallyScreen> createState() => _AddFoodManuallyScreenState();
}

class _AddFoodManuallyScreenState extends ConsumerState<AddFoodManuallyScreen> {
  final _name = TextEditingController();
  final _serving = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _fiber = TextEditingController();
  final _sugar = TextEditingController();
  final _sodium = TextEditingController();
  late String _meal = widget.mealType;

  @override
  void dispose() {
    for (final c in [_name, _serving, _protein, _carbs, _fat, _fiber, _sugar, _sodium]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _grams(TextEditingController c) => c.text.trim().isEmpty ? 0 : double.tryParse(c.text.trim());

  /// Blank is unknown (null); anything else unreadable is NaN, which fails
  /// every range check.
  double? _optionalNumber(TextEditingController c) {
    final text = c.text.trim();
    return text.isEmpty ? null : (double.tryParse(text) ?? double.nan);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final p = _grams(_protein), c = _grams(_carbs), f = _grams(_fat);
    final fiber = _optionalNumber(_fiber);
    final sugar = _optionalNumber(_sugar), sodium = _optionalNumber(_sodium);
    final gramsOk = [p, c, f].every((g) => g != null && g >= 0 && g <= 500) &&
        [fiber, sugar].every((g) => g == null || (g >= 0 && g <= 500));
    final sodiumOk = sodium == null || (sodium >= 0 && sodium <= 20000);
    final kcal = gramsOk ? manualKcal(p!, c!, f!) : null;
    final name = _name.text.trim();
    final valid = name.isNotEmpty && name.length <= _maxName && _serving.text.trim().length <= _maxServing
        && gramsOk && sodiumOk && (p! + c! + f!) > 0;

    Widget gramsField(String label, Key key, TextEditingController ctrl, {bool sodium = false}) => Expanded(
      child: NumberBox(
        label: label,
        controller: ctrl,
        fieldKey: key,
        hint: sodium ? 'mg' : 'g',
        error: sodium ? sodiumError(ctrl.text) : gramsError(ctrl.text),
        onChanged: (_) => setState(() {}),
      ),
    );
    // Log is off with no protein, carbs or fat: say so once the user has
    // started, rather than leave the button grey without a reason.
    final noMacros = gramsOk && sodiumOk && p! + c! + f! == 0 &&
        (name.isNotEmpty || [_protein, _carbs, _fat].any((c) => c.text.trim().isNotEmpty));

    // Back with anything typed asks first; an untouched form just leaves.
    final typed = [_name, _serving, _protein, _carbs, _fat, _fiber, _sugar, _sodium]
        .any((c) => c.text.trim().isNotEmpty);

    return FsDiscardGuard(
      dirty: typed,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(title: const Text('Add manually')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Labelled as the prototype draws them: a placeholder alone goes
            // as soon as something is typed, taking the field's name with it.
            FsField(
              controller: _name,
              fieldKey: const Key('manual.name'),
              label: 'Food name',
              hint: 'e.g. Grilled bangus',
              textCapitalization: TextCapitalization.sentences,
              // The most the server accepts, so Log never greys out unexplained.
              inputFormatters: [LengthLimitingTextInputFormatter(_maxName)],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (!widget.pick) ...[
              const FsEyebrow('Meal'),
              const SizedBox(height: 6),
              MealChips(keyPrefix: 'manual.meal', selected: _meal, onSelected: (m) => setState(() => _meal = m)),
              const SizedBox(height: 16),
            ],
            FsField(
              controller: _serving,
              fieldKey: const Key('manual.serving'),
              label: 'Serving size · optional',
              hint: 'e.g. 1 cup',
              inputFormatters: [LengthLimitingTextInputFormatter(_maxServing)],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('Macros · per serving', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            // Two rows of two, not one row of four: four boxes in a row
            // overflow a narrow phone at large text.
            // Tops aligned, so an error under one box never shifts its pair.
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              gramsField('Protein (g)', const Key('manual.protein'), _protein),
              const SizedBox(width: 10),
              gramsField('Carbs (g)', const Key('manual.carbs'), _carbs),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              gramsField('Fat (g)', const Key('manual.fat'), _fat),
              const SizedBox(width: 10),
              gramsField('Fiber (g)', const Key('manual.fiber'), _fiber),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              gramsField('Sugar (g)', const Key('manual.sugar'), _sugar),
              const SizedBox(width: 10),
              gramsField('Sodium (mg)', const Key('manual.sodium'), _sodium, sodium: true),
            ]),
            if (noMacros) ...[
              const SizedBox(height: 8),
              const FsErrorLine('Add some protein, carbs or fat'),
            ],
            const SizedBox(height: 16),
            Text('Calories', style: TextStyle(color: t.text2, fontSize: 12)),
            Text(kcal == null ? '—' : '$kcal kcal', style: theme.textTheme.titleLarge),
            Text('Worked out from protein, carbs and fat.', style: TextStyle(color: t.text3, fontSize: 12)),
            const SizedBox(height: 24),
            FsButton(
              key: const Key('manual.log'),
              label: widget.pick ? 'Use this food' : 'Log',
              onPressed: !valid ? null : () async {
                final food = Food(
                  source: 'manual', name: name,
                  servingDesc: _serving.text.trim().isEmpty ? null : _serving.text.trim(),
                  kcal: kcal!, proteinG: p, carbsG: c, fatG: f, fiberG: fiber,
                  sugarG: sugar, sodiumMg: sodium,
                );
                if (widget.pick) {
                  Navigator.of(context).pop(food);
                  return;
                }
                final messenger = ScaffoldMessenger.of(context);
                final controller = ref.read(nutritionDayProvider.notifier);
                final date = ref.read(nutritionDayProvider).value?.date;
                final onLogged = widget.onLogged;
                final meal = _meal;
                final persist = MediaQuery.accessibleNavigationOf(context);
                Navigator.of(context).pop(true);
                // The form is gone, but the food is kept: Try again sends it
                // again rather than asking for it to be typed twice.
                await saveOrOfferRetry(
                  messenger,
                  save: () => controller.log(food, mealType: meal, servings: 1, date: date),
                  failure: "Couldn't save ${food.name}.",
                  persist: persist,
                  onSaved: (saved) => onLogged?.call(saved, date!),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The longest name and serving a manual entry may have
/// (server/src/routes/nutrition.js).
const _maxName = 100;
const _maxServing = 60;
