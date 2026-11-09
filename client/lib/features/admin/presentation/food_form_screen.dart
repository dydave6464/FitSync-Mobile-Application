import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../nutrition/domain/nutrition.dart'
    show manualKcal, mealLabel, mealTypes;
import '../../nutrition/presentation/widgets/number_box.dart';
import '../../nutrition/presentation/widgets/text_limits.dart';
import '../../onboarding/presentation/edit_scaffold.dart';
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';
import 'providers.dart';

/// Adds one of FitSync's own foods ([food] null) or edits one. Calories
/// follow the typed-food rule: typed from a label they are kept; left empty
/// the server works them out from protein, carbs and fat. Editing changes
/// future logs only; meals already logged keep their own numbers.
///
/// Editing also hides the food from trainees, or shows it again.
class FoodFormScreen extends ConsumerStatefulWidget {
  const FoodFormScreen({super.key, this.food});

  final AdminFood? food;

  @override
  ConsumerState<FoodFormScreen> createState() => _FoodFormScreenState();
}

/// The number boxes: the form's key for each, and the server's field name.
const _numbers = [
  ('kcal', 'kcal'),
  ('protein', 'proteinG'),
  ('carbs', 'carbsG'),
  ('fat', 'fatG'),
  ('fiber', 'fiberG'),
  ('sugar', 'sugarG'),
  ('sodium', 'sodiumMg'),
];

