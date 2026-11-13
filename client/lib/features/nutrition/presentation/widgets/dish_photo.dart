import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme.dart';

/// A dish's photo, at a fixed size, clipped to [radius] (spec 2026-11-13,
/// round 3, 1.1). Decorative: the dish's name is always beside it, so a
/// screen reader never meets it.
///
/// While it loads, a plain `surface2` box of the same size holds its place
/// (no spinner, nothing jumps); the first frame then fades in over 150 ms,
/// at once with reduced motion. No [url], or a photo that fails, shows the
/// leaf tile -- or, with [fallback] false (the Log sheet's banner), nothing
/// at all, taking no space: not even its [bottomMargin].
class DishPhoto extends StatelessWidget {
  const DishPhoto({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = FsRadius.sm,
    this.fallback = true,
    this.bottomMargin = 0,
  });

  /// A full URL; null when the dish has no photo.
  final String? url;
  final double width;
  final double height;
  final double radius;

  /// The leaf tile when there is no photo; false: nothing.
  final bool fallback;

  /// Space under the photo, its placeholder or the leaf, drawn only with
  /// them: a banner that collapses leaves no gap behind.
  final double bottomMargin;

  /// The image for [url], decoded at [cacheWidth] x [cacheHeight] pixels
  /// (the box's size on screen). Null: fetched from the network. A widget
  /// test sets it so no image is fetched, and sets it back to null after.
  @visibleForTesting
  static ImageProvider Function(String url, int cacheWidth, int cacheHeight)? debugImage;

  static const _fade = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final Widget child;
    if (url == null) {
      if (!fallback) return const SizedBox.shrink();
      child = _leaf(context);
    } else {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheWidth = (width * dpr).round();
      final cacheHeight = (height * dpr).round();
      child = Image(
        key: const Key('dish.photo'),
        image: debugImage?.call(url, cacheWidth, cacheHeight) ?? _network(url, cacheWidth, cacheHeight),
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        gaplessPlayback: true,
        frameBuilder: (context, image, frame, sync) {
          if (frame == null && !sync) {
            return _box(key: const Key('dish.loading'), child: ColoredBox(color: context.fs.surface2));
          }
          // A photo already in memory was never a placeholder: no fade.
          if (sync || MediaQuery.disableAnimationsOf(context)) return _box(child: image);
          return _box(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: _fade,
              builder: (_, opacity, image) => Opacity(opacity: opacity, child: image),
              child: image,
            ),
          );
        },
        // Not wrapped by frameBuilder: with no fallback the area is gone.
        errorBuilder: (context, _, _) => fallback ? _leaf(context) : const SizedBox.shrink(),
      );
    }
    return ExcludeSemantics(child: child);
  }

  /// Decoded no larger than the box needs, keeping the photo's shape:
  /// fitted into a square of the box's longer side, so a square photo still
  /// covers a 16:9 box sharply rather than being squashed into it.
  static ImageProvider _network(String url, int cacheWidth, int cacheHeight) {
    final side = math.max(cacheWidth, cacheHeight);
    return ResizeImage(NetworkImage(url), width: side, height: side, policy: ResizeImagePolicy.fit);
  }

  Widget _box({Key? key, required Widget child}) => Padding(
    padding: EdgeInsets.only(bottom: bottomMargin),
    child: SizedBox(
      key: key,
      width: width,
      height: height,
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
    ),
  );

  /// The leaf tile: what a dish without a photo shows.
  Widget _leaf(BuildContext context) {
    final t = context.fs;
    return _box(
      key: const Key('dish.leaf'),
      child: ColoredBox(
        color: t.surface2,
        child: Center(child: Icon(Icons.eco_outlined, size: math.min(width, height) * 0.42, color: t.accentText)),
      ),
    );
  }
}
