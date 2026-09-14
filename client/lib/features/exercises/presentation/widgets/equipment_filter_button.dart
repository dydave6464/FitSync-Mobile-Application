import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/exercise_filters.dart';
import '../equipment_icon.dart';
import '../providers.dart';

/// The catalogue's equipment filter, as a labelled button rather than chips.
///
/// It replaced a horizontal strip that held every muscle group AND every
/// equipment tag in one scroller, equipment last. Reaching "dumbbell" meant
/// scrolling past a dozen muscle groups first, and nothing on screen said the
/// tags at the far end were a different kind of filter from the ones at the
/// near end. A user looking for dumbbell exercises could not find the control
/// that does it.
///
/// A button says what it filters even when nothing is chosen, and says what is
/// in force when something is. The tags themselves move into a sheet, which is
/// where a list this long belongs: the catalogue carries roughly two dozen raw
/// equipment tags, well past what a strip can show at once.
class EquipmentFilterButton extends ConsumerWidget {
  const EquipmentFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fs;
    final filters = ref.watch(exerciseFiltersProvider);
    final selected = ref.watch(selectedFiltersProvider).equipment;

    // Secondary furniture, same as the strip it replaces: if the tags cannot
    // load, the list below is still perfectly usable unfiltered. Rendering a
    // button that opens an empty sheet would be worse than rendering nothing.
    final options = filters.value?.equipment;
    if (options == null || options.isEmpty) return const SizedBox(height: 8);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: ActionChip(
          key: const Key('library.equipment'),
          avatar: Icon(
            selected == null ? Icons.tune : equipmentIcon(selected),
            size: 16,
            color: selected == null ? t.text2 : t.onAccent,
          ),
          label: Text(selected ?? 'Equipment'),
          labelStyle: TextStyle(
            fontSize: 13,
            color: selected == null ? t.text2 : t.onAccent,
          ),
          backgroundColor: selected == null ? t.surface : t.accent,
          side: BorderSide(color: selected == null ? t.line : Colors.transparent),
          onPressed: () => _open(context, ref, options),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    List<FilterOption> options,
  ) async {
    final chosen = await showModalBottomSheet<_Choice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EquipmentSheet(
        options: options,
        selected: ref.read(selectedFiltersProvider).equipment,
      ),
    );
    // Null means dismissed, which is not the same as "Any equipment": backing
    // out of the sheet must leave the filter exactly as it was found.
    if (chosen == null) return;
    ref.read(selectedFiltersProvider.notifier).setEquipment(chosen.value);
  }
}

/// What the sheet hands back. A bare `String?` could not tell "cleared" from
/// "dismissed", since both are null.
class _Choice {
  const _Choice(this.value);
  final String? value;
}

class _EquipmentSheet extends StatefulWidget {
  const _EquipmentSheet({required this.options, required this.selected});

  final List<FilterOption> options;
  final String? selected;

  @override
  State<_EquipmentSheet> createState() => _EquipmentSheetState();
}

class _EquipmentSheetState extends State<_EquipmentSheet> {
  final _controller = TextEditingController();

  /// Typed into the box, lowercased once rather than per row.
  String _term = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Filtered in memory, not through the API: the whole tag list is already
  /// here, so there is nothing to fetch and no debounce to wait out.
  List<FilterOption> get _visible => widget.options
      .where((o) => o.value.toLowerCase().contains(_term))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final visible = _visible;

    return SafeArea(
      child: Padding(
        // Lifts the sheet clear of the keyboard the search box raises.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Equipment',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: FsField(
                fieldKey: const Key('equipment.search'),
                controller: _controller,
                hint: 'Find equipment',
                icon: Icons.search,
                onChanged: (value) =>
                    setState(() => _term = value.trim().toLowerCase()),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  // Above the tags and never filtered out by the search box:
                  // it is how the filter comes off, so it must stay reachable
                  // no matter what has been typed.
                  _OptionRow(
                    key: const Key('equipment.option.any'),
                    icon: Icons.all_inclusive,
                    label: 'Any equipment',
                    selected: widget.selected == null,
                    onTap: () => Navigator.of(context).pop(const _Choice(null)),
                  ),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Text(
                        'No equipment matches that.',
                        style: TextStyle(fontSize: 13, color: t.text3),
                      ),
                    ),
                  for (final option in visible)
                    _OptionRow(
                      key: Key('equipment.option.${option.value}'),
                      icon: equipmentIcon(option.value),
                      label: option.value,
                      count: option.count,
                      selected: widget.selected == option.value,
                      onTap: () =>
                          Navigator.of(context).pop(_Choice(option.value)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// How many exercises carry this tag, or null for "Any equipment", whose
  /// count is just the catalogue size and tells the user nothing.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 20, color: selected ? t.accent : t.text2),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: selected ? t.accent : t.text,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count != null)
            Text(
              '$count',
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check, size: 18, color: t.accent),
          ],
        ],
      ),
    );
  }
}
