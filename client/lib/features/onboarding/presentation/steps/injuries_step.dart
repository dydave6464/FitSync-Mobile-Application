import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../../profile/domain/profile.dart';
import '../../../profile/presentation/providers.dart';

/// Reading order for the region groups.
///
/// The server returns rows ordered by `region_group, name`, which is
/// alphabetical (back_core, lower_body, upper_body) and reads oddly on a body
/// diagram. This is display order only — which regions exist, which are
/// lateral, and which group each belongs to all still come from the response.
const _groupOrder = ['upper_body', 'back_core', 'lower_body'];

const _groupLabels = {
  'upper_body': 'Upper body',
  'back_core': 'Back and core',
  'lower_body': 'Lower body',
};

const _sides = <({String value, String label})>[
  (value: 'left', label: 'Left'),
  (value: 'right', label: 'Right'),
  (value: 'both', label: 'Both'),
];

/// Step 4: past or current injuries, and which side they are on.
///
/// Laterality is driven entirely by `isLateral` in the response. Hard-coding
/// which regions have sides would duplicate a fact the server already owns —
/// and the server is what returns a 400 when the two disagree.
class InjuriesStep extends ConsumerWidget {
  const InjuriesStep({super.key, required this.value, required this.onChanged});

  final List<SelectedInjury> value;
  final ValueChanged<List<SelectedInjury>> onChanged;

  SelectedInjury? _selection(int injuryId) {
    for (final injury in value) {
      if (injury.injuryId == injuryId) return injury;
    }
    return null;
  }

  void _toggle(InjuryOption option) {
    final next = [...value];
    final index = next.indexWhere((i) => i.injuryId == option.injuryId);
    if (index >= 0) {
      // Removing the region takes its side with it — leaving a stranded side
      // for an unselected region is how a stale value reaches the server.
      next.removeAt(index);
    } else {
      next.add(SelectedInjury(injuryId: option.injuryId));
    }
    onChanged(next);
  }

  void _setSide(int injuryId, String side) {
    onChanged([
      for (final injury in value)
        if (injury.injuryId == injuryId)
          injury.withSide(injury.side == side ? null : side)
        else
          injury,
    ]);
  }

  /// Groups in display order, with any group the server adds later appended
  /// rather than dropped — migration 007 defaults `region_group` to 'other',
  /// and a region the client has never heard of still has to be selectable.
  List<({String group, List<InjuryOption> options})> _grouped(
      List<InjuryOption> options) {
    final byGroup = <String, List<InjuryOption>>{};
    for (final option in options) {
      byGroup.putIfAbsent(option.regionGroup, () => []).add(option);
    }

    final ordered = [
      ..._groupOrder.where(byGroup.containsKey),
      ...byGroup.keys.where((g) => !_groupOrder.contains(g)),
    ];

    return [
      for (final group in ordered) (group: group, options: byGroup[group]!),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final injuries = ref.watch(injuryOptionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Any injuries?', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Tell us where you have had trouble, past or present. Your answers '
          'are recorded with your profile and passed to the plan generator. '
          'This is not a medical diagnosis — if something hurts, see a '
          'professional.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'If nothing applies, just continue.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        injuries.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text(describeError(error), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(injuryOptionsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (options) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final section in _grouped(options)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    _groupLabels[section.group] ?? section.group,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                for (final option in section.options)
                  _RegionTile(
                    option: option,
                    selection: _selection(option.injuryId),
                    onToggle: () => _toggle(option),
                    onSide: (side) => _setSide(option.injuryId, side),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RegionTile extends StatelessWidget {
  const _RegionTile({
    required this.option,
    required this.selection,
    required this.onToggle,
    required this.onSide,
  });

  final InjuryOption option;
  final SelectedInjury? selection;
  final VoidCallback onToggle;
  final ValueChanged<String> onSide;

  @override
  Widget build(BuildContext context) {
    final selected = selection != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            key: Key('injury.${option.injuryId}'),
            value: selected,
            title: Text(option.name),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (_) => onToggle(),
          ),
          // Only a selected, lateral region gets a side. The server rejects a
          // side on anything else.
          if (selected && option.isLateral)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  for (final side in _sides)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: Key('side.${option.injuryId}.${side.value}'),
                        label: Text(side.label),
                        selected: selection!.side == side.value,
                        onSelected: (_) => onSide(side.value),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
