import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import 'equipment_icon.dart';

/// An exercise's artwork, square, falling back to its equipment icon.
///
/// Shared by the Plan tab's list and the logger's exercise card so the two
/// cannot drift: both need the same fallback and the same URL join, and the
/// join is the part that has already been got wrong once.
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb({
    super.key,
    required this.size,
    required this.baseUrl,
    this.thumbnailUrl,
    this.equipment,
    this.radius = FsRadius.sm,
    this.overlay,
  });

  final double size;
  final String baseUrl;
  final String? thumbnailUrl;
  final String? equipment;
  final double radius;

  /// Drawn over the artwork -- the logger puts a play badge here, because the
  /// tile is also what opens the demo.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final url = thumbnailUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url == null)
              _Placeholder(equipment: equipment, size: size)
            else
              // `/plans/active` once returned a bare relative path
              // ("exercises/1460/thumb.jpg") where `/exercises` returns an
              // absolute one, which joined naively to "http://host:3000exer...".
              // The server resolves both through storage.url() now; the guard
              // stays because the join should not depend on that, and
              // errorBuilder still covers a genuinely missing file.
              Image.network(
                '$baseUrl${url.startsWith('/') ? '' : '/'}$url',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _Placeholder(equipment: equipment, size: size),
              ),
            if (overlay != null) Center(child: overlay),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size, this.equipment});

  final double size;
  final String? equipment;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return Container(
      color: t.surface2,
      child: Icon(equipmentIcon(equipment), size: size * 0.42, color: t.text3),
    );
  }
}
