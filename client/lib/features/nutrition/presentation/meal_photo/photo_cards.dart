import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/meal_photo.dart';
import '../../domain/nutrition.dart';

/// One food the photo will log: its name and ✕, the AI's other guesses and
/// Search, and the portion in half servings.
class PhotoItemCard extends StatelessWidget {
  const PhotoItemCard({
    super.key,
    required this.card,
    required this.onSwap,
    required this.onSearch,
    required this.onServings,
    required this.onRemove,
  });

  final DraftCard card;
  final ValueChanged<Food> onSwap;
  final VoidCallback onSearch;
  final ValueChanged<double> onServings;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    final food = card.food!;
    final servings = card.servings;
    final kcal = (food.kcal * servings).round();

    return FsCard(
      key: Key('snap.item.${card.id}'),
      small: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(food.name, style: theme.textTheme.titleMedium),
                ),
              ),
              IconButton(
                key: Key('snap.remove.${card.id}'),
                tooltip: 'Remove ${food.name}',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            card.alternatives.isEmpty ? 'Not right?' : 'Not right? Pick another:',
            style: TextStyle(color: t.text2, fontSize: 12),
          ),
          const SizedBox(height: 8),
          // Chips wrap rather than clip at large text. Each chip sits in a
          // 48 dp tall box, so its tap band is 48 dp on every row -- the
          // band reaches only as far as its parent's box.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, alt) in card.alternatives.indexed)
                Semantics(
                  key: Key('snap.alt.${card.id}.$i'),
                  label: 'Swap to ${alt.name}',
                  button: true,
                  excludeSemantics: true,
                  // excludeSemantics drops the chip's own tap action, so
                  // the node carries it.
                  onTap: () => onSwap(alt),
                  child: _ChipRoom(child: FsChip(label: alt.name, selected: false, onTap: () => onSwap(alt))),
                ),
              Semantics(
                key: Key('snap.search.${card.id}'),
                label: 'Search for another food',
                button: true,
                excludeSemantics: true,
                onTap: onSearch,
                child: _ChipRoom(child: FsChip(label: 'Search', selected: false, onTap: onSearch)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Portion', style: TextStyle(color: t.text2)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('snap.minus.${card.id}'),
                    tooltip: 'Less ${food.name}',
                    onPressed: servings > minPhotoServings ? () => onServings(servings - 0.5) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  // At least 48 dp; the figure shrinks rather than breaking
                  // "1.5" over two lines at large text.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 48),
                    child: ExcludeSemantics(
                      child: Center(
                        widthFactor: 1,
                        child: FsOneLine(formatServings(servings), style: theme.textTheme.titleMedium!),
                      ),
                    ),
                  ),
                  IconButton(
                    key: Key('snap.plus.${card.id}'),
                    tooltip: 'More ${food.name}',
                    onPressed: servings < maxPhotoServings ? () => onServings(servings + 0.5) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
          // Read out after every step: how much, of what serving, and what
          // it comes to -- never a bare number.
          // Its own node, so only this line is the live region.
          Semantics(
            key: Key('snap.portion.${card.id}'),
            container: true,
            liveRegion: true,
            label: '${food.name}: ${formatServings(servings)} × ${food.servingDesc ?? 'serving'} · $kcal kcal',
            excludeSemantics: true,
            child: Text(
              '${formatServings(servings)} × ${food.servingDesc ?? 'serving'} · $kcal kcal',
              style: TextStyle(color: t.text2, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 48 dp tall box around a chip, so the chip's tap band has the room to
/// reach 48 dp in any row of a Wrap.
class _ChipRoom extends StatelessWidget {
  const _ChipRoom({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Align(widthFactor: 1, heightFactor: 1, child: child),
  );
}

/// An item the AI saw that isn't in FitSync's list: its name, a search
/// started from it, and ✕.
class PhotoUnlistedCard extends StatelessWidget {
  const PhotoUnlistedCard({
    super.key,
    required this.card,
    required this.onSearch,
    required this.onRemove,
  });

  final DraftCard card;
  final VoidCallback onSearch;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final name = card.unlistedName!;
    return FsCard(
      key: Key('snap.unlisted.${card.id}'),
      small: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('"$name" isn\'t in FitSync\'s list', style: TextStyle(color: t.text, fontWeight: FontWeight.w600)),
                ),
              ),
              IconButton(
                key: Key('snap.remove.${card.id}'),
                tooltip: 'Remove $name',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FsButton(
            key: Key('snap.unlisted.search.${card.id}'),
            label: 'Search for it',
            kind: FsButtonKind.secondary,
            small: true,
            icon: const Icon(Icons.search, size: 18),
            onPressed: onSearch,
          ),
        ],
      ),
    );
  }
}

/// The estimated kcal, protein, carbs and fat of everything on the list.
class PhotoTotalCard extends StatelessWidget {
  const PhotoTotalCard({super.key, required this.totals});

  final MacroTotals totals;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);
    // A Wrap, not a Row: at large text on a small phone the figure drops
    // under its label instead of running off the card. Heard as one item.
    Widget macro(String label, double grams, Color dot) => MergeSemantics(
      child: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // The colour only echoes the Nutrition card's bars; the label says it.
          ExcludeSemantics(
            child: Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          ),
          Text(label, style: TextStyle(color: t.text2, fontSize: 12)),
          Text('${grams.round()} g', style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return FsCard(
      key: const Key('snap.total'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text('Estimated total', style: theme.textTheme.titleMedium),
              Text('${totals.kcal} kcal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.accentText)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              macro('Protein', totals.proteinG, t.accent),
              macro('Carbs', totals.carbsG, t.blue),
              macro('Fat', totals.fatG, t.violet),
            ],
          ),
        ],
      ),
    );
  }
}