/// "28", "870.5": a stored number as it is typed.
String _typed(double? value) {
  if (value == null) return '';
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

class _FoodFormScreenState extends ConsumerState<FoodFormScreen> {
  late final _name = TextEditingController(text: widget.food?.name ?? '');
  late final _serving = TextEditingController(
    text: widget.food?.servingDesc ?? '',
  );
  late final Map<String, TextEditingController> _boxes = {
    for (final (key, _) in _numbers) key: TextEditingController(),
  };
  String? _category;
  String? _type;

  /// What the form opened with, to tell an edit from an untouched form.
  late final String _opened;

  /// What the server said about one field on the last Save, by the
  /// server's field name; cleared as that field changes.
  final _fieldErrors = <String, String>{};
  String? _error;
  bool _saving = false;

  /// Hidden from trainees: the food's own flag, then whatever the last
  /// Hide or Show answered.
  late bool _hidden = widget.food?.hidden ?? false;
  bool _toggling = false;

  /// The meals it is suggested for as a local meal (the prototype's "Add
  /// local meal"), and whether with 1 cup of rice.
  late final Set<String> _suggest = {...?widget.food?.suggestMeals};
  late bool _withRice = widget.food?.suggestWithRice ?? false;

  /// Rice is offered beside a main meal only: a snack never comes with it.
  bool get _mainMealChosen => _suggest.any((meal) => meal != 'snack');

  /// The chosen meals in meal order, as the server keeps them.
  List<String> get _suggestMeals => [
    for (final meal in mealTypes)
      if (_suggest.contains(meal)) meal,
  ];

  bool get _editing => widget.food != null;

  @override
  void initState() {
    super.initState();
    final food = widget.food;
    if (food != null) {
      _category = food.category;
      _type = foodTypeLabels.containsKey(food.foodType) ? food.foodType : null;
      _boxes['protein']!.text = _typed(food.proteinG);
      _boxes['carbs']!.text = _typed(food.carbsG);
      _boxes['fat']!.text = _typed(food.fatG);
      _boxes['fiber']!.text = _typed(food.fiberG);
      _boxes['sugar']!.text = _typed(food.sugarG);
      _boxes['sodium']!.text = _typed(food.sodiumMg);
      // Calories the server worked out stay out of the box, so a change to
      // protein, carbs or fat works them out again; a label's are kept.
      final worked = manualKcal(food.proteinG, food.carbsG, food.fatG);
      if (food.kcal != worked) _boxes['kcal']!.text = '${food.kcal}';
    }
    _opened = _snapshot();
  }

  @override
  void dispose() {
    _name.dispose();
    _serving.dispose();
    for (final box in _boxes.values) {
      box.dispose();
    }
    super.dispose();
  }

  String _snapshot() => [
    _name.text.trim(),
    _serving.text.trim(),
    _category,
    _type,
    for (final (key, _) in _numbers) _boxes[key]!.text.trim(),
    _suggestMeals.join(','),
    '${_withRice && _mainMealChosen}',
  ].join('\u0000');

  /// Blank is null; anything unreadable is NaN, which fails every check.
  double? _number(String key) {
    final text = _boxes[key]!.text.trim();
    return text.isEmpty ? null : (double.tryParse(text) ?? double.nan);
  }

  void _changed(String serverField) => setState(() {
    _fieldErrors.remove(serverField);
    _error = null;
  });

  /// Why Save is off, or null when the form can be sent.
  String? _missing() {
    if (_name.text.trim().isEmpty) return 'Add a name';
    if (_category == null) return 'Choose Filipino or International';
    if (_type == null) return 'Choose a type';
    if (_serving.text.trim().isEmpty) return 'Add a serving';
    final macros = [_number('protein'), _number('carbs'), _number('fat')];
    if (macros.any((g) => g == null)) return 'Add protein, carbs and fat';
    return null;
  }

  /// Whether every number is in range; out-of-range ones say so under
  /// their own box.
  bool _numbersOk() {
    bool grams(String key) {
      final g = _number(key);
      return g == null || inGramsRange(g);
    }

    final kcal = _number('kcal');
    final sodium = _number('sodium');
    return ['protein', 'carbs', 'fat', 'fiber', 'sugar'].every(grams) &&
        (kcal == null || inKcalRange(kcal)) &&
        (sodium == null || inSodiumRange(sodium));
  }

  /// Something to count: protein, carbs or fat, or the label's calories
  /// (a drink label may give only those). The server's rule.
  bool _hasAmount() {
    final total =
        (_number('protein') ?? 0) +
        (_number('carbs') ?? 0) +
        (_number('fat') ?? 0);
    return total > 0 || (_number('kcal') ?? 0) > 0;
  }

  FoodInput _input() => FoodInput(
    name: _name.text.trim(),
    category: _category!,
    foodType: _type!,
    servingDesc: _serving.text.trim(),
    kcal: _number('kcal')?.round(),
    proteinG: _number('protein')!,
    carbsG: _number('carbs')!,
    fatG: _number('fat')!,
    fiberG: _number('fiber'),
    sugarG: _number('sugar'),
    sodiumMg: _number('sodium'),
    suggestMeals: _suggestMeals,
    suggestWithRice: _withRice && _mainMealChosen,
  );

  Future<void> _save() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final repo = ref.read(adminRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors.clear();
    });
    try {
      final food = widget.food;
      if (food == null) {
        await repo.createFood(_input());
      } else {
        await repo.updateFood(food.id, _input());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _placeError(error);
      });
      return;
    }
    container.invalidate(adminFoodsProvider);
    // Back stays open while saving, so the admin may have left already, or a
    // dialog may sit on top. Not `mounted`: during back's exit transition the
    // form is still mounted but no longer current, and pop() would close the
    // route under it. Still "saving" as it pops, so the discard guard lets
    // it go.
    if (route != null && route.isCurrent) navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(_editing ? 'Food saved.' : 'Food added.')),
    );
  }

  /// A refusal about one field goes under it; anything else above Save.
  void _placeError(Object error) {
    final message = userMessage(error);
    if (error is ApiException) {
      if (error.code == 'FOOD_NAME_TAKEN') {
        _fieldErrors['name'] = message;
        return;
      }
      for (final detail in error.details) {
        final field = detail['field'];
        if (field is String && _fieldsShown.contains(field)) {
          _fieldErrors[field] = message;
          return;
        }
      }
    }
    _error = message;
  }

  static const _fieldsShown = {
    'name',
    'category',
    'foodType',
    'servingDesc',
    'kcal',
    'proteinG',
    'carbsG',
    'fatG',
    'fiberG',
    'sugarG',
    'sodiumMg',
    'suggestMeals',
    'suggestWithRice',
  };

  Future<void> _hide(AdminFood food) async {
    final confirmed = await confirmDestructive(
      context,
      keyPrefix: 'admin.hideFood',
      title: 'Hide ${food.name}?',
      message:
          'It leaves food search, Recents and Snap a meal. Meals already '
          'logged keep it.',
      action: 'Hide',
      cancel: 'Keep',
    );
    if (!confirmed || !mounted) return;
    await _toggle(
      () => ref.read(adminRepositoryProvider).hideFood(food.id),
      done: 'Food hidden.',
    );
  }

  Future<void> _show(AdminFood food) => _toggle(
    () => ref.read(adminRepositoryProvider).showFood(food.id),
    done: 'Food shown.',
  );

  Future<void> _toggle(
    Future<AdminFood> Function() call, {
    required String done,
  }) async {
    if (_toggling) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _toggling = true);
    AdminFood? changed;
    String message;
    try {
      changed = await call();
      message = done;
    } catch (error) {
      message = userMessage(error);
    }
    container.invalidate(adminFoodsProvider);
    if (!mounted) return;
    setState(() {
      _toggling = false;
      if (changed != null) _hidden = changed.hidden;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final missing = _missing();
    final numbersOk = _numbersOk();
    final nothingToCount = missing == null && numbersOk && !_hasAmount();
    final valid = missing == null && numbersOk && !nothingToCount;
    final food = widget.food;

    Widget number(
      String key,
      String serverField,
      String label, {
      bool whole = false,
      String hint = 'g',
    }) {
      final text = _boxes[key]!.text;
      final rangeError = switch (key) {
        'kcal' => kcalError(text),
        'sodium' => sodiumError(text),
        _ => gramsError(text),
      };
      return KeyedSubtree(
        key: Key('admin.food.$key.box'),
        child: NumberBox(
          label: label,
          controller: _boxes[key]!,
          fieldKey: Key('admin.food.$key'),
          hint: hint,
          wholeNumbers: whole,
          error: _fieldErrors[serverField] ?? rangeError,
          onChanged: (_) => _changed(serverField),
        ),
      );
    }

    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ],
    );

    Widget? fieldError(String serverField) {
      final message = _fieldErrors[serverField];
      return message == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FsErrorLine(message),
            );
    }

    return EditScaffold(
      title: _editing ? 'Edit food' : 'Add food',
      dirty: _snapshot() != _opened,
      busy: _saving,
      error: _error,
      hint:
          missing ??
          (nothingToCount ? 'Add calories, protein, carbs or fat' : null),
      // Not while Hide or Show runs: one change to the food at a time.
      onSave: valid && !_toggling ? _save : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            key: const Key('admin.food.name.box'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FsField(
                  controller: _name,
                  fieldKey: const Key('admin.food.name'),
                  label: 'Name',
                  hint: 'e.g. Chicken adobo',
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: const [Utf16LengthLimit(maxFoodName)],
                  errorText: _fieldErrors['name'],
                  onChanged: (_) => _changed('name'),
                ),
                ?fieldError('name'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Semantics(header: true, child: const FsEyebrow('Cuisine')),
          const SizedBox(height: 6),
          FsSegmented(
            options: const [
              (value: 'filipino', label: 'Filipino'),
              (value: 'international', label: 'International'),
            ],
            selected: _category,
            onSelected: (value) => setState(() {
              _category = value;
              _fieldErrors.remove('category');
              _error = null;
            }),
          ),
          ?fieldError('category'),
          const SizedBox(height: 16),
          Semantics(header: true, child: const FsEyebrow('Type')),
          const SizedBox(height: 6),
          FsTapRoom(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MapEntry(key: value, value: label)
                    in foodTypeLabels.entries)
                  FsChip(
                    key: Key('admin.food.type.$value'),
                    label: label,
                    exclusive: true,
                    selected: _type == value,
                    onTap: () => setState(() {
                      _type = value;
                      _fieldErrors.remove('foodType');
                      _error = null;
                    }),
                  ),
              ],
            ),
          ),
          ?fieldError('foodType'),
          const SizedBox(height: 16),
          KeyedSubtree(
            key: const Key('admin.food.serving.box'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FsField(
                  controller: _serving,
                  fieldKey: const Key('admin.food.serving'),
                  label: 'Serving',
                  hint: 'e.g. 1 cup',
                  inputFormatters: const [Utf16LengthLimit(maxServingDesc)],
                  errorText: _fieldErrors['servingDesc'],
                  onChanged: (_) => _changed('servingDesc'),
                ),
                ?fieldError('servingDesc'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          number(
            'kcal',
            'kcal',
            'Calories (kcal) · optional',
            whole: true,
            hint: 'kcal',
          ),
          const SizedBox(height: 6),
          Text(
            'Leave empty to work it out from protein, carbs and fat.',
            style: TextStyle(fontSize: 12, height: 1.4, color: t.text3),
          ),
          const SizedBox(height: 16),
          // Two to a row, not four: four boxes overflow a narrow phone at
          // large text (the Add manually form's rule).
          pair(
            number('protein', 'proteinG', 'Protein (g)'),
            number('carbs', 'carbsG', 'Carbs (g)'),
          ),
          const SizedBox(height: 10),
          pair(
            number('fat', 'fatG', 'Fat (g)'),
            number('fiber', 'fiberG', 'Fiber (g) · optional'),
          ),
          const SizedBox(height: 10),
          pair(
            number('sugar', 'sugarG', 'Sugar (g) · optional'),
            number('sodium', 'sodiumMg', 'Sodium (mg) · optional', hint: 'mg'),
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: const FsEyebrow('Suggest as a local meal'),
          ),
          const SizedBox(height: 6),
          FsTapRoom(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final meal in mealTypes)
                  FsChip(
                    key: Key('admin.food.suggest.$meal'),
                    label: mealLabel(meal),
                    showCheck: true,
                    selected: _suggest.contains(meal),
                    onTap: () => setState(() {
                      if (!_suggest.remove(meal)) _suggest.add(meal);
                      _fieldErrors.remove('suggestMeals');
                      _error = null;
                    }),
                  ),
              ],
            ),
          ),
          ?fieldError('suggestMeals'),
          if (_mainMealChosen)
            SwitchListTile(
              key: const Key('admin.food.suggest.rice'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Served with 1 cup rice',
                style: TextStyle(fontSize: 13.5, color: t.text),
              ),
              value: _withRice,
              onChanged: (on) => setState(() {
                _withRice = on;
                _fieldErrors.remove('suggestWithRice');
                _error = null;
              }),
            ),
          ?fieldError('suggestWithRice'),
          if (food != null) ...[
            const SizedBox(height: 24),
            if (_hidden)
              FsButton(
                key: const Key('admin.food.show'),
                label: 'Show food',
                kind: FsButtonKind.secondary,
                busy: _toggling,
                onPressed: _saving ? null : () => _show(food),
              )
            else
              FsButton(
                key: const Key('admin.food.hide'),
                label: 'Hide food',
                kind: FsButtonKind.ghost,
                danger: true,
                busy: _toggling,
                onPressed: _saving ? null : () => _hide(food),
              ),
          ],
        ],
      ),
    );
  }
}
