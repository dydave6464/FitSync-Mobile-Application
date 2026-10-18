import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart' show FsEyebrow;
import '../../domain/nutrition.dart';

/// One meal of the day: its foods under its name and subtotal, or, while it
/// has none, a single row to add to it.
class MealSection extends StatelessWidget {
  const MealSection({
    super.key,
    required this.mealType,
    required this.entries,
    required this.onAdd,
    required this.onDelete,
    required this.onChange,
    this.enabled = true,
    this.suggested = false,
  });

  final String mealType;
  final List<FoodEntry> entries;
  final VoidCallback onAdd;
  final ValueChanged<FoodEntry> onDelete;

  /// A food's row was tapped, to change its meal, servings or numbers.
  final ValueChanged<FoodEntry> onChange;
  final bool enabled;

  /// The meal the clock suggests, today only. It marks the empty row as the
  /// likely one -- a hint, not a choice made for the user.
  final bool suggested;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    if (entries.isEmpty) {
      return _AddRow(
        mealType: mealType,
        suggested: suggested,
        onAdd: enabled ? onAdd : null,
        t: t,
      );
    }
    final subtotal = entries.fold<int>(0, (a, e) => a + e.kcal);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: FsEyebrow(mealLabel(mealType).toUpperCase())),
              Text('$subtotal kcal', style: TextStyle(fontSize: 12, color: t.text3)),
              IconButton(
                key: Key('meal.add.$mealType'),
                // The same verb as the row it replaces once the meal has food.
                tooltip: 'Add to ${mealLabel(mealType).toLowerCase()}',
                onPressed: enabled ? onAdd : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          for (final e in entries)
            _EntryRow(
              entry: e,
              // A pending entry has no server id yet to change or delete.
              onChange: enabled && e.id > 0 ? () => onChange(e) : null,
              onDelete: enabled && e.id > 0 ? () => onDelete(e) : null,
              t: t,
            ),
        ],
      ),
    );
  }
}

/// One logged food, drawn as a small card. All of it but the ✕ is one
/// button that opens the food to change it; the ✕ stays its own button, so
/// a tap meant to remove never opens the sheet.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onChange, required this.onDelete, required this.t});

  final FoodEntry entry;
  final VoidCallback? onChange;
  final VoidCallback? onDelete;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Material(
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FsRadius.md),
        side: BorderSide(color: t.line),
      ),
      // Keeps the press inside the card's rounded corners.
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            // One node: name, serving and kcal are read together, then what
            // a tap does.
            child: Semantics(
              key: Key('entry.${e.id}'),
              container: true,
              button: true,
              enabled: onChange != null,
              onTap: onChange,
              onTapHint: onChange == null ? null : 'Change',
              child: InkWell(
                onTap: onChange,
                excludeFromSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 0, 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: LayoutBuilder(
                      builder: (context, box) => Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  [if (e.servingDesc != null) e.servingDesc!, if (e.servings != 1) '× ${formatServings(e.servings)}'].join(' '),
                                  style: TextStyle(fontSize: 12, color: t.text3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Its own width, up to a share of the row: at
                          // large text on a narrow phone it wraps rather
                          // than pushing the row past the edge.
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.4),
                            child: Text('${e.kcal} kcal',
                                textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              key: Key('entry.delete.${e.id}'),
              tooltip: 'Remove ${e.name}',
              onPressed: onDelete,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// An empty meal: four rows of "0 kcal +" said nothing, so it is one row
/// that says what to do, the whole of it a 48 dp target. Dashed and quiet;
/// the suggested meal's is outlined in green, bolder and named so for a
/// screen reader, so the hint is not carried by colour alone.
class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.mealType,
    required this.suggested,
    required this.onAdd,
    required this.t,
  });

  final String mealType;
  final bool suggested;
  final VoidCallback? onAdd;
  final FsTokens t;

  @override
  Widget build(BuildContext context) {
    final words = 'Add ${mealLabel(mealType).toLowerCase()}';
    // Off while the day loads, and it shows: dimmed, and no green invitation
    // to a tap that would do nothing.
    final live = onAdd != null;
    final highlighted = suggested && live;
    final colour = !live ? t.text3 : (highlighted ? t.accentText : t.text2);
    final radius = BorderRadius.circular(FsRadius.md);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // One button node: the words and the InkWell's tap merge into it, so a
      // screen reader both hears the row and can press it.
      child: Semantics(
        container: true,
        button: true,
        enabled: live,
        hint: highlighted ? 'Suggested for now' : null,
        child: CustomPaint(
          // Dashed for an empty slot; the suggested one is a solid outline.
          painter: highlighted
              ? null
              : _DashedBorder(colour: t.line2, radius: FsRadius.md),
          child: Material(
            color: highlighted ? t.accentDim : Colors.transparent,
            // The text green, not the faint tint: solid against dashed has
            // to read beside colour for someone who cannot tell the greens.
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: highlighted
                  ? BorderSide(color: t.accentText, width: 1.5)
                  : BorderSide.none,
            ),
            child: InkWell(
              key: Key('meal.add.$mealType'),
              onTap: onAdd,
              borderRadius: radius,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 18, color: colour),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          words,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
                            color: colour,
                          ),
                        ),
                      ),
                    ],
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

/// A dashed rounded outline, as the prototype draws an empty slot.
class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.colour, required this.radius});

  final Color colour;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ).deflate(0.6));
    for (final PathMetric metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.colour != colour || old.radius != radius;
}
