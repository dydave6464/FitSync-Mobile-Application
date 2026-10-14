import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/nutrition.dart';
import 'fatsecret_attribution.dart';

class LogChoice {
  const LogChoice({required this.mealType, required this.servings});

  final String mealType;
  final double servings;
}

Future<LogChoice?> showLogFoodSheet(BuildContext context, Food food, {required String mealType}) =>
    showModalBottomSheet<LogChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LogFoodSheet(food: food, mealType: mealType),
    );

String _servingsLabel(double s) => s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toString();
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

  void _step(double by) => setState(() => _servings = (_servings + by).clamp(0.5, 20));

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final f = widget.food;
    final kcal = (f.kcal * _servings).round();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(f.name, style: theme.textTheme.titleMedium),
            if (f.servingDesc != null)
              Text('Per serving: ${f.servingDesc}', style: TextStyle(color: t.text2, fontSize: 13)),
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
                  child: Text(_servingsLabel(_servings), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                ),
                IconButton(key: const Key('servings.plus'), onPressed: () => _step(0.5), icon: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: 8),
            Text('$kcal kcal', style: theme.textTheme.titleLarge),
            Text(
              'Protein ${_g(f.proteinG * _servings)} g · Carbs ${_g(f.carbsG * _servings)} g · Fat ${_g(f.fatG * _servings)} g',
              style: TextStyle(color: t.text2, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FsButton(
              key: const Key('logSheet.log'),
              label: 'Log',
              onPressed: () => Navigator.of(context).pop(LogChoice(mealType: _meal, servings: _servings)),
            ),
            if (f.isFatsecret) const FatsecretAttribution(),
          ],
        ),
      ),
    );
  }
}
