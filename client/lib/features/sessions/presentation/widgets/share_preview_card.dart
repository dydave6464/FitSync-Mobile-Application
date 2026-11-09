import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/share_preview.dart';

/// What the coach's page will open with: the window, then its number tiles,
/// two to a row. The prototype's "PDF report · Oct 1–28" card.
class SharePreviewCard extends StatelessWidget {
  const SharePreviewCard({
    super.key,
    required this.heading,
    required this.tiles,
  });

  /// "Week · Nov 3 – Nov 9".
  final String heading;
  final List<SharePreviewTile> tiles;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;

    return FsCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FsEyebrow(heading, maxLines: 2),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: 10,
                children: [
                  for (final tile in tiles)
                    SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tile.value,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          Text(
                            tile.label,
                            style: TextStyle(fontSize: 11.5, color: t.text2),
                          ),
                          if (tile.note != null)
                            // text2, not text3: text3 does not hold 4.5:1 on
                            // the accent card's tint (see FsTokens.text3).
                            Text(
                              tile.note!,
                              style: TextStyle(fontSize: 11.5, color: t.text2),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
