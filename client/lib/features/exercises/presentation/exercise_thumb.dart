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
    this.animationUrl,
    this.animate = false,
    this.overlayAlignment = Alignment.center,
  });

  final double size;
  final String baseUrl;
  final String? thumbnailUrl;
  final String? equipment;
  final double radius;

  /// Drawn over the artwork -- the logger puts a play badge here, because the
  /// tile is also what opens the demo.
  final Widget? overlay;

  /// The exercise's looping demo (a server-relative GIF), played in place of
  /// the still artwork when [animate] is on. The logger's set table passes the
  /// URL the demo stage already loaded, so the tile is the cached image, not a
  /// second download.
  final String? animationUrl;

  /// Whether to play [animationUrl]. Off by default: the Plan tab's list stays
  /// still. Reduce Motion always wins -- the tile shows the still artwork.
  final bool animate;

  /// Where [overlay] sits; the logger moves its badge to a corner so it does
  /// not cover the movement.
  final AlignmentGeometry overlayAlignment;

  @override
  Widget build(BuildContext context) {
    final url = thumbnailUrl;
    final still = url == null
        ? _Placeholder(equipment: equipment, size: size)
        : Image.network(
            _join(url),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _Placeholder(equipment: equipment, size: size),
          );
    final gif = animationUrl;
    final playing =
        animate && gif != null && !MediaQuery.disableAnimationsOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (playing)
              Image.network(
                _join(gif),
                key: const ValueKey('thumb.animation'),
                fit: BoxFit.cover,
                // The still artwork until the first frame lands, and instead
                // of a GIF that will not load: the tile is never blank.
                frameBuilder: (_, child, frame, syncLoaded) =>
                    frame == null && !syncLoaded ? still : child,
                errorBuilder: (_, _, _) => still,
              )
            else
              still,
            if (overlay != null)
              Align(alignment: overlayAlignment, child: overlay),
          ],
        ),
      ),
    );
  }

  // `/plans/active` once returned a bare relative path
  // ("exercises/1460/thumb.jpg") where `/exercises` returns an absolute one,
  // which joined naively to "http://host:3000exer...". The server resolves
  // both through storage.url() now; the guard stays because the join should
  // not depend on that, and errorBuilder still covers a genuinely missing file.
  String _join(String path) =>
      '$baseUrl${path.startsWith('/') ? '' : '/'}$path';
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
