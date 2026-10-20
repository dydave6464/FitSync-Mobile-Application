import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../domain/nutrition.dart';
import 'add_food_manually_screen.dart';
import 'error_snack_bar.dart';
import 'providers.dart';
import 'widgets/fatsecret_attribution.dart';
import 'widgets/log_food_sheet.dart';

const foodSearchDebounce = Duration(milliseconds: 300);

/// The server refuses a longer q with INVALID_FOOD_QUERY.
const _maxQuery = 60;

class LogFoodScreen extends ConsumerStatefulWidget {
  const LogFoodScreen({super.key, required this.mealType, this.onLogged});

  final String mealType;

  /// Called once a food logged from here (or from Add manually) is saved,
  /// with the day it went to, after this screen has closed.
  final void Function(FoodEntry entry, String date)? onLogged;

  @override
  ConsumerState<LogFoodScreen> createState() => _LogFoodScreenState();
}

class _LogFoodScreenState extends ConsumerState<LogFoodScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _tab = 'all';

  /// The meal the food goes into: the one whose Add row or + was tapped,
  /// shown at the top and changeable before anything is searched. It used
  /// to be fixed in the title and changeable only in the last step.
  late String _meal = widget.mealType;

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
        if (mounted) showErrorSnackBar(ScaffoldMessenger.of(context), "Couldn't load this food. Try again.");
        return;
      } finally {
        if (mounted) setState(() => _loadingFood = false);
      }
      if (!mounted) return;
    }
    final choice = await showLogFoodSheet(context, food, mealType: _meal);
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(nutritionDayProvider.notifier);
    final date = ref.read(nutritionDayProvider).value?.date;
    final onLogged = widget.onLogged;
    Navigator.of(context).pop();
    final FoodEntry saved;
    try {
      // Edited numbers are saved as the user's own entry; the listed food
      // itself is never changed.
      saved = await controller.log(choice.edited ?? food, mealType: choice.mealType, servings: choice.servings, date: date);
    } catch (_) {
      showErrorSnackBar(messenger, "Couldn't save — try again.");
      return;
    }
    onLogged?.call(saved, date!);
  }

  Future<void> _manual() async {
    final logged = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => AddFoodManuallyScreen(mealType: _meal, onLogged: widget.onLogged),
    ));
    if (logged == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(title: const Text('Log food')),
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
          // Where the food goes, on one labelled line: four meal pills here
          // looked just like the All / Recents filter below, and on a small
          // phone at large text they wrapped to 82 dp and pushed the foods
          // off the screen. Changing it is rare -- it arrives pre-picked. A
          // Wrap, so at very large text the pill drops under its label
          // rather than cutting "Breakfast" short; heard as one button.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: MergeSemantics(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  children: [
                    const FsEyebrow('Adding to'),
                    _MealPicker(meal: _meal, onPicked: (m) => setState(() => _meal = m)),
                  ],
                ),
              ),
            ),
          ),
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
          // The bar's 2 px are kept when idle, so the list never jumps.
          if (_loadingFood) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
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
        // The phone reached the server, so its connection isn't the problem.
        note: r.fatsecretUnavailable ? "Some foods couldn't load right now. Try again later." : null,
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

/// The meal the food goes into, as one pill that opens the four meals.
///
/// The pill is its own Material, so the ink and the focus colour fill it
/// inside its rounded edge rather than drawing a square behind it. The
/// whole 48 dp row around it opens the meals -- by the pill's rounded ends
/// too, where moving a tap onto the pill's edge would land outside its
/// shape -- while only a tap on the pill draws a press.
class _MealPicker extends StatelessWidget {
  const _MealPicker({required this.meal, required this.onPicked});

  final String meal;
  final ValueChanged<String> onPicked;

  Future<void> _open(BuildContext row) async {
    final box = row.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(row).overlay!.context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final picked = await showMenu<String>(
      context: row,
      position: position,
      initialValue: meal,
      items: [
        for (final m in mealTypes)
          CheckedPopupMenuItem<String>(
            key: Key('log.meal.$m'),
            value: m,
            checked: m == meal,
            child: Text(mealLabel(m)),
          ),
      ],
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return Builder(
      builder: (row) => GestureDetector(
        key: const Key('log.meal'),
        behavior: HitTestBehavior.opaque,
        // The pill's InkWell is what a screen reader presses.
        excludeFromSemantics: true,
        onTap: () => _open(row),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Semantics(
              button: true,
              child: Tooltip(
                message: 'Change meal',
                child: Material(
                  color: t.surface,
                  shape: StadiumBorder(side: BorderSide(color: t.line2)),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => _open(row),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Never cut: the line wraps the pill under its
                          // label first.
                          Flexible(
                            child: Text(
                              mealLabel(meal),
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.text),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.expand_more, size: 20, color: t.text2),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
      // 8 of the 24 at the foot moves into the list itself, as room under
      // the last row of suggestions for a thumb to land in.
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        Text('What did you eat?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Search by name, like adobo or rice',
            textAlign: TextAlign.center, style: TextStyle(color: t.text2)),
        // Half the 16 above the suggestions sits in their own padding, so a
        // thumb landing just over the first row still finds a chip.
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FsTapRoom(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in _suggestions) FsChip(label: name, selected: false, onTap: () => onPick(name)),
              ],
            ),
          ),
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
