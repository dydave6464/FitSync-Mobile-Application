import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../domain/nutrition.dart';
import 'providers.dart';

class AddFoodManuallyScreen extends ConsumerStatefulWidget {
  const AddFoodManuallyScreen({super.key, required this.mealType});

  final String mealType;

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
  late String _meal = widget.mealType;

  @override
  void dispose() {
    for (final c in [_name, _serving, _protein, _carbs, _fat, _fiber]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _grams(TextEditingController c) => c.text.trim().isEmpty ? 0 : double.tryParse(c.text.trim());

  /// Fiber is optional: blank is unknown (null), not 0. Anything else
  /// unreadable comes back as NaN, which fails the 0-500 range check below
  /// the same way an out-of-range number would.
  double? _fiberGrams(TextEditingController c) {
    final text = c.text.trim();
    return text.isEmpty ? null : (double.tryParse(text) ?? double.nan);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final p = _grams(_protein), c = _grams(_carbs), f = _grams(_fat);
    final fiber = _fiberGrams(_fiber);
    final gramsOk = [p, c, f].every((g) => g != null && g >= 0 && g <= 500) &&
        (fiber == null || (fiber >= 0 && fiber <= 500));
    final kcal = gramsOk ? manualKcal(p!, c!, f!) : null;
    final name = _name.text.trim();
    final valid = name.isNotEmpty && name.length <= 100 && _serving.text.trim().length <= 60
        && gramsOk && (p! + c! + f!) > 0;

    Widget gramsField(String label, Key key, TextEditingController ctrl) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.text2, fontSize: 12)),
          const SizedBox(height: 4),
          FsField(
            controller: ctrl,
            fieldKey: key,
            hint: 'g',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Add manually')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FsField(controller: _name, fieldKey: const Key('manual.name'), hint: 'Food name',
              textCapitalization: TextCapitalization.sentences, onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          FsSegmented(
            options: [for (final m in mealTypes) (value: m, label: mealLabel(m))],
            selected: _meal,
            onSelected: (m) => setState(() => _meal = m),
          ),
          const SizedBox(height: 12),
          FsField(controller: _serving, fieldKey: const Key('manual.serving'),
              hint: 'Serving size (optional), e.g. 1 cup', onChanged: (_) => setState(() {})),
          const SizedBox(height: 16),
          Text('Macros · per serving', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          // Two rows of two, not one row of four: four boxes in a row
          // overflow a narrow phone at large text.
          Row(children: [
            gramsField('Protein (g)', const Key('manual.protein'), _protein),
            const SizedBox(width: 10),
            gramsField('Carbs (g)', const Key('manual.carbs'), _carbs),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            gramsField('Fat (g)', const Key('manual.fat'), _fat),
            const SizedBox(width: 10),
            gramsField('Fiber (g)', const Key('manual.fiber'), _fiber),
          ]),
          if (!gramsOk)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Each value must be 0–500 g', style: TextStyle(color: t.red, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          Text('Calories', style: TextStyle(color: t.text2, fontSize: 12)),
          Text(kcal == null ? '—' : '$kcal kcal', style: theme.textTheme.titleLarge),
          Text('Worked out from protein, carbs and fat.', style: TextStyle(color: t.text3, fontSize: 12)),
          const SizedBox(height: 24),
          FsButton(
            key: const Key('manual.log'),
            label: 'Log',
            onPressed: !valid ? null : () async {
              final messenger = ScaffoldMessenger.of(context);
              final controller = ref.read(nutritionDayProvider.notifier);
              final food = Food(
                source: 'manual', name: name,
                servingDesc: _serving.text.trim().isEmpty ? null : _serving.text.trim(),
                kcal: kcal!, proteinG: p, carbsG: c, fatG: f, fiberG: fiber,
              );
              Navigator.of(context).pop(true);
              try {
                await controller.log(food, mealType: _meal, servings: 1);
              } catch (_) {
                messenger.showSnackBar(const SnackBar(content: Text("Couldn't save — try again.")));
              }
            },
          ),
        ],
      ),
    );
  }
}
