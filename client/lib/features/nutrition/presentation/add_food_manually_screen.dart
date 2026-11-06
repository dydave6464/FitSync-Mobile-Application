import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/nutrition.dart';
import 'error_snack_bar.dart';
import 'providers.dart';
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
    final valid = name.isNotEmpty && name.length <= 100 && _serving.text.trim().length <= 60
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
            FsField(controller: _name, fieldKey: const Key('manual.name'), hint: 'Food name',
                textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            if (!widget.pick) ...[
              FsSegmented(
                options: [for (final m in mealTypes) (value: m, label: mealLabel(m))],
                selected: _meal,
                onSelected: (m) => setState(() => _meal = m),
              ),
              const SizedBox(height: 12),
            ],
            FsField(controller: _serving, fieldKey: const Key('manual.serving'),
                hint: 'Serving size (optional), e.g. 1 cup', onChanged: (_) => setState(() {})),
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
                Navigator.of(context).pop(true);
                final FoodEntry saved;
                try {
                  saved = await controller.log(food, mealType: _meal, servings: 1, date: date);
                } catch (_) {
                  showErrorSnackBar(messenger, "Couldn't save — try again.");
                  return;
                }
                onLogged?.call(saved, date!);
              },
            ),
          ],
        ),
      ),
    );
  }
}
