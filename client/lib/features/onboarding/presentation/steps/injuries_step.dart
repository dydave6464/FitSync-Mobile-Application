import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
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
    final t = context.fs;
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
          'This is not a medical diagnosis. If something hurts, see a '
          'professional.',
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
        const SizedBox(height: 6),
        Text(
          'If nothing applies, just continue.',
          style: TextStyle(fontSize: 11, color: t.text3),
        ),
        const SizedBox(height: 18),
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
                FsButton(
                  label: 'Retry',
                  small: true,
                  kind: FsButtonKind.secondary,
                  onPressed: () => ref.invalidate(injuryOptionsProvider),
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
                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: FsEyebrow(
                    _groupLabels[section.group] ?? section.group,
                  ),
                ),
                for (final option in section.options) ...[
                  _RegionCard(
                    option: option,
                    selection: _selection(option.injuryId),
                    onToggle: () => _toggle(option),
                    onSide: (side) => _setSide(option.injuryId, side),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RegionCard extends StatelessWidget {
  const _RegionCard({
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
    final t = context.fs;
    final theme = Theme.of(context);
    final selected = selection != null;

    return FsCard(
      small: true,
      accent: selected,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: Key('injury.${option.injuryId}'),
            onTap: onToggle,
            child: Row(
              children: [
                Expanded(
                  child: Text(option.name, style: theme.textTheme.titleMedium),
                ),
                FsRadioDot(selected: selected),
              ],
            ),
          ),
          // Only a selected, lateral region gets a side. The server rejects a
          // side on anything else.
          if (selected && option.isLateral) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Side',
                  style: TextStyle(fontSize: 11, color: t.text3),
                ),
                const SizedBox(width: 10),
                for (final side in _sides) ...[
                  FsChip(
                    key: Key('side.${option.injuryId}.${side.value}'),
                    label: side.label,
                    small: true,
                    selected: selection!.side == side.value,
                    onTap: () => onSide(side.value),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
