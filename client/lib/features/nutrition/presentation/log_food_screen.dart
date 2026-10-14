import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../domain/nutrition.dart';
import 'add_food_manually_screen.dart';
import 'providers.dart';
import 'widgets/fatsecret_attribution.dart';
import 'widgets/log_food_sheet.dart';

const foodSearchDebounce = Duration(milliseconds: 300);

/// The server refuses a longer q with INVALID_FOOD_QUERY.
const _maxQuery = 60;

class LogFoodScreen extends ConsumerStatefulWidget {
  const LogFoodScreen({super.key, required this.mealType});

  final String mealType;

  @override
  ConsumerState<LogFoodScreen> createState() => _LogFoodScreenState();
}

class _LogFoodScreenState extends ConsumerState<LogFoodScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _tab = 'all';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(foodSearchDebounce, () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  /// A suggested food was tapped: fill the box and search straight away.
  void _searchFor(String name) {
    _debounce?.cancel();
    _search.text = name;
    setState(() => _query = name);
  }

  /// True while a FatSecret food's details load, so a second tap is ignored.
  bool _loadingFood = false;

  Future<void> _choose(Food listed) async {
    if (_loadingFood) return;
    var food = listed;
    // FatSecret's search list describes a food by one serving and its detail
    // by another; the server logs the detail, so the sheet must show it too.
    if (listed.isFatsecret) {
      setState(() => _loadingFood = true);
      try {
        food = await ref.read(nutritionRepositoryProvider).fatsecretFood(listed.externalId!);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("Couldn't load this food. Try again.")));
        }
        return;
      } finally {
        if (mounted) setState(() => _loadingFood = false);
      }
      if (!mounted) return;
    }
    final choice = await showLogFoodSheet(context, food, mealType: widget.mealType);
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(nutritionDayProvider.notifier);
    Navigator.of(context).pop();
    try {
      // Edited numbers are saved as the user's own entry; the listed food
      // itself is never changed.
      await controller.log(choice.edited ?? food, mealType: choice.mealType, servings: choice.servings);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't save — try again.")));
    }
  }

  Future<void> _manual() async {
    final logged = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AddFoodManuallyScreen(mealType: widget.mealType),
    ));
    if (logged == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: Text('Log ${mealLabel(widget.mealType).toLowerCase()}')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: FsButton(
          key: const Key('food.manual'),
          label: 'Add manually',
          kind: FsButtonKind.secondary,
          onPressed: _manual,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: FsField(
              controller: _search,
              fieldKey: const Key('food.search'),
              hint: 'Search foods',
              icon: Icons.search,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              inputFormatters: [LengthLimitingTextInputFormatter(_maxQuery)],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FsSegmented(
              options: const [(value: 'all', label: 'All'), (value: 'recents', label: 'Recents')],
              selected: _tab,
              onSelected: (v) => setState(() => _tab = v),
            ),
          ),
          if (_loadingFood) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _tab == 'recents' ? _recents() : _results()),
        ],
      ),
    );
  }

  Widget _results() {
    if (_query.isEmpty) return _StartHint(onPick: _searchFor);
    // One letter: wait for the next, with nothing to read in the meantime.
    if (_query.length < 2) return const SizedBox.shrink();
    return ref.watch(foodSearchProvider(_query)).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Hint(describeError(e)),
      data: (r) => _FoodList(
        foods: r.foods,
        onTap: _choose,
        note: r.fatsecretUnavailable ? "Some foods couldn't load. Check your connection." : null,
        empty: 'No foods match "$_query". Try another word, or add it manually.',
      ),
    );
  }

  Widget _recents() => ref.watch(recentFoodsProvider).when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => _Hint(describeError(e)),
    data: (foods) => _FoodList(foods: foods, onTap: _choose, empty: 'Foods you log show up here.'),
  );
}

/// Shown before anything is typed: a prompt and a few foods to tap, rather
/// than rules about how much to type.
class _StartHint extends StatelessWidget {
  const _StartHint({required this.onPick});

  final ValueChanged<String> onPick;

  static const _suggestions = ['Rice', 'Chicken adobo', 'Egg', 'Tapsilog', 'Banana'];

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Text('What did you eat?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Search by name, like adobo or rice',
            textAlign: TextAlign.center, style: TextStyle(color: t.text2)),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in _suggestions) ActionChip(label: Text(name), onPressed: () => onPick(name)),
          ],
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.fs.text2)),
  );
}

class _FoodList extends StatelessWidget {
  const _FoodList({required this.foods, required this.onTap, required this.empty, this.note});

  final List<Food> foods;
  final ValueChanged<Food> onTap;
  final String empty;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    if (foods.isEmpty) return _Hint(note == null ? empty : '$note $empty');
    final anyFatsecret = foods.any((f) => f.isFatsecret);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(note!, style: TextStyle(color: t.text3, fontSize: 12)),
          ),
        for (final f in foods)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => onTap(f),
            title: Text(f.name),
            subtitle: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (f.servingDesc != null) Text(f.servingDesc!),
              ],
            ),
            trailing: Text('${f.kcal} kcal'),
          ),
        if (anyFatsecret) const FatsecretAttribution(),
      ],
    );
  }
}
